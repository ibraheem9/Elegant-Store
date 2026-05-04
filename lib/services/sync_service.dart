import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import '../models/models.dart';
import '../core/config/api_config.dart';
import '../utils/timestamp_formatter.dart';
import 'dart:developer' as dev;
import 'package:uuid/uuid.dart';
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

  // ── Auto-sync timer ──────────────────────────────────────────────────────
  Timer? _autoSyncTimer;
  static const Duration _autoSyncInterval = Duration(minutes: 3);

  /// Tables that contain parent records (no FK dependencies on other tables).
  /// These must be written FIRST so child tables can resolve their FKs.
  static const List<String> _parentTables = [
    'payment_methods',
    'users',
  ];

  /// Tables that depend on parent tables via FK.
  static const List<String> _childTables = [
    'invoices',
    'transactions',
    'purchases',
    'daily_statistics',
    'edit_history',
  ];

  /// Full ordered list for push payload preparation.
  static const List<String> _tableOrder = [
    'payment_methods',
    'users',
    'invoices',
    'transactions',
    'purchases',
    'daily_statistics',
    'edit_history',
  ];

  SyncService(this._dbService, this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
        // ModSecurity on the server blocks requests with no User-Agent (HTTP 406)
        'User-Agent': 'ElegantStore/1.0 (Dart/3.5; Android)',
      },
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

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-SYNC TIMER
  // ─────────────────────────────────────────────────────────────────────────

  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) async {
      final hasInternet = await checkConnectivity();
      if (!hasInternet || _isSyncing) return;
      dev.log('Auto-sync triggered.', name: 'SyncService');
      try {
        await performFullSync();
      } catch (e) {
        dev.log('Auto-sync failed silently: $e', name: 'SyncService');
      }
    });
    dev.log('Auto-sync timer started (interval: ${_autoSyncInterval.inMinutes} min).', name: 'SyncService');
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    dev.log('Auto-sync timer stopped.', name: 'SyncService');
  }

  Future<void> syncBeforeLogout() async {
    stopAutoSync();
    final hasInternet = await checkConnectivity();
    if (!hasInternet) return;
    try {
      await performFullSync();
    } catch (e) {
      dev.log('Pre-logout sync failed (non-blocking): $e', name: 'SyncService');
    }
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
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      _isOffline = result.isEmpty || result[0].rawAddress.isEmpty;
    } catch (_) {
      _isOffline = true;
    }
    notifyListeners();
    return !_isOffline;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SAFE TYPE HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _safeMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isEmpty) return {};
    return null;
  }

  String? _safeString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  bool _isSuccessResponse(dynamic success) =>
      success == true || success == 'true' || success == 1;

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN SYNC ENTRY POINT
  // ─────────────────────────────────────────────────────────────────────────


  // ─────────────────────────────────────────────────────────────────────────
  // DEVICE ID
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the device ID stored in SharedPreferences.
  /// If none exists yet (first run before DeviceSyncService has initialised),
  /// generates a UUID, persists it, and returns it.
  Future<String> _getOrCreateDeviceId() async {
    final saved = _prefs.getString('device_id');
    if (saved != null && saved.isNotEmpty) return saved;
    final newId = const Uuid().v4();
    await _prefs.setString('device_id', newId);
    return newId;
  }

  Future<void> performFullSync({bool isInitialSync = false}) async {
    if (_isSyncing) return;

    final bool hasInternet = await checkConnectivity();
    if (!hasInternet) {
      _isOffline = true;
      notifyListeners();
      throw Exception('أنت غير متصل بالإنترنت. يرجى التحقق من الاتصال للمزامنة.');
    }

    _isSyncing = true;
    notifyListeners();

    try {
      dev.log('Starting sync. Initial: $isInitialSync', name: 'SyncService');

      final String? lastSyncTime =
          isInitialSync ? null : _prefs.getString('last_sync_time');

      final payload = await _prepareSyncPayload();
      final int custUp = payload['users']?.length ?? 0;
      final int invUp  = payload['invoices']?.length ?? 0;

      final deviceId = await _getOrCreateDeviceId();
      final response = await _dio.post('sync/receive', data: {
        'data': payload,
        'last_sync_time': lastSyncTime,
        'device_id': deviceId,
      });

      final responseData = response.data is String
          ? jsonDecode(response.data)
          : response.data;

      final bool isSuccess = _isSuccessResponse(responseData['success']);

      if (response.statusCode == 200 && isSuccess) {
        final pullData = _safeMap(responseData['pull_data']);
        final String? serverTimestamp =
            _safeString(responseData['timestamp']) ??
            _safeString(responseData['server_time']);
        final remappedUuids = _safeMap(responseData['remapped_uuids']);

        if (pullData == null || serverTimestamp == null) {
          throw Exception('استجابة غير صالحة من السيرفر: بيانات المزامنة ناقصة');
        }

        final int custDown = (pullData['users'] as List?)?.length ?? 0;
        final int invDown  = (pullData['invoices'] as List?)?.length ?? 0;
        final List<String> mergedNames = [];

        // Apply UUID remappings first (outside transaction for safety)
        final db = await _dbService.database;
        if (remappedUuids != null && remappedUuids.isNotEmpty) {
          await db.transaction((txn) async {
            for (final entry in remappedUuids.entries) {
              final newUuid = entry.value?.toString();
              if (newUuid != null && newUuid.isNotEmpty) {
                await _applyUuidRemap(entry.key, newUuid, txn);
              }
            }
          });
        }

        // ── Two-pass pull: parents first, then children ────────────────────
        // Pass 1: write payment_methods and users so FK resolution works
        await _writePullPass(
          db: db,
          pullData: pullData,
          tables: _parentTables,
          mergedNames: mergedNames,
        );

        // Pass 2: write child tables (invoices, transactions, etc.)
        // At this point all users and payment_methods are in local DB.
        await _writePullPass(
          db: db,
          pullData: pullData,
          tables: _childTables,
          mergedNames: mergedNames,
        );

        // Mark pushed items as synced
        await db.transaction((txn) async {
          for (final table in payload.keys) {
            final uuids = payload[table]!
                .where((e) => e['uuid'] != null)
                .map((e) => e['uuid'] as String)
                .toList();
            if (uuids.isNotEmpty) {
              await txn.update(
                table,
                {'is_synced': 1},
                where: 'uuid IN (${List.filled(uuids.length, '?').join(', ')})',
                whereArgs: uuids,
              );
            }
          }
        });

        await _dbService.recalculateAllBalances();
        final localTimestamp = TimestampFormatter.nowUtc();
        await _prefs.setString('last_sync_time', serverTimestamp); // keep server version for next sync request
        await _prefs.setString('last_sync_time_local', localTimestamp); // local version for display

        await _saveSyncDetails(SyncDetails(
          lastSyncTime: localTimestamp,
          customersUploaded: custUp,
          invoicesUploaded: invUp,
          customersDownloaded: custDown,
          invoicesDownloaded: invDown,
          mergedCustomers: mergedNames,
        ));

        dev.log('Sync completed at $serverTimestamp.', name: 'SyncService');
      } else {
        final String errorMsg =
            responseData['message'] as String? ?? 'Unknown server error';
        throw Exception(errorMsg);
      }
    } on DioException catch (e) {
      String message = 'فشلت المزامنة بسبب مشكلة في الشبكة';
      if (e.type == DioExceptionType.connectionTimeout) {
        message = 'انتهت مهلة الاتصال بالسيرفر';
      } else if (e.response?.statusCode == 401) {
        message = 'انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول';
      } else if (e.response?.statusCode == 500) {
        final serverMsg = e.response?.data is Map
            ? (e.response!.data['message'] ?? 'خطأ داخلي في السيرفر (500)')
            : 'خطأ داخلي في السيرفر (500)';
        message = serverMsg.toString();
      }
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

  // ─────────────────────────────────────────────────────────────────────────
  // TWO-PASS PULL WRITER
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes a set of tables from [pullData] into the local DB.
  ///
  /// Each table is written in its own transaction so a failure in one table
  /// does not roll back the others. Within each table, failures on individual
  /// records are logged and skipped rather than aborting the whole table.
  ///
  /// Child tables that fail FK resolution (user_id = null) are deferred and
  /// retried once after all tables in this pass have been written.
  Future<void> _writePullPass({
    required dynamic db,
    required Map<String, dynamic> pullData,
    required List<String> tables,
    required List<String> mergedNames,
  }) async {
    // Collect deferred items: {table -> [item]} for FK-retry pass
    final Map<String, List<Map<String, dynamic>>> deferred = {};

    for (final table in tables) {
      final rawItems = pullData[table];
      if (rawItems == null || rawItems is! List || rawItems.isEmpty) continue;

      final List<Map<String, dynamic>> failedItems = [];

      // Using multiple small transactions instead of one giant one per table.
      // This ensures that if one record fails, others in the same table still sync.
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);

        await db.transaction((txn) async {
          try {
            if (table == 'users') {
              final name = item['name'];
              final uuid = item['uuid'];
              if (name != null && uuid != null) {
                final dup = await txn.query('users',
                    where: 'name = ? AND uuid != ?',
                    whereArgs: [name, uuid]);
                if (dup.isNotEmpty) mergedNames.add(name.toString());
              }
            }

            final resolved = await _resolveRelationsInTxn(table, item, txn);

            // Detect unresolved critical FK (user_id for invoices/transactions)
            if (_hasCriticalNullFk(table, resolved)) {
              dev.log(
                'Deferred $table item (unresolved FK): ${item['uuid']}',
                name: 'SyncService',
              );
              failedItems.add(item);
              return; // skip this item in this pass
            }

            await _dbService.upsertFromSyncInTxn(table, resolved, txn);
          } catch (itemError) {
            dev.log(
              'Error on $table item ${item['uuid']}: $itemError — skipping',
              name: 'SyncService',
            );
            // We don't add to failedItems here because it's a real error, not just an FK dependency
          }
        });
      }

      if (failedItems.isNotEmpty) {
        deferred[table] = failedItems;
      }
    }

    // ── Deferred retry pass ────────────────────────────────────────────────
    // At this point all parent records should be in the DB.
    if (deferred.isNotEmpty) {
      dev.log(
        'Retrying ${deferred.values.fold(0, (s, l) => s + l.length)} deferred items…',
        name: 'SyncService',
      );

      for (final entry in deferred.entries) {
        final table = entry.key;
        final items = entry.value;

        for (final item in items) {
          await db.transaction((txn) async {
            try {
              final resolved = await _resolveRelationsInTxn(table, item, txn);
              await _dbService.upsertFromSyncInTxn(table, resolved, txn);
              dev.log('Retry succeeded for $table item ${item['uuid']}', name: 'SyncService');
            } catch (retryError) {
              dev.log(
                'Retry failed for $table item ${item['uuid']}: $retryError — permanently skipped',
                name: 'SyncService',
              );
            }
          });
        }
      }
    }
  }

  /// Returns true if [table] has a critical NOT NULL FK that resolved to null.
  bool _hasCriticalNullFk(String table, Map<String, dynamic> data) {
    switch (table) {
      case 'invoices':
        return data['user_id'] == null;
      case 'transactions':
        return data['buyer_id'] == null;
      case 'edit_history':
        return data['edited_by_id'] == null;
      default:
        return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UUID REMAPPING
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _applyUuidRemap(
      String oldUuid, String newUuid, dynamic txn) async {
    dev.log('Remapping UUID: $oldUuid → $newUuid', name: 'SyncService');

    final oldRows = await txn.rawQuery(
      'SELECT id FROM users WHERE uuid = ? LIMIT 1',
      [oldUuid],
    );
    final newRows = await txn.rawQuery(
      'SELECT id FROM users WHERE uuid = ? LIMIT 1',
      [newUuid],
    );

    final bool oldExists = oldRows.isNotEmpty;
    final bool newExists = newRows.isNotEmpty;

    if (oldExists && newExists) {
      final int oldId = oldRows.first['id'] as int;
      final int newId = newRows.first['id'] as int;

      if (oldId != newId) {
        dev.log(
          'Both UUIDs exist locally — re-pointing FKs ($oldId → $newId)',
          name: 'SyncService',
        );
        await txn.rawUpdate(
            'UPDATE invoices SET user_id = ? WHERE user_id = ?',
            [newId, oldId]);
        await txn.rawUpdate(
            'UPDATE transactions SET buyer_id = ? WHERE buyer_id = ?',
            [newId, oldId]);
        await txn.rawDelete('DELETE FROM users WHERE id = ?', [oldId]);
      }
    } else if (oldExists && !newExists) {
      await txn.rawUpdate(
        'UPDATE users SET uuid = ?, is_synced = 1 WHERE uuid = ?',
        [newUuid, oldUuid],
      );
      for (final table in _tableOrder) {
        if (table == 'users') continue;
        await txn.rawUpdate(
          'UPDATE $table SET uuid = ?, is_synced = 1 WHERE uuid = ?',
          [newUuid, oldUuid],
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUSH PAYLOAD PREPARATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, List<Map<String, dynamic>>>> _prepareSyncPayload() async {
    final Map<String, List<Map<String, dynamic>>> payload = {};
    final db = await _dbService.database;

    for (final table in _tableOrder) {
      final unsynced = await _dbService.getUnsynced(table);
      if (unsynced.isEmpty) continue;

      final Map<String, Map<int, String>> uuidCache = {};

      Future<Map<int, String>> buildCache(String fromTable, List<int> ids) async {
        if (ids.isEmpty) return {};
        final placeholders = List.filled(ids.length, '?').join(', ');
        final rows = await db.rawQuery(
          'SELECT id, uuid FROM $fromTable WHERE id IN ($placeholders)',
          ids,
        );
        return {for (final r in rows) r['id'] as int: r['uuid'] as String};
      }

      switch (table) {
        case 'invoices':
          final userIds = unsynced.map((r) => r['user_id'] as int?).whereType<int>().toSet().toList();
          final pmIds   = unsynced.map((r) => r['payment_method_id'] as int?).whereType<int>().toSet().toList();
          uuidCache['users']           = await buildCache('users', userIds);
          uuidCache['payment_methods'] = await buildCache('payment_methods', pmIds);
          break;
        case 'transactions':
          final buyerIds = unsynced.map((r) => r['buyer_id'] as int?).whereType<int>().toSet().toList();
          final invIds   = unsynced.map((r) => r['invoice_id'] as int?).whereType<int>().toSet().toList();
          final pmIds    = unsynced.map((r) => r['payment_method_id'] as int?).whereType<int>().toSet().toList();
          uuidCache['users']           = await buildCache('users', buyerIds);
          uuidCache['invoices']        = await buildCache('invoices', invIds);
          uuidCache['payment_methods'] = await buildCache('payment_methods', pmIds);
          break;
        case 'purchases':
          final pmIds = unsynced.map((r) => r['payment_method_id'] as int?).whereType<int>().toSet().toList();
          uuidCache['payment_methods'] = await buildCache('payment_methods', pmIds);
          break;
        case 'users':
          final parentIds = unsynced.map((r) => r['parent_id'] as int?).whereType<int>().toSet().toList();
          uuidCache['users'] = await buildCache('users', parentIds);
          break;
        case 'edit_history':
          final editorIds = unsynced.map((r) => r['edited_by_id'] as int?).whereType<int>().toSet().toList();
          uuidCache['users'] = await buildCache('users', editorIds);
          break;
      }

      payload[table] = unsynced.map((rawItem) {
        final item = Map<String, dynamic>.from(rawItem);
        item.remove('id');
        switch (table) {
          case 'invoices':
            item['user_uuid']           = uuidCache['users']?[item['user_id'] as int?];
            item['payment_method_uuid'] = uuidCache['payment_methods']?[item['payment_method_id'] as int?];
            item.remove('user_id');
            item.remove('payment_method_id');
            break;
          case 'transactions':
            item['buyer_uuid']          = uuidCache['users']?[item['buyer_id'] as int?];
            item['invoice_uuid']        = uuidCache['invoices']?[item['invoice_id'] as int?];
            item['payment_method_uuid'] = uuidCache['payment_methods']?[item['payment_method_id'] as int?];
            item.remove('buyer_id');
            item.remove('invoice_id');
            item.remove('payment_method_id');
            break;
          case 'purchases':
            item['payment_method_uuid'] = uuidCache['payment_methods']?[item['payment_method_id'] as int?];
            item.remove('payment_method_id');
            break;
          case 'users':
            {
              item['parent_uuid'] = uuidCache['users']?[item['parent_id'] as int?];
              item.remove('parent_id');
              final role     = item['role'] as String? ?? '';
              final isSynced = (item['is_synced'] as int? ?? 1) == 1;
              final hasPass  = (item['password'] as String?)?.isNotEmpty == true;
              if (role == 'ACCOUNTANT' && !isSynced && hasPass) {
                // Keep plain-text password so server can hash it
              } else {
                item.remove('password');
              }
            }
            break;
          case 'edit_history':
            item['edited_by_uuid'] = uuidCache['users']?[item['edited_by_id'] as int?];
            item.remove('edited_by_id');
            break;
        }
        return item;
      }).toList();
    }
    return payload;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FK RESOLUTION (PULL)
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _resolveRelationsInTxn(
      String table, Map<String, dynamic> data, dynamic txn) async {
    final map = Map<String, dynamic>.from(data);

    final Map<String, List<String>> relations = {
      'user_uuid':           ['users',           'user_id'],
      'buyer_uuid':          ['users',           'buyer_id'],
      'invoice_uuid':        ['invoices',        'invoice_id'],
      'payment_method_uuid': ['payment_methods', 'payment_method_id'],
      'parent_uuid':         ['users',           'parent_id'],
      'edited_by_uuid':      ['users',           'edited_by_id'],
    };

    for (final entry in relations.entries) {
      final uuidKey = entry.key;
      if (!map.containsKey(uuidKey)) continue;

      final targetUuid  = map[uuidKey];
      final targetTable = entry.value[0];
      final idKey       = entry.value[1];

      if (targetUuid != null) {
        final rows = await txn.rawQuery(
          'SELECT id FROM $targetTable WHERE uuid = ? LIMIT 1',
          [targetUuid],
        );
        map[idKey] = rows.isNotEmpty ? rows.first['id'] as int : null;

        if (rows.isEmpty) {
          dev.log(
            'Cannot resolve $uuidKey ($targetUuid) in $table — parent not yet in local DB.',
            name: 'SyncService',
          );
        }
      } else {
        map[idKey] = null;
      }

      map.remove(uuidKey);
    }

    return map;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FULL RESTORE  (POST sync/restore)
  // ─────────────────────────────────────────────────────────────────────────

  /// Downloads ALL store data from the server (including soft-deleted records)
  /// and writes it to the local DB using the same two-pass strategy as
  /// [performFullSync] to guarantee FK integrity.
  Future<void> performFullRestore() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      dev.log('Starting full restore from server…', name: 'SyncService');

      // Note: baseUrl already ends with '/api/' — use relative path (no leading slash)
      final response = await _dio.post('sync/restore');
      final responseData = response.data is String
          ? jsonDecode(response.data)
          : response.data as Map<String, dynamic>;

      final bool isSuccess = _isSuccessResponse(responseData['success']);

      if (isSuccess) {
        final pullData = _safeMap(responseData['pull_data']) ?? {};
        final serverTimestamp =
            _safeString(responseData['timestamp']) ??
            _safeString(responseData['server_time']) ??
            TimestampFormatter.nowUtc();

        final db = await _dbService.database;
        final List<String> mergedNames = [];

        // Pass 1: parents (payment_methods, users)
        await _writePullPass(
          db: db,
          pullData: pullData,
          tables: _parentTables,
          mergedNames: mergedNames,
        );

        // Pass 2: children (invoices, transactions, …)
        await _writePullPass(
          db: db,
          pullData: pullData,
          tables: _childTables,
          mergedNames: mergedNames,
        );

        await _dbService.recalculateAllBalances();
        final localTimestamp = TimestampFormatter.nowUtc();
        await _prefs.setString('last_sync_time', serverTimestamp);
        await _prefs.setString('last_sync_time_local', localTimestamp);

        final int custDown = (pullData['users'] as List?)?.length ?? 0;
        final int invDown  = (pullData['invoices'] as List?)?.length ?? 0;

        await _saveSyncDetails(SyncDetails(
          lastSyncTime: localTimestamp,
          customersUploaded: 0,
          invoicesUploaded: 0,
          customersDownloaded: custDown,
          invoicesDownloaded: invDown,
          mergedCustomers: mergedNames,
        ));

        dev.log('Full restore completed at $serverTimestamp.', name: 'SyncService');
      } else {
        final errorMsg =
            responseData['message'] as String? ?? 'Restore failed on server';
        throw Exception(errorMsg);
      }
    } on DioException catch (e) {
      String message = 'فشل استعادة البيانات بسبب مشكلة في الشبكة';
      if (e.response?.statusCode == 401) {
        message = 'انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول';
      } else if (e.response?.statusCode == 500) {
        final serverMsg = e.response?.data is Map
            ? (e.response!.data['message'] ?? 'خطأ داخلي في السيرفر (500)')
            : 'خطأ داخلي في السيرفر (500)';
        message = serverMsg.toString();
      }
      dev.log('Restore failed (Network): ${e.message}', name: 'SyncService');
      throw Exception(message);
    } catch (e) {
      dev.log('Restore failed (General): $e', name: 'SyncService', error: e);
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
      /// Forces a complete re-sync by clearing the last sync time and performing a full sync.
  Future<void> forceFullReSync() async {
    await _prefs.remove('last_sync_time');
    await performFullSync(isInitialSync: true);
  }
}
    /// Forces a complete re-sync by clearing the last sync time and performing a full sync.
  Future<void> forceFullReSync() async {
    await _prefs.remove('last_sync_time');
    await performFullSync(isInitialSync: true);
  }
}
  /// Forces a complete re-sync by clearing the last sync time and performing a full sync.
  Future<void> forceFullReSync() async {
    await _prefs.remove('last_sync_time');
    await performFullSync(isInitialSync: true);
  }
}
