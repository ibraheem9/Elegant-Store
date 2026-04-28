import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// DeviceSyncService
///
/// Handles timestamp-based device sync with the server.
/// Each device tracks its own last sync time and time offset.
///
/// Protocol:
///   1. initSync     – Initialize sync, calculate time offset
///   2. startSync    – Mark sync as started
///   3. getChangedRecords – Get records changed since last sync
///   4. completeSync – Mark sync as completed
///   5. failSync     – Mark sync as failed (retry from same point)
class DeviceSyncService {
  final Dio _dio;
  final AuthService _authService;
  final DatabaseService _databaseService;

  String? _deviceId;
  String? _deviceName;
  int? _timeOffsetMs;
  bool _isSyncing = false;

  // Callbacks
  VoidCallback? onSyncStart;
  VoidCallback? onSyncComplete;
  Function(String)? onSyncError;
  Function(int)? onRecordsReceived;

  DeviceSyncService({
    required Dio dio,
    required AuthService authService,
    required DatabaseService databaseService,
  })  : _dio = dio,
        _authService = authService,
        _databaseService = databaseService;

  /// Get device ID (generated once and stored)
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown';
      } else {
        deviceId = 'web_${DateTime.now().millisecondsSinceEpoch}';
      }

      _deviceId = deviceId;
      return deviceId;
    } catch (e) {
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      return _deviceId!;
    }
  }

  /// Get device name
  Future<String> getDeviceName() async {
    if (_deviceName != null) return _deviceName!;

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceName;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.model;
      } else {
        deviceName = 'Web Browser';
      }

      _deviceName = deviceName;
      return deviceName;
    } catch (e) {
      _deviceName = 'Unknown Device';
      return _deviceName!;
    }
  }

  /// Initialize sync: calculate time offset
  Future<bool> initSync() async {
    try {
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();
      final deviceLocalTimeMs = DateTime.now().millisecondsSinceEpoch;

      final response = await _dio.post(
        '/api/sync/device/init',
        data: {
          'device_id': deviceId,
          'device_name': deviceName,
          'device_local_time_ms': deviceLocalTimeMs,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        _timeOffsetMs = response.data['time_offset_ms'] as int?;
        return true;
      }
      return false;
    } catch (e) {
      onSyncError?.call('Failed to initialize sync: $e');
      return false;
    }
  }

  /// Start sync process
  Future<bool> startSync() async {
    if (_isSyncing) {
      onSyncError?.call('Sync already in progress');
      return false;
    }

    try {
      _isSyncing = true;
      onSyncStart?.call();

      final deviceId = await getDeviceId();

      final response = await _dio.post(
        '/api/sync/device/start',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return true;
      }

      _isSyncing = false;
      onSyncError?.call('Failed to start sync');
      return false;
    } catch (e) {
      _isSyncing = false;
      onSyncError?.call('Failed to start sync: $e');
      return false;
    }
  }

  /// Get changed records since last sync
  Future<Map<String, dynamic>> getChangedRecords(List<String> tables) async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        '/api/sync/device/changed-records',
        data: {
          'device_id': deviceId,
          'tables': tables,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final changedRecords = response.data['changed_records'] as Map<String, dynamic>? ?? {};
        final recordCount = changedRecords.values.fold<int>(0, (sum, table) {
          if (table is List) return sum + table.length;
          return sum;
        });

        onRecordsReceived?.call(recordCount);
        return changedRecords;
      }

      return {};
    } catch (e) {
      onSyncError?.call('Failed to get changed records: $e');
      return {};
    }
  }

  /// Complete sync successfully
  Future<bool> completeSync() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        '/api/sync/device/complete',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        _isSyncing = false;
        onSyncComplete?.call();
        return true;
      }

      _isSyncing = false;
      onSyncError?.call('Failed to complete sync');
      return false;
    } catch (e) {
      _isSyncing = false;
      onSyncError?.call('Failed to complete sync: $e');
      return false;
    }
  }

  /// Mark sync as failed (will retry from same point)
  Future<bool> failSync() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        '/api/sync/device/fail',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        _isSyncing = false;
        return true;
      }

      _isSyncing = false;
      return false;
    } catch (e) {
      _isSyncing = false;
      onSyncError?.call('Failed to mark sync as failed: $e');
      return false;
    }
  }

  /// Get sync status for this device
  Future<Map<String, dynamic>?> getSyncStatus() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.get(
        '/api/sync/device/status/$deviceId',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      onSyncError?.call('Failed to get sync status: $e');
      return null;
    }
  }

  /// Get all devices for current user
  Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final response = await _dio.get('/api/sync/device/list');

      if (response.statusCode == 200 && response.data['success'] == true) {
        final devices = response.data['devices'] as List?;
        return devices?.cast<Map<String, dynamic>>() ?? [];
      }

      return [];
    } catch (e) {
      onSyncError?.call('Failed to get devices: $e');
      return [];
    }
  }

  /// Perform full sync cycle
  Future<bool> performFullSync(List<String> tables) async {
    try {
      // Step 1: Initialize sync
      if (!await initSync()) {
        return false;
      }

      // Step 2: Start sync
      if (!await startSync()) {
        return false;
      }

      // Step 3: Get changed records
      final changedRecords = await getChangedRecords(tables);

      // Step 4: Save records to local database
      if (changedRecords.isNotEmpty) {
        await _saveChangedRecords(changedRecords);
      }

      // Step 5: Complete sync
      if (!await completeSync()) {
        await failSync();
        return false;
      }

      return true;
    } catch (e) {
      await failSync();
      onSyncError?.call('Full sync failed: $e');
      return false;
    }
  }

  /// Save changed records to local database
  Future<void> _saveChangedRecords(Map<String, dynamic> changedRecords) async {
    try {
      final db = await _databaseService.database;
      
      for (final entry in changedRecords.entries) {
        final tableName = entry.key;
        final records = entry.value as List?;

        if (records == null || records.isEmpty) continue;

        // Save each record to local SQLite database
        for (final record in records) {
          try {
            final recordMap = record is Map ? Map<String, dynamic>.from(record as Map) : {};
            
            // Use raw insert or replace to save records
            await db.insert(
              tableName,
              recordMap,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            debugPrint('Failed to save record from $tableName: $e');
          }
        }

        debugPrint('Saved ${records.length} records from table: $tableName');
      }
    } catch (e) {
      debugPrint('Error saving changed records: $e');
    }
  }

  /// Get localized timestamp with device timezone
  DateTime getLocalizedTimestamp(int timestampMs) {
    // Convert milliseconds to DateTime in UTC
    final utcDateTime = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
    
    // Convert to local timezone
    final localDateTime = utcDateTime.toLocal();
    
    return localDateTime;
  }

  /// Get last sync time localized to device timezone
  DateTime? getLocalizedLastSyncTime() {
    if (_timeOffsetMs == null) return null;
    
    // Get current time and apply offset to get last sync time
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSyncMs = now - _timeOffsetMs!;
    
    return getLocalizedTimestamp(lastSyncMs);
  }

  /// Format timestamp for display (localized)
  String formatLocalizedTime(int timestampMs) {
    final localDateTime = getLocalizedTimestamp(timestampMs);
    return localDateTime.toString();
  }

  /// Check if sync is in progress
  bool get isSyncing => _isSyncing;

  /// Get current time offset
  int? get timeOffsetMs => _timeOffsetMs;

  /// Get adjusted timestamp (applying time offset)
  int getAdjustedTimestamp(int timestamp) {
    if (_timeOffsetMs == null) return timestamp;
    return timestamp + _timeOffsetMs!;
  }

  /// Reset sync state
  void reset() {
    _isSyncing = false;
    _timeOffsetMs = null;
  }

  /// Perform full sync with default tables
  Future<bool> performFullSyncDefault() async {
    return performFullSync([
      'users',
      'invoices',
      'transactions',
      'purchases',
      'payment_methods',
      'daily_statistics',
      'edit_history',
    ]);
  }
}
