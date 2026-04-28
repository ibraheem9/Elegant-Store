# Device Sync Service Usage Guide

## Overview

The Device Sync Service provides timestamp-based synchronization between Flutter app and Laravel backend. Each device tracks its own sync state independently.

## Architecture

### Components

1. **DeviceSyncService** - Low-level API communication
2. **SyncManager** - High-level orchestration with auto-retry and background sync

## Setup

### 1. Add Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  device_info_plus: ^10.0.0
  dio: ^5.0.0
```

### 2. Initialize in Main App

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.example.com',
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
  ));
  
  final authService = AuthService(dio: dio);
  final databaseService = DatabaseService();
  
  // Create sync services
  final deviceSyncService = DeviceSyncService(
    dio: dio,
    authService: authService,
    databaseService: databaseService,
  );
  
  final syncManager = SyncManager(
    deviceSyncService: deviceSyncService,
    databaseService: databaseService,
    syncInterval: Duration(minutes: 15),
    maxRetries: 3,
  );
  
  // Set up callbacks
  syncManager.onSyncStart = () {
    print('Sync started');
  };
  
  syncManager.onSyncSuccess = () {
    print('Sync completed successfully');
  };
  
  syncManager.onSyncError = (error) {
    print('Sync error: $error');
  };
  
  syncManager.onRecordsReceived = (count) {
    print('Received $count records');
  };
  
  // Enable automatic sync
  syncManager.enable();
  
  runApp(MyApp(
    syncManager: syncManager,
    deviceSyncService: deviceSyncService,
  ));
}
```

### 3. Use in Provider

```dart
class SyncProvider extends ChangeNotifier {
  final SyncManager _syncManager;
  
  bool _isSyncing = false;
  String? _lastError;
  int _recordsReceived = 0;
  
  SyncProvider({required SyncManager syncManager})
      : _syncManager = syncManager {
    _setupCallbacks();
  }
  
  void _setupCallbacks() {
    _syncManager.onSyncStart = () {
      _isSyncing = true;
      _lastError = null;
      notifyListeners();
    };
    
    _syncManager.onSyncSuccess = () {
      _isSyncing = false;
      notifyListeners();
    };
    
    _syncManager.onSyncError = (error) {
      _isSyncing = false;
      _lastError = error;
      notifyListeners();
    };
    
    _syncManager.onRecordsReceived = (count) {
      _recordsReceived = count;
      notifyListeners();
    };
  }
  
  Future<void> syncNow() => _syncManager.forceSyncNow();
  
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  int get recordsReceived => _recordsReceived;
  
  @override
  void dispose() {
    _syncManager.dispose();
    super.dispose();
  }
}
```

### 4. Use in Widget

```dart
class SyncStatusWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, _) {
        return Column(
          children: [
            if (syncProvider.isSyncing)
              CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: syncProvider.syncNow,
                child: Text('Sync Now'),
              ),
            if (syncProvider.lastError != null)
              Text(
                'Error: ${syncProvider.lastError}',
                style: TextStyle(color: Colors.red),
              ),
            if (syncProvider.recordsReceived > 0)
              Text('Received ${syncProvider.recordsReceived} records'),
          ],
        );
      },
    );
  }
}
```

## API Endpoints

### 1. Initialize Sync
```
POST /api/sync/device/init

Request:
{
  "device_id": "device_uuid",
  "device_name": "Samsung Galaxy S21",
  "device_local_time_ms": 1682000000000
}

Response:
{
  "success": true,
  "server_time_ms": 1682000005000,
  "time_offset_ms": 5000,
  "last_sync_time_ms": 1681999000000,
  "is_completed": true
}
```

### 2. Start Sync
```
POST /api/sync/device/start

Request:
{
  "device_id": "device_uuid"
}

Response:
{
  "success": true,
  "message": "Sync started"
}
```

