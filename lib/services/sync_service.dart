import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import '../models/models.dart';
import '../core/config/api_config.dart';
import 'dart:developer' as dev;
import 'dart:io';

class SyncDetails {
  final String lastSyncTime;
  final int customersUploaded;
  final int invoicesUploaded;
  final int customersDownloaded;
  final int invoicesDownloaded;
  final List<String> mergedCustomers;

  SyncDetails({
    required this.lastSyncTime,
    required this.customersUploaded,
    required this.invoicesUploaded,
    required this.customersDownloaded,
    required this.invoicesDownloaded,
    required this.mergedCustomers,
  });

  Map<String, dynamic> toJson() => {
    'lastSyncTime': lastSyncTime,
    'customersUploaded': customersUploaded,
    'invoicesUploaded': invoicesUploaded,
    'customersDownloaded': customersDownloaded,
    'invoicesDownloaded': invoicesDownloaded,
    'mergedCustomers': mergedCustomers,
  };

  factory SyncDetails.fromJson(Map<String, dynamic> json) => SyncDetails(
    lastSyncTime: json['lastSyncTime'] ?? 'غير معروف',
    customersUploaded: json['customersUploaded'] ?? 0,
    invoicesUploaded: json['invoicesUploaded'] ?? 0,
    customersDownloaded: json['customersDownloaded'] ?? 0,
    invoicesDownloaded: json['invoicesDownloaded'] ?? 0,
    mergedCustomers: List<String>.from(json['mergedCustomers'] ?? []),
  );
}

class SyncService extends ChangeNotifier {
  final DatabaseService _dbService;
  final SharedPreferences _prefs;
  late final Dio _dio;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  SyncDetails? _lastSyncDetails;
  SyncDetails? get lastSyncDetails => _lastSyncDetails;

