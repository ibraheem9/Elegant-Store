# Disable Sync Process

The goal is to comment out all sync-related processes and UI elements from the application, keeping them available for future use.

## User Review Required

- **Scope**: I will be commenting out background sync (Workmanager), sync providers in `main.dart`, and sync-related UI in the dashboard and login screens.
- **Data Preservation**: Database schema changes (like `uuid` and `is_synced` columns) will remain as they don't interfere with offline usage.

## Proposed Changes

### [Core]

#### [main.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/main.dart)

- Comment out `Workmanager` initialization and registration.
- Comment out background `callbackDispatcher`.
- Comment out sync-related providers (`SyncService`, `DeviceSyncService`, `SyncManager`).
- Comment out the `CustomerTrackingService` background sync call.

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)

- Comment out imports of `SyncService` and `SyncManager`.
- Comment out the manual sync UI elements (if any) or any background sync triggers.

#### [login_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/login_screen.dart)

- Ensure initial sync logic remains commented out (it already is partially).
- Comment out any other sync-related checks during login.

---

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no broken references remain after commenting out providers and imports.

### Manual Verification
1.  **Launch App**: Verify the app starts without errors.
2.  **Login**: Verify login works (offline mode).
3.  **Dashboard**: Verify no sync-related errors appear in the logs or UI.
4.  **Workmanager**: Verify no background tasks are being registered (check logs).
