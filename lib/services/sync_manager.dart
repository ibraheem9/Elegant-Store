import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_sync_service.dart';
import 'database_service.dart';
import 'sync_service.dart';

class SyncManager {
  final DeviceSyncService _deviceSyncService;
  final SyncService _syncService;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;
  bool get isSyncing => false;

  VoidCallback? onSyncStart;
  VoidCallback? onSyncSuccess;
  Function(String)? onSyncError;
  Function(int)? onRecordsReceived;

  SyncManager({
    required DeviceSyncService deviceSyncService,
    required DatabaseService databaseService,
    required SyncService syncService,
    Duration syncInterval = const Duration(hours: 1),
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 5),
  })  : _deviceSyncService = deviceSyncService,
        _syncService = syncService;

  void enable() {}
  void disable() {}

  Future<bool> performSync() async => true;
  Future<bool> forceSyncNow() async => true;

  Future<Map<String, dynamic>?> getSyncStatus() async => null;
  Future<List<Map<String, dynamic>>> getDevices() async => [];

  void dispose() {}
}