### 3. Get Changed Records
```
POST /api/sync/device/changed-records

Request:
{
  "device_id": "device_uuid",
  "tables": ["users", "invoices", "transactions"]
}

Response:
{
  "success": true,
  "changed_records": {
    "users": [...],
    "invoices": [...]
  },
  "last_sync_time_ms": 1681999000000,
  "server_time_ms": 1682000005000
}
```

### 4. Complete Sync
```
POST /api/sync/device/complete

Request:
{
  "device_id": "device_uuid"
}

Response:
{
  "success": true,
  "message": "Sync completed",
  "last_sync_time_ms": 1682000005000
}
```

### 5. Fail Sync
```
POST /api/sync/device/fail

Request:
{
  "device_id": "device_uuid"
}

Response:
{
  "success": true,
  "message": "Sync failed, will retry from same point"
}
```

### 6. Get Sync Status
```
GET /api/sync/device/status/{device_id}

Response:
{
  "success": true,
  "device_id": "device_uuid",
  "device_name": "Samsung Galaxy S21",
  "last_sync_time_ms": 1682000005000,
  "is_completed": true,
  "sync_started_at_ms": null,
  "time_offset_ms": 5000
}
```

### 7. Get All Devices
```
GET /api/sync/device/list

Response:
{
  "success": true,
  "devices": [
    {
      "device_id": "device_uuid_1",
      "device_name": "Samsung Galaxy S21",
      "last_sync_time_ms": 1682000005000,
      "is_completed": true,
      "time_offset_ms": 5000
    }
  ]
}
```

## Sync Flow

```
1. User logs in
   ↓
2. SyncManager.enable() is called
   ↓
3. Every 15 minutes (configurable):
   ├─ DeviceSyncService.initSync()
   │  └─ Calculate time offset
   ├─ DeviceSyncService.startSync()
   │  └─ Mark sync as started
   ├─ DeviceSyncService.getChangedRecords()
   │  └─ Get records changed since last sync
   ├─ Save records to local database
   ├─ DeviceSyncService.completeSync()
   │  └─ Mark sync as completed
   └─ Update UI with results

4. If sync fails:
   ├─ DeviceSyncService.failSync()
   │  └─ Mark sync as failed (will retry from same point)
   └─ Retry after delay (configurable)
```

## Time Offset Handling

The time offset is calculated to handle device timezone differences:

```
time_offset_ms = server_time_ms - device_local_time_ms

Example:
- Device local time: 1682000000000 (GMT+3)
- Server time: 1682000005000 (UTC)
- Offset: 5000 ms (device is 5 seconds behind)

When comparing timestamps:
- Device timestamp: 1681999000000
- Adjusted timestamp: 1681999000000 + 5000 = 1681999005000
- Server compares: WHERE updated_at > 1681999005000
```

## Error Handling

The service includes automatic retry logic:

```dart
// Configuration
SyncManager(
  maxRetries: 3,           // Max retry attempts
  retryDelay: Duration(seconds: 5),  // Delay between retries
)

// Retry behavior
Attempt 1: Fails
  ↓ (wait 5 seconds)
Attempt 2: Fails
  ↓ (wait 5 seconds)
Attempt 3: Fails
  ↓
Max retries reached → onSyncError callback
```

## Best Practices

1. **Enable sync after login**: Call `syncManager.enable()` after successful authentication
2. **Disable sync on logout**: Call `syncManager.disable()` when user logs out
3. **Handle errors gracefully**: Show user-friendly error messages
4. **Monitor battery**: Consider disabling sync on low battery
5. **Respect data limits**: Adjust `syncInterval` based on user preferences
6. **Test with multiple devices**: Verify sync works correctly across devices

## Troubleshooting

### Sync not starting
- Check if `syncManager.enable()` was called
- Verify network connectivity
- Check authentication token validity

### Records not syncing
- Verify `last_sync_time` is being updated correctly
- Check if `is_completed` is true
- Ensure tables are in the allowed list

### Time offset issues
- Verify device time is synchronized with network
- Check server timezone configuration
- Review offset calculation in logs

### Multiple sync attempts
- Check if `is_completed` is false
- Verify no other sync is in progress
- Review sync logs for errors
