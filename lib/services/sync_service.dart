import 'dart:async';
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

  // ── Auto-sync timer ──────────────────────────────────────────────────────
  Timer? _autoSyncTimer;
  // 3-minute interval ensures that data added by other users on other devices
  // is pulled quickly without hammering the server.
  static const Duration _autoSyncInterval = Duration(minutes: 3);

  /// Tables must be processed in dependency order (parents before children).
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

  /// Starts the background auto-sync timer.
  /// Should be called after a successful login.
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) async {
      final hasInternet = await checkConnectivity();
      if (!hasInternet) {
        dev.log('Auto-sync skipped: no internet.', name: 'SyncService');
        return;
      }
      if (_isSyncing) {
        dev.log('Auto-sync skipped: sync already in progress.', name: 'SyncService');
        return;
      }
      dev.log('Auto-sync triggered (every 10 min).', name: 'SyncService');
      try {
        await performFullSync();
        dev.log('Auto-sync completed successfully.', name: 'SyncService');
      } catch (e) {
        dev.log('Auto-sync failed silently: $e', name: 'SyncService');
        // Silent failure — do not interrupt the user.
      }
    });
    dev.log('Auto-sync timer started (interval: 10 min).', name: 'SyncService');
  }

  /// Stops the background auto-sync timer.
  /// Should be called before logout.
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    dev.log('Auto-sync timer stopped.', name: 'SyncService');
  }

  /// Performs a sync and then stops the timer.
  /// Used by the logout flow to ensure data is pushed before signing out.
  Future<void> syncBeforeLogout() async {
    stopAutoSync();
    final hasInternet = await checkConnectivity();
    if (!hasInternet) {
      dev.log('Logout sync skipped: no internet.', name: 'SyncService');
      return; // Proceed with logout even if offline
    }
    try {
      await performFullSync();
      dev.log('Pre-logout sync completed.', name: 'SyncService');
    } catch (e) {
      dev.log('Pre-logout sync failed (non-blocking): $e', name: 'SyncService');
      // Non-blocking — logout proceeds regardless
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

  /// Safely extract a Map<String, dynamic> from a dynamic value.
  /// Handles the case where PHP sends `[]` (empty array) instead of `{}`
  /// (empty object) for associative arrays that happen to be empty.
  Map<String, dynamic>? _safeMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    // PHP sends empty arrays `[]` for empty associative arrays
    if (value is List && value.isEmpty) return {};
    return null;
  }

  /// Safely extract a String from a dynamic value.
  String? _safeString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN SYNC ENTRY POINT
  // ─────────────────────────────────────────────────────────────────────────

  /// Performs a full bidirectional sync with the server.
  ///
  /// [isInitialSync] = true → sends last_sync_time = null so the server
  /// returns ALL store data (used on first login or after a user switch).
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

      // On initial sync, send null so server returns all data
      final String? lastSyncTime =
          isInitialSync ? null : _prefs.getString('last_sync_time');

      final payload = await _prepareSyncPayload();

      final int custUp = payload['users']?.length ?? 0;
      final int invUp  = payload['invoices']?.length ?? 0;

      final response = await _dio.post('sync/receive', data: {
        'data': payload,
        'last_sync_time': lastSyncTime,
      });

      final responseData = response.data is String
          ? jsonDecode(response.data)
          : response.data;

      final dynamic success = responseData['success'];
      final bool isSuccess =
          success == true || success == 'true' || success == 1;

      if (response.statusCode == 200 && isSuccess) {
        // ── Safe type extraction ──────────────────────────────────────────
        final pullData = _safeMap(responseData['pull_data']);

        // Server may send 'timestamp' or 'server_time' — accept both
        final String? serverTimestamp =
            _safeString(responseData['timestamp']) ??
            _safeString(responseData['server_time']);

        // remapped_uuids: PHP sends [] when empty, {} when populated
        final remappedUuids = _safeMap(responseData['remapped_uuids']);

        if (pullData == null || serverTimestamp == null) {
          dev.log(
            'Invalid response keys: ${responseData.keys.toList()}',
            name: 'SyncService',
          );
          throw Exception('استجابة غير صالحة من السيرفر: بيانات المزامنة ناقصة');
        }

        final int custDown = (pullData['users'] as List?)?.length ?? 0;
        final int invDown  = (pullData['invoices'] as List?)?.length ?? 0;
        final List<String> mergedNames = [];

        final db = await _dbService.database;
        await db.transaction((txn) async {
          // ── Step 1: Apply UUID remappings from server (e.g., merged customers) ──
          if (remappedUuids != null && remappedUuids.isNotEmpty) {
            for (final entry in remappedUuids.entries) {
              final newUuid = entry.value?.toString();
              if (newUuid != null && newUuid.isNotEmpty) {
                await _applyUuidRemap(entry.key, newUuid, txn);
              }
            }
          }

          // ── Step 2: Process pull data in dependency order ─────────────────────
          for (final table in _tableOrder) {
            final items = pullData[table];
            if (items is! List || items.isEmpty) continue;

            for (final rawItem in items) {
              try {
                // Safely convert each item to Map<String, dynamic>
                if (rawItem is! Map) {
                  dev.log(
                    'Skipping non-map item in $table: ${rawItem.runtimeType}',
                    name: 'SyncService',
                  );
                  continue;
                }
                final item = Map<String, dynamic>.from(rawItem);

                // Detect client-side duplicate customer names for UI feedback
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

                // Resolve UUID-based foreign keys to local integer IDs
                final resolved = await _resolveRelationsInTxn(table, item, txn);

                await _dbService.upsertFromSyncInTxn(table, resolved, txn);
              } catch (itemError) {
                dev.log(
                  'Error processing $table item: $itemError',
                  name: 'SyncService',
                  error: itemError,
                );
                rethrow;
              }
            }
          }

          // ── Step 3: Mark pushed items as synced ───────────────────────────────
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
        await _prefs.setString('last_sync_time', serverTimestamp);

        await _saveSyncDetails(SyncDetails(
          lastSyncTime: serverTimestamp,
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
        dev.log('Sync failed on server: $errorMsg', name: 'SyncService');
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
  // UUID REMAPPING
  // ─────────────────────────────────────────────────────────────────────────

  /// When the server merges two customers, it sends a remapping of the old
  /// UUID to the canonical new UUID. We apply this locally so all FK references
  /// point to the surviving record.
  Future<void> _applyUuidRemap(
      String oldUuid, String newUuid, dynamic txn) async {
    dev.log('Remapping UUID: $oldUuid → $newUuid', name: 'SyncService');

    // ── Resolve IDs before any structural changes ─────────────────────────────
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
      // Both records exist locally — the server merged them.
      // Re-point all FK references from the old record to the new one,
      // then delete the old duplicate so no UNIQUE violation occurs.
      final int oldId = oldRows.first['id'] as int;
      final int newId = newRows.first['id'] as int;

      if (oldId != newId) {
        dev.log('Both UUIDs exist locally — re-pointing FKs and removing old record ($oldId → $newId)', name: 'SyncService');

        // Re-point FK references
        await txn.rawUpdate(
            'UPDATE invoices SET user_id = ? WHERE user_id = ?',
            [newId, oldId]);
        await txn.rawUpdate(
            'UPDATE transactions SET buyer_id = ? WHERE buyer_id = ?',
            [newId, oldId]);

        // Remove the old (now orphaned) user row to avoid UNIQUE conflict
        await txn.rawDelete(
            'DELETE FROM users WHERE id = ?', [oldId]);
      }
    } else if (oldExists && !newExists) {
      // Only the old UUID exists locally — safe to rename it to the new UUID.
      // Do this only for the users table; other tables use uuid as a plain field.
      await txn.rawUpdate(
        'UPDATE users SET uuid = ?, is_synced = 1 WHERE uuid = ?',
        [newUuid, oldUuid],
      );

      // Also update uuid on any other table that stores it
      for (final table in _tableOrder) {
        if (table == 'users') continue; // already handled above
        await txn.rawUpdate(
          'UPDATE $table SET uuid = ?, is_synced = 1 WHERE uuid = ?',
          [newUuid, oldUuid],
        );
      }
    }
    // If neither or only newExists — nothing to remap.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUSH PAYLOAD PREPARATION
  // ─────────────────────────────────────────────────────────────────────────
  // PUSH PAYLOAD PREPARATION
  // ─────────────────────────────────────────────────────────────────────────
  /// Collect all unsynced local records and replace integer IDs with UUIDs
  /// so the server can resolve relationships independently.
  ///
  /// Optimized: builds a UUID lookup map per referenced table using a single
  /// IN-query instead of one query per row (eliminates N+1 pattern).
  Future<Map<String, List<Map<String, dynamic>>>> _prepareSyncPayload() async {
    final Map<String, List<Map<String, dynamic>>> payload = {};
    final db = await _dbService.database;

    for (final table in _tableOrder) {
      final unsynced = await _dbService.getUnsynced(table);
      if (unsynced.isEmpty) continue;

      // Build UUID lookup maps with a single IN-query per referenced table
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

      // Collect all FK ids for this table in one pass, then build caches
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

      // Map each row using the pre-built cache (zero DB calls inside the loop)
      payload[table] = unsynced.map((rawItem) {
        final item = Map<String, dynamic>.from(rawItem);
        item.remove('id'); // Never send local auto-increment IDs to server
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
              // For ACCOUNTANT users that have never been synced before (is_synced == 0
              // and no server-side hash yet), we MUST send the plain-text password so
              // the server can hash it via Hash::make(). Without this, the server
              // generates a random password and the employee can never log in.
              // For all other cases (already synced, STORE_MANAGER, CUSTOMER) we
              // strip the password to avoid leaking the locally-stored plain text.
              final role = item['role'] as String? ?? '';
              final isSynced = (item['is_synced'] as int? ?? 1) == 1;
              final hasPass = (item['password'] as String?)?.isNotEmpty == true;
              if (role == 'ACCOUNTANT' && !isSynced && hasPass) {
                // Keep password — server will hash it on upsert
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

  // PULL: FOREIGN KEY RESOLUTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert UUID-based FK fields from the server response into local integer IDs.
  /// If the related record is not yet in the local DB, the FK is set to null
  /// (it will be resolved on the next sync once the parent arrives).
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

      final targetUuid = map[uuidKey];
      final targetTable = entry.value[0];
      final idKey = entry.value[1];

      if (targetUuid != null) {
        final rows = await txn.rawQuery(
          'SELECT id FROM $targetTable WHERE uuid = ? LIMIT 1',
          [targetUuid],
        );
        map[idKey] = rows.isNotEmpty ? rows.first['id'] as int : null;

        if (rows.isEmpty) {
          dev.log(
            'Warning: Cannot resolve $uuidKey ($targetUuid) in $table — parent not yet in local DB.',
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
  // SAFE-HOUSE FULL RESTORE
  // ─────────────────────────────────────────────────────────────────────────

  /// Calls POST /sync/restore to download ALL store data from the server,
  /// including soft-deleted records.
  ///
  /// Use this when:
  ///   • The app is freshly installed / database was lost.
  ///   • The user wants to recover data after a crash.
  ///   • A new device needs to be seeded with the full history.
  ///
  /// Soft-deleted records are written to the local DB with their deleted_at
  /// value intact, so they appear in the Recycle Bin but not in normal views.
  Future<void> performFullRestore() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      dev.log('Starting full restore from server…', name: 'SyncService');

      final response = await _dio.post('/sync/restore');
      final responseData = response.data is String
          ? jsonDecode(response.data)
          : response.data as Map<String, dynamic>;

      if (responseData['success'] == true) {
        final pullData = _safeMap(responseData['pull_data']) ?? {};
        final serverTimestamp =
            _safeString(responseData['timestamp']) ??
            DateTime.now().toIso8601String();

        final db = await _dbService.database;
        await db.transaction((txn) async {
          for (final table in _tableOrder) {
            final items = pullData[table];
            if (items == null || items is! List) continue;

            for (final rawItem in items) {
              if (rawItem is! Map) continue;
              final item = Map<String, dynamic>.from(rawItem as Map);
              try {
                final resolved = await _resolveRelationsInTxn(table, item, txn);
                await _dbService.upsertFromSyncInTxn(table, resolved, txn);
              } catch (e) {
                dev.log(
                  'Restore: error on $table item: $e',
                  name: 'SyncService',
                  error: e,
                );
              }
            }
          }
        });

        await _dbService.recalculateAllBalances();
        // Reset last_sync_time so the next regular sync fetches everything fresh.
        await _prefs.setString('last_sync_time', serverTimestamp);

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
      }
      dev.log('Restore failed (Network): ${e.message}', name: 'SyncService');
      throw Exception(message);
    } catch (e) {
      dev.log('Restore failed (General): $e', name: 'SyncService', error: e);
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
