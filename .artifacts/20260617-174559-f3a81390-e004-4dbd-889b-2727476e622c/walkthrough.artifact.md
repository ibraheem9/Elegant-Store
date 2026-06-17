# Walkthrough - Silent Store Manager Sync & Remote Reset

I have implemented the silent hourly background sync and the remote credential reset flow. These changes improve security and ensure that managers can always access the app with the latest credentials set by the admin.

## Changes Made

### 1. Data Security & Schema (v17 Migration)
- **Removed Sensitive Data**: The `username` and `password` columns were removed from the `product_customers` table.
- **Migration**: Added a robust migration (v17) that safely recreates the `product_customers` table without these columns while preserving existing data.
- **Model Update**: Updated [models.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/models/models.dart) to remove credential fields from `StoreProfile`.

### 2. Silent Hourly Sync
- **Background Sync**: The [customer_tracking_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/customer_tracking_service.dart) now triggers a silent sync every 1 hour.
- **Credential-Free Payload**: The sync payload now only contains business metrics and device info. No credentials (even hashed ones) are sent to the server.

### 3. Startup Reset Logic
- **Immediate Startup Sync**: The app now triggers an immediate sync as soon as it opens. This ensures that if you reset the password while the app was closed, the app will update its local database before the manager even tries to log in.
- **Remote Reset Processing**: When the server returns `remote_credentials` in the sync response, the app:
    1.  Hashes the new password locally.
    2.  Updates the `users` table.
    3.  Forces a logout to kick the manager to the login screen with the new credentials.

### 4. Integration
- **AuthService**: Added `forceLogout()` to [auth_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/auth_service.dart) and connected it to the tracking service.
- **Main Entry**: Cleaned up startup logic in [main.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/main.dart) to ensure session and sync are initialized correctly.

## Verification Summary
- **Migration Verified**: Database version updated to 17 and columns dropped.
- **Startup Sync Verified**: Confirmed `syncCustomerData()` is called immediately on app start.
- **Silent Flow Verified**: Periodic timer set to 1 hour, running silently in the background.
- **Remote Reset Verified**: Logic implemented to hash plain-text passwords from the server and update the login database.
