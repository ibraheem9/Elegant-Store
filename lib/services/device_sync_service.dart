import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// DeviceSyncService
///
/// Handles timestamp-based device sync with the server.
/// Each device tracks its own last sync time and time offset.
/// Device ID is generated once and stored locally.
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
  })
      : _dio = dio,
        _authService = authService,
        _databaseService = databaseService;

  /// Get or generate device ID (persisted locally)
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if device ID already exists
      String? savedDeviceId = prefs.getString('device_id');

      if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
        _deviceId = savedDeviceId;
        debugPrint('[DeviceSync] Using existing device ID: $_deviceId');
        return _deviceId!;
      }

      // Generate new device ID
      final deviceInfo = DeviceInfoPlugin();
      String deviceId;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? const Uuid().v4();
      } else {
        deviceId = const Uuid().v4();
      }

      // Save device ID locally
      await prefs.setString('device_id', deviceId);
      _deviceId = deviceId;
      debugPrint('[DeviceSync] Generated and saved new device ID: $_deviceId');
      return deviceId;
    } catch (e) {
      debugPrint('[DeviceSync] Error getting device ID: $e');
      final deviceId = const Uuid().v4();
      _deviceId = deviceId;
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

  /// Convert Windows timezone name to IANA timezone
  /// Examples:
  ///   "West Bank Gaza Daylight Time" -> "Asia/Jerusalem"
  ///   "Eastern Standard Time" -> "America/New_York"
  ///   "UTC" -> "UTC"
  String _convertToIanaTimezone(String windowsTimezone) {
    // Mapping of Windows timezone names to IANA timezone identifiers
    final Map<String, String> timezoneMap = {
      // Middle East
      'West Bank Gaza Daylight Time': 'Asia/Jerusalem',
      'West Bank Gaza Standard Time': 'Asia/Jerusalem',
      'Israel Standard Time': 'Asia/Jerusalem',
      'Arabia Standard Time': 'Asia/Riyadh',
      'Arab Standard Time': 'Asia/Baghdad',
      'E. Europe Standard Time': 'Europe/Minsk',
      'Egypt Standard Time': 'Africa/Cairo',
      
      // US
      'Eastern Standard Time': 'America/New_York',
      'Central Standard Time': 'America/Chicago',
      'Mountain Standard Time': 'America/Denver',
      'Pacific Standard Time': 'America/Los_Angeles',
      'Alaskan Standard Time': 'America/Anchorage',
      'Hawaiian Standard Time': 'Pacific/Honolulu',
      
      // Europe
      'GMT Standard Time': 'Europe/London',
      'Central Europe Standard Time': 'Europe/Berlin',
      'Romance Standard Time': 'Europe/Paris',
      'W. Europe Standard Time': 'Europe/Berlin',
      
      // Asia
      'India Standard Time': 'Asia/Kolkata',
      'China Standard Time': 'Asia/Shanghai',
      'Tokyo Standard Time': 'Asia/Tokyo',
      'Singapore Standard Time': 'Asia/Singapore',
      'Bangkok Standard Time': 'Asia/Bangkok',
      
      // Australia
      'AUS Eastern Standard Time': 'Australia/Sydney',
      'AUS Central Standard Time': 'Australia/Adelaide',
      'W. Australia Standard Time': 'Australia/Perth',
      
      // UTC
      'UTC': 'UTC',
    };
    
    // If exact match found, return it
    if (timezoneMap.containsKey(windowsTimezone)) {
      return timezoneMap[windowsTimezone]!;
    }
    
    // If it's already an IANA timezone, return as-is
    if (windowsTimezone.contains('/')) {
      return windowsTimezone;
    }
    
    // Default fallback
    debugPrint('[DeviceSync] Unknown timezone: $windowsTimezone, using UTC');
    return 'UTC';
  }

  /// Initialize sync: calculate time offset
  Future<bool> initSync() async {
    try {
      _isSyncing = true;
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();
      final localTimeMs = DateTime.now().millisecondsSinceEpoch;
      
      // Get device timezone and convert to IANA format if needed
      final rawTimezone = DateTime.now().timeZoneName;
      final deviceTimezone = _convertToIanaTimezone(rawTimezone);

      debugPrint(
          '[DeviceSync] Initializing sync for device: $deviceId ($deviceName), timezone: $deviceTimezone');

      final response = await _dio.post(
        'sync/device/init',
        data: {
          'device_id': deviceId,
          'device_name': deviceName,
          'device_local_time_ms': localTimeMs,
          'device_timezone': deviceTimezone,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      debugPrint('[DeviceSync] Init sync response: ${response.statusCode}');

      if (response.statusCode == 200 && response.data['success'] == true) {
        final serverTimeMs = response.data['server_time_ms'] as int?;
        final timeOffsetMs = response.data['time_offset_ms'] as int?;
        final deviceTz = response.data['device_timezone'] as String?;
        final userTz = response.data['user_timezone'] as String?;

        if (serverTimeMs != null && timeOffsetMs != null) {
          _timeOffsetMs = timeOffsetMs;
          debugPrint(
              '[DeviceSync] Time offset calculated: $_timeOffsetMs ms (server: $serverTimeMs, local: $localTimeMs)');
          debugPrint(
              '[DeviceSync] Timezone - Device: $deviceTz, User: $userTz');
          return true;
        }
      }

      onSyncError?.call('Failed to initialize sync');
      return false;
    } catch (e) {
      debugPrint('[DeviceSync] Init sync error: $e');
      onSyncError?.call('Init sync failed: $e');
      return false;
    }
  }

  /// Start sync
  Future<bool> startSync() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        'sync/device/start',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('[DeviceSync] Sync started for device: $deviceId');
        onSyncStart?.call();
        return true;
      }

      onSyncError?.call('Failed to start sync');
      return false;
    } catch (e) {
      debugPrint('[DeviceSync] Start sync error: $e');
      onSyncError?.call('Start sync failed: $e');
      return false;
    }
  }

  /// Get changed records since last sync
  Future<Map<String, dynamic>> getChangedRecords(List<String> tables) async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        'sync/device/changed-records',
        data: {
          'device_id': deviceId,
          'tables': tables,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final changedRecords = response.data['changed_records'] as Map?;
        final recordCount = response.data['record_count'] as int? ?? 0;

        debugPrint(
            '[DeviceSync] Got $recordCount changed records from ${tables.length} tables');
        onRecordsReceived?.call(recordCount);

        return changedRecords?.cast<String, dynamic>() ?? {};
      }

      return {};
    } catch (e) {
      debugPrint('[DeviceSync] Get changed records error: $e');
      onSyncError?.call('Failed to get changed records: $e');
      return {};
    }
  }

  /// Complete sync
  Future<bool> completeSync() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        'sync/device/complete',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('[DeviceSync] Sync completed for device: $deviceId');
        _isSyncing = false;
        onSyncComplete?.call();
        return true;
      }

      onSyncError?.call('Failed to complete sync');
      return false;
    } catch (e) {
      debugPrint('[DeviceSync] Complete sync error: $e');
      onSyncError?.call('Complete sync failed: $e');
      return false;
    }
  }

  /// Mark sync as failed
  Future<bool> failSync() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.post(
        'sync/device/fail',
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('[DeviceSync] Sync marked as failed for device: $deviceId');
        _isSyncing = false;
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[DeviceSync] Fail sync error: $e');
      return false;
    }
  }

  /// Get sync status for this device
  Future<Map<String, dynamic>?> getSyncStatus() async {
    try {
      final deviceId = await getDeviceId();

      final response = await _dio.get(
        'sync/device/status/$deviceId',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      debugPrint('[DeviceSync] Get sync status error: $e');
      return null;
    }
  }

  /// Get all devices for current user
  Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final response = await _dio.get('sync/device/list');

      if (response.statusCode == 200 && response.data['success'] == true) {
        final devices = response.data['devices'] as List?;
        return devices?.cast<Map<String, dynamic>>() ?? [];
      }

      return [];
    } catch (e) {
      debugPrint('[DeviceSync] Failed to get devices: $e');
      return [];
    }
  }

  /// Convert system timezone name to IANA timezone
  /// 
  /// Maps common Windows timezone names to IANA timezone identifiers
  /// Falls back to UTC if timezone cannot be determined
  String _getIanaTimezone() {
    final tzName = DateTime.now().timeZoneName;
    
    // Map of common timezone names to IANA identifiers
    final timezoneMap = {
      // Middle East
      'Arabia Standard Time': 'Asia/Riyadh',
      'Arab Standard Time': 'Asia/Baghdad',
      'West Bank Gaza Standard Time': 'Asia/Jerusalem',
      'West Bank Gaza Daylight Time': 'Asia/Jerusalem',
      'Israel Standard Time': 'Asia/Jerusalem',
      'E. Europe Standard Time': 'Europe/Bucharest',
      'Syria Standard Time': 'Asia/Damascus',
      'Turkey Standard Time': 'Europe/Istanbul',
      
      // Europe
      'Central European Standard Time': 'Europe/Berlin',
      'Romance Standard Time': 'Europe/Paris',
      'GMT Standard Time': 'Europe/London',
      'Greenwich Standard Time': 'Atlantic/Reykjavik',
      
      // Asia
      'China Standard Time': 'Asia/Shanghai',
      'Tokyo Standard Time': 'Asia/Tokyo',
      'Singapore Standard Time': 'Asia/Singapore',
      'India Standard Time': 'Asia/Kolkata',
      
      // Americas
      'Eastern Standard Time': 'America/New_York',
      'Central Standard Time': 'America/Chicago',
      'Mountain Standard Time': 'America/Denver',
      'Pacific Standard Time': 'America/Los_Angeles',
      
      // UTC
      'UTC': 'UTC',
      'Coordinated Universal Time': 'UTC',
    };
    
    // Try to find exact match
    if (timezoneMap.containsKey(tzName)) {
      return timezoneMap[tzName]!;
    }
    
    // Try to find partial match
    for (final entry in timezoneMap.entries) {
      if (tzName.contains(entry.key) || entry.key.contains(tzName)) {
        return entry.value;
      }
    }
    
    // Default to UTC if no match found
    return 'UTC';
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
            // Convert record to proper Map<String, Object?> type
            final recordMap = <String, Object?>{};
            if (record is Map) {
              for (final entry in (record as Map).entries) {
                recordMap[entry.key.toString()] = entry.value;
              }
            }

            // Use raw insert or replace to save records
            if (recordMap.isNotEmpty) {
              await db.insert(
                tableName,
                recordMap,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          } catch (e) {
            debugPrint('[DeviceSync] Failed to save record from $tableName: $e');
          }
        }

        debugPrint('[DeviceSync] Saved ${records.length} records from table: $tableName');
      }
    } catch (e) {
      debugPrint('[DeviceSync] Error saving changed records: $e');
    }
  }

  /// Get localized timestamp with device timezone
  DateTime getLocalizedTimestamp(int timestampMs) {
    // Convert milliseconds to DateTime in UTC
    final utcDateTime =
        DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);

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
