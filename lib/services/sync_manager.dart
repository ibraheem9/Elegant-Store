import 'dart:async';
import 'package:flutter/material.dart';
import 'device_sync_service.dart';
import 'database_service.dart';
import 'sync_service.dart';

/// SyncManager
///
/// Orchestrates the sync process with automatic retry, background sync,
/// and conflict resolution.
class SyncManager extends ChangeNotifier {
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
  double _syncProgress = 0.0;
  String _syncStatusText = "";

  // Callbacks
  VoidCallback? onSyncStart;
  VoidCallback? onSyncSuccess;
  Function(String)? onSyncError;
  Function(int)? onRecordsReceived;
  Function(double, String)? onProgressChanged;

  // Tables to sync
  final List<String> _syncTables = [
    'users',
    'payment_methods',
    'invoices',
    'transactions',
    'purchases',
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
      _syncStatusText = "بدء مزامنة البيانات...";
      onSyncStart?.call();
      notifyListeners();
    };

    _deviceSyncService.onSyncComplete = () {
      _retryCount = 0;
      _syncProgress = 1.0;
      _syncStatusText = "اكتملت المزامنة بنجاح";
      onSyncSuccess?.call();
      notifyListeners();
    };

    _deviceSyncService.onSyncError = (error) {
      _syncStatusText = "فشلت المزامنة: $error";
      onSyncError?.call(error);
      notifyListeners();
    };

    _deviceSyncService.onRecordsReceived = (count) {
      onRecordsReceived?.call(count);
    };

    _deviceSyncService.onProgressUpdate = (progress, status) {
      // Map DeviceSyncService (0.0 - 1.0) to the second half of total progress (0.5 - 1.0)
      _updateProgress(0.5 + (progress * 0.5), status);
    };
  }

  double get syncProgress => _syncProgress;
  String get syncStatusText => _syncStatusText;

  void _updateProgress(double progress, String status) {
    _syncProgress = progress;
    _syncStatusText = status;
    onProgressChanged?.call(progress, status);
    notifyListeners();
  }

  /// Enable automatic sync
  void enable() {
    // We'll keep the logic but won't call it by default as requested.
    if (_isEnabled) return;
    _isEnabled = true;
    _startSyncTimer();
    debugPrint('SyncManager: Enabled');
    notifyListeners();
  }

  /// Disable automatic sync
  void disable() {
    _isEnabled = false;
    _syncTimer?.cancel();
    debugPrint('SyncManager: Disabled');
    notifyListeners();
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
      _updateProgress(0.05, "جاري تحضير البيانات...");

      // Step 1: Push local changes to server using SyncService
      debugPrint('SyncManager: [1/2] Pushing local changes via SyncService...');
      
      // Hook into SyncService progress
      void onPushProgress() {
        // Map SyncService progress (0.0 to 1.0) to (0.05 to 0.45) in SyncManager
        final pushProgress = _syncService.syncProgress;
        final pushStatus = _syncService.syncStatusText;
        _updateProgress(0.05 + (pushProgress * 0.4), pushStatus);
      }
      
      _syncService.addListener(onPushProgress);
      
      try {
        await _syncService.performFullSync(isInitialSync: false, pushOnly: true);
        _updateProgress(0.45, "تم رفع البيانات بنجاح.");
      } catch (e) {
        debugPrint('SyncManager: SyncService (push) failed: $e');
        _updateProgress(0.45, "تنبيه: فشل رفع بعض البيانات.");
      } finally {
        _syncService.removeListener(onPushProgress);
      }

      // Step 2: Pull remote changes using DeviceSyncService
      debugPrint('SyncManager: [2/2] Pulling remote changes via DeviceSyncService...');
      
      // DeviceSyncService.performFullSync will handle its internal steps and progress updates (0.5 -> 1.0)
      final stats = await _deviceSyncService.performFullSync(_syncTables);

      if (stats != null) {
        // Step 3: Sync Store Profile and Metrics to its own endpoint
        debugPrint('SyncManager: [3/3] Syncing store profile to separate endpoint...');
        _updateProgress(0.95, "جاري تحديث ملف المتجر والبيانات...");
        await _deviceSyncService.syncStoreProfileOnly();
        
        final updated = stats['updated'] ?? 0;
        final inserted = stats['inserted'] ?? 0;
        String summary = "اكتملت المزامنة بنجاح ✓";
        if (updated > 0 || inserted > 0) {
          summary += " (تم تحديث $updated وإضافة $inserted سجل)";
        }
        
        _updateProgress(1.0, summary);
        debugPrint('SyncManager: Unified sync completed successfully. Stats: $stats');
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