  SyncService(this._dbService, this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _prefs.getString('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));

    _loadLastSyncDetails();
    checkConnectivity();
  }

  void _loadLastSyncDetails() {
    final data = _prefs.getString('last_sync_details_v2');
    if (data != null) {
      try {
        _lastSyncDetails = SyncDetails.fromJson(jsonDecode(data));
      } catch (e) {
        dev.log('Error loading sync details: $e');
      }
    }
  }

  Future<void> _saveSyncDetails(SyncDetails details) async {
    _lastSyncDetails = details;
    await _prefs.setString('last_sync_details_v2', jsonEncode(details.toJson()));
    notifyListeners();
  }

  Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      _isOffline = result.isEmpty || result[0].rawAddress.isEmpty;
    } catch (_) {
      _isOffline = true;
    }
    notifyListeners();
    return !_isOffline;
  }

  Future<void> performFullSync({bool isInitialSync = false}) async {
    if (_isSyncing) return;
    
    bool hasInternet = await checkConnectivity();
    if (!hasInternet) {
      dev.log('Sync aborted: No internet connection.', name: 'SyncService');
      _isOffline = true;
      notifyListeners();
      throw Exception('أنت غير متصل بالإنترنت. يرجى التحقق من الاتصال للمزامنة.');
    }

    _isSyncing = true;
    notifyListeners();

    try {
      dev.log('Starting HQ Delta Sync. Initial sync: $isInitialSync', name: 'SyncService');

      final lastSyncTime = isInitialSync ? null : _prefs.getString('last_sync_time');
      final payload = await _prepareSyncPayload();

      int custUp = payload['users']?.length ?? 0;
      int invUp = payload['invoices']?.length ?? 0;

      final response = await _dio.post('sync/receive', data: {
        'data': payload,
        'last_sync_time': lastSyncTime,
      });

      final responseData = response.data is String ? jsonDecode(response.data) : response.data;
      final success = responseData['success'];
      final isSuccess = success == true || success == 'true' || success == 1;

      if (response.statusCode == 200 && isSuccess) {
        final pullData = responseData['pull_data'] as Map<String, dynamic>?;
        final serverTimestamp = responseData['timestamp'] as String?;
        final remappedUuids = responseData['remapped_uuids'] as Map<String, dynamic>?;

        if (pullData == null || serverTimestamp == null) {
          throw Exception('استجابة غير صالحة من السيرفر: بيانات المزامنة ناقصة');
        }

        int custDown = pullData['users']?.length ?? 0;
        int invDown = pullData['invoices']?.length ?? 0;
        List<String> mergedNames = [];

        final tablesOrder = ['payment_methods', 'purchase_methods', 'users', 'invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history'];

        final db = await _dbService.database;
        await db.transaction((txn) async {
          // 0. Handle Remapped UUIDs (e.g., from customer merges)
          if (remappedUuids != null && remappedUuids.isNotEmpty) {
            for (var entry in remappedUuids.entries) {
              final oldUuid = entry.key;
              final newUuid = entry.value;
              await _handleUuidRemapping(oldUuid, newUuid, txn);
            }
          }

          // 1. Process Pull Data
          for (var table in tablesOrder) {
            if (pullData.containsKey(table)) {
              final items = pullData[table];
              if (items is List) {
                for (var itemData in items) {
                  try {
                    final standardized = Map<String, dynamic>.from(itemData);
                    final resolvedItem = await _resolveRelationsInTxn(table, standardized, txn);

                    if (table == 'users') {
                      final name = resolvedItem['name'];
                      final uuid = resolvedItem['uuid'];
                      final existing = await txn.query('users', where: 'name = ? AND uuid != ?', whereArgs: [name, uuid]);
                      if (existing.isNotEmpty) {
                        mergedNames.add(name);
                      }
                    }

                    await _dbService.upsertFromSyncInTxn(table, resolvedItem, txn);
                  } catch (itemError) {
                    dev.log('Error processing item in table $table: $itemError', name: 'SyncService', error: itemError);
                    rethrow;
                  }
                }
              }
            }
          }

          // 2. Mark pushed items as synced
          for (var table in payload.keys) {
            final List items = payload[table]!;
            final uuids = items.map((e) => e['uuid'] as String).toList();
            if (uuids.isNotEmpty) {
              await txn.update(table, {'is_synced': 1},
                where: "uuid IN (${uuids.map((_) => '?').join(', ')})",
                whereArgs: uuids);
            }
          }
        });

        await _dbService.recalculateAllBalances();
        await _prefs.setString('last_sync_time', serverTimestamp);

        await _saveSyncDetails(SyncDetails(
          lastSyncTime: serverTimestamp,
          customersUploaded: custUp,
          invoicesUploaded: invUp,
          customersDownloaded: custDown,
          invoicesDownloaded: invDown,
          mergedCustomers: mergedNames,
        ));

        dev.log('HQ Delta Sync completed successfully at $serverTimestamp.', name: 'SyncService');
      } else {
        String errorMsg = responseData['message'] ?? 'Unknown server error';
        dev.log('Sync failed on server: $errorMsg', name: 'SyncService');
        throw Exception(errorMsg);
      }
    } on DioException catch (e) {
      String message = 'فشلت المزامنة بسبب مشكلة في الشبكة';
      if (e.type == DioExceptionType.connectionTimeout) message = 'انتهت مهلة الاتصال بالسيرفر';
      if (e.response?.statusCode == 401) message = 'انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول';
      if (e.response?.statusCode == 500) message = 'خطأ داخلي في السيرفر (500)';

      dev.log('Sync failed (Network): ${e.message}', name: 'SyncService');
      throw Exception(message);
    } catch (e) {
      dev.log('Sync failed (General): $e', name: 'SyncService', error: e);
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _handleUuidRemapping(String oldUuid, String newUuid, dynamic txn) async {
    dev.log('Remapping UUID: $oldUuid -> $newUuid', name: 'SyncService');
    
    // 1. Update the record itself if it exists locally
    // We check multiple tables but primarily 'users' for customer merges
    final tables = ['users', 'invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history'];
    for (var table in tables) {
      await txn.update(table, {'uuid': newUuid, 'is_synced': 1}, where: 'uuid = ?', whereArgs: [oldUuid]);
    }

    // 2. Update foreign key references in other tables
    // This is handled by the server during pull, but we do it locally for immediate consistency
    await txn.update('invoices', {'user_uuid': newUuid}, where: 'user_uuid = ?', whereArgs: [oldUuid]);
    await txn.update('transactions', {'buyer_uuid': newUuid}, where: 'buyer_uuid = ?', whereArgs: [oldUuid]);
    await txn.update('transactions', {'invoice_uuid': newUuid}, where: 'invoice_uuid = ?', whereArgs: [oldUuid]);
    // Add other FK relations as needed
  }

  Future<Map<String, List<Map<String, dynamic>>>> _prepareSyncPayload() async {
    final Map<String, List<Map<String, dynamic>>> payload = {};
    final tables = ['payment_methods', 'purchase_methods', 'users', 'invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history'];
    
    for (var table in tables) {
      final unsynced = await _dbService.getUnsynced(table);
      if (unsynced.isNotEmpty) {
        payload[table] = await Future.wait(unsynced.map((item) async {
          final map = Map<String, dynamic>.from(item);
          return await _replaceIdsWithUuids(table, map);
        }));
      }
    }
    return payload;
  }

  Future<Map<String, dynamic>> _replaceIdsWithUuids(String table, Map<String, dynamic> item) async {
    final db = await _dbService.database;
    item.remove('id');

    if (table == 'invoices') {
      if (item['user_id'] != null) {
        final r = await db.query('users', columns: ['uuid'], where: 'id = ?', whereArgs: [item['user_id']]);
        if (r.isNotEmpty) item['user_uuid'] = r.first['uuid'];
        item.remove('user_id');
      }
      if (item['payment_method_id'] != null) {
        final r = await db.query('payment_methods', columns: ['uuid'], where: 'id = ?', whereArgs: [item['payment_method_id']]);
        if (r.isNotEmpty) item['payment_method_uuid'] = r.first['uuid'];
        item.remove('payment_method_id');
      }
    } else if (table == 'transactions') {
      if (item['buyer_id'] != null) {
        final r = await db.query('users', columns: ['uuid'], where: 'id = ?', whereArgs: [item['buyer_id']]);
        if (r.isNotEmpty) item['buyer_uuid'] = r.first['uuid'];
        item.remove('buyer_id');
      }
      if (item['invoice_id'] != null) {
        final r = await db.query('invoices', columns: ['uuid'], where: 'id = ?', whereArgs: [item['invoice_id']]);
        if (r.isNotEmpty) item['invoice_uuid'] = r.first['uuid'];
        item.remove('invoice_id');
      }
      if (item['payment_method_id'] != null) {
        final r = await db.query('payment_methods', columns: ['uuid'], where: 'id = ?', whereArgs: [item['payment_method_id']]);
        if (r.isNotEmpty) item['payment_method_uuid'] = r.first['uuid'];
        item.remove('payment_method_id');
      }
    } else if (table == 'purchases') {
      if (item['payment_method_id'] != null) {
        final r = await db.query('payment_methods', columns: ['uuid'], where: 'id = ?', whereArgs: [item['payment_method_id']]);
        if (r.isNotEmpty) item['payment_method_uuid'] = r.first['uuid'];
        item.remove('payment_method_id');
      }
    } else if (table == 'users') {
      if (item['parent_id'] != null) {
        final r = await db.query('users', columns: ['uuid'], where: 'id = ?', whereArgs: [item['parent_id']]);
        if (r.isNotEmpty) item['parent_uuid'] = r.first['uuid'];
        item.remove('parent_id');
      }
    }
    return item;
  }

  Future<Map<String, dynamic>> _resolveRelationsInTxn(String table, Map<String, dynamic> data, dynamic txn) async {
    final map = Map<String, dynamic>.from(data);

    final relations = {
        'user_uuid': ['users', 'user_id'],
        'buyer_uuid': ['users', 'buyer_id'],
        'invoice_uuid': ['invoices', 'invoice_id'],
        'payment_method_uuid': ['payment_methods', 'payment_method_id'],
        'parent_uuid': ['users', 'parent_id'],
    };

    for (var entry in relations.entries) {
        final uuidKey = entry.key;
        if (map.containsKey(uuidKey) && map[uuidKey] != null) {
            final targetTable = entry.value[0];
            final idKey = entry.value[1];
            final r = await txn.query(targetTable, columns: ['id'], where: 'uuid = ?', whereArgs: [map[uuidKey]]);
            if (r.isNotEmpty) {
              map[idKey] = r.first['id'];
            } else {
              dev.log('Warning: Could not resolve $uuidKey (${map[uuidKey]}) for table $table locally.', name: 'SyncService');
            }
            map.remove(uuidKey);
        }
    }
    return map;
  }
}
