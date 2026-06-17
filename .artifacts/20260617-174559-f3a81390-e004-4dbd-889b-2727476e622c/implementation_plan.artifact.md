# Implementation Plan - Silent Store Manager Sync & Remote Reset

This plan outlines the changes to remove plain-text credentials from the `product_customers` table, implement a silent hourly background sync, and support immediate credential updates on app startup for remote resets.

## User Review Required

> [!NOTE]
> **Startup Sync**: To ensure the manager can log in after a remote reset even if the app was closed, we will trigger the sync **immediately** as soon as the app opens. This happens silently in the background while the user is looking at the login screen.

## Proposed Changes

### Data Models

#### [models.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/models/models.dart)
- Remove `username` and `password` from `StoreProfile` class.
- Update `toMap` and `fromMap`.

### Database Services

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)
- **Migration (v17)**: Remove `username` and `password` columns from `product_customers`.
- **`updateManagerCredentials`**:
    - Update to accept `username` and `password` (plain-text from server).
    - Hash the password locally using `PasswordUtils.hashPassword`.
    - Find the manager in the `users` table and update their record.

### Sync & Tracking Services

#### [customer_tracking_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/customer_tracking_service.dart)
- **`startPeriodicSync`**:
    - Trigger `syncCustomerData()` **immediately** when called.
    - Set up a timer to repeat every 1 hour.
- **`syncCustomerData`**:
    - **Remove** credentials (`username`, `password`) from the outgoing payload.
    - Process `remote_credentials` if present in the response:
        - Call `DatabaseService.updateManagerCredentials`.
        - If the user is currently logged in, trigger `AuthService.forceLogout`.

#### [auth_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/auth_service.dart)
- **`forceLogout`**: New method to clear the session and notify the UI to navigate to the login screen.
- **`initSession`**: Ensure `CustomerTrackingService.instance.startPeriodicSync()` is called here to catch startup resets.

### App Entry Point

#### [main.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/main.dart)
- (Verify) Ensure `AuthService.initSession` is called during startup.

---

## Verification Plan

### Automated Tests
- Verify database migration.
- Verify sync payload contains no credentials.

### Manual Verification
1.  **Startup Reset Test**:
    - Close the app.
    - Change credentials in Admin Panel.
    - Open the app.
    - Wait a few seconds for the background sync to finish.
    - Log in with the **new** credentials.
2.  **Force Logout Test**:
    - Log in as manager.
    - Trigger a reset from the server during the hourly sync.
    - Verify the app logs the user out and shows the login screen.
