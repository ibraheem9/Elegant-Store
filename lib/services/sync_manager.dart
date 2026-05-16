import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_sync_service.dart';
import 'database_service.dart';
import 'sync_service.dart';

/// SyncManager
///
/// Orchestrates the sync process with automatic retry, background sync,
/// and conflict resolution.
class SyncManager {
  final DeviceSyncService _deviceSyncService;
  final SyncService _syncService;

  // Configuration
  final Duration _syncInterval;
  final int _maxRetries;
  final Duration _retryDelay;

  // State
  Timer? _syncTimer;
  int _retryCount = 0;
  bool _isEnabled = false;

  // Callbacks
  VoidCallback? onSyncStart;
  VoidCallback? onSyncSuccess;
  Function(String)? onSyncError;
  Function(int)? onRecordsReceived;

  // Tables to sync
  final List<String> _syncTables = [
    'users',
    'invoices',
    'transactions',
    'purchases',
    'payment_methods',
    'daily_statistics',
    'edit_history',
  ];

  SyncManager({
    required DeviceSyncService deviceSyncService,
    required DatabaseService databaseService,
    required SyncService syncService,
    Duration syncInterval = const Duration(hours: 1),
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 5),
  })  : _deviceSyncService = deviceSyncService,
        _syncService = syncService,
        _syncInterval = syncInterval,
        _maxRetries = maxRetries,
        _retryDelay = retryDelay {
    // Set up callbacks
    _deviceSyncService.onSyncStart = () {
      onSyncStart?.call();
    };

    _deviceSyncService.onSyncComplete = () {
      _retryCount = 0;
      onSyncSuccess?.call();
    };

    _deviceSyncService.onSyncError = (error) {
      onSyncError?.call(error);
    };

    _deviceSyncService.onRecordsReceived = (count) {
      onRecordsReceived?.call(count);
    };
  }

  /// Enable automatic sync
  void enable() {
    if (_isEnabled) return;

    _isEnabled = true;
    _startSyncTimer();
    debugPrint('SyncManager: Enabled');
  }

  /// Disable automatic sync
  void disable() {
    _isEnabled = false;
    _syncTimer?.cancel();
    debugPrint('SyncManager: Disabled');
  }

  /// Start sync timer for periodic syncing
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (_isEnabled && !_deviceSyncService.isSyncing) {
        performSync();
      }
    });
  }

  /// Perform sync with automatic retry
  Future<bool> performSync() async {
    try {
      debugPrint('SyncManager: Starting unified sync (attempt ${_retryCount + 1}/$_maxRetries)');

      // Step 1: Push local changes to server using SyncService
      // This is necessary because DeviceSyncService is currently pull-only.
      debugPrint('SyncManager: [1/2] Pushing local changes via SyncService...');
      try {
        await _syncService.performFullSync();
      } catch (e) {
        debugPrint('SyncManager: SyncService (push) failed: $e');
        // We continue to DeviceSyncService even if SyncService fails,
        // as we still want to pull remote changes if possible.
        // However, we'll return failure if the main pull also fails.
      }

      // Step 2: Pull remote changes using DeviceSyncService
      debugPrint('SyncManager: [2/2] Pulling remote changes via DeviceSyncService...');
      final success = await _deviceSyncService.performFullSync(_syncTables);

      if (success) {
        debugPrint('SyncManager: Unified sync completed successfully');
        return true;
      } else {
        return await _handleSyncFailure();
      }
    } catch (e) {
      debugPrint('SyncManager: Sync error: $e');
      return await _handleSyncFailure();
    }
  }

  /// Handle sync failure with retry logic
  Future<bool> _handleSyncFailure() async {
    _retryCount++;

    if (_retryCount < _maxRetries) {
      debugPrint('SyncManager: Retrying sync in ${_retryDelay.inSeconds}s (attempt $_retryCount/$_maxRetries)');
      await Future.delayed(_retryDelay);
      return performSync();
    } else {
      debugPrint('SyncManager: Max retries reached');
      onSyncError?.call('Sync failed after $_maxRetries attempts');
      _retryCount = 0;
      return false;
    }
  }

  /// Force immediate sync (ignoring interval)
  Future<bool> forceSyncNow() async {
    if (_deviceSyncService.isSyncing) {
      debugPrint('SyncManager: Sync already in progress, skipping forceSyncNow');
      return true; // Consider it a success if a sync is already happening
    }

    _retryCount = 0;
    return performSync();
  }

  /// Get sync status
  Future<Map<String, dynamic>?> getSyncStatus() async {
    return _deviceSyncService.getSyncStatus();
  }

  /// Get all devices for current user
  Future<List<Map<String, dynamic>>> getDevices() async {
    return _deviceSyncService.getDevices();
  }

  /// Check if sync is in progress
  bool get isSyncing => _deviceSyncService.isSyncing;

  /// Check if manager is enabled
  bool get isEnabled => _isEnabled;

  /// Get retry count
  int get retryCount => _retryCount;

  /// Dispose resources
  void dispose() {
    disable();
  }
}
