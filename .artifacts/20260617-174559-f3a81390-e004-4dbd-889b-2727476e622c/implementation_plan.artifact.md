# Implementation Plan - Silent Store Manager Sync

This plan outlines the changes required to remove plain-text credentials from the `product_customers` table, switch to using hashed credentials from the `users` table for syncing, and implement a silent hourly background sync for store manager data.

## User Review Required

> [!IMPORTANT]
> **Password "Unhashing"**: Cryptographic hashes (like the ones used in the `users` table) are **one-way**. It is technically impossible to "unhash" them to get the original plain-text password.
>
> **To achieve your goal on the server**:
> 1.  **Verification**: The server should compare the received hash with its stored hash.
> 2.  **Recovery**: If the server needs the plain text (e.g., for a "forgot password" feature), we would need to switch to **reversible encryption (AES)**. However, this is significantly less secure.
>
> **Recommendation**: Continue using the hashed password. The server can still store it and use it for authentication without ever knowing the plain-text version.

## Proposed Changes

### Data Models

#### [models.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/models/models.dart)
- Remove `username` and `password` fields from `StoreProfile` class.
- Update `toMap` and `fromMap` accordingly.

### Database Services

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)
- Update `_createTables` to remove `username` and `password` from the `product_customers` table definition.
- Add a migration (v17) in `onUpgrade` to handle existing databases.
- Update `updateStoreProfileMetrics` to remove `username` and `password` parameters.
- Update `updateManagerCredentials` to only update the `users` table (hashed) and not the `product_customers` table.
- Add `getManagerUser()` method to fetch the primary manager's details.

### Sync & Tracking Services

#### [customer_tracking_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/customer_tracking_service.dart)
- Update `syncCustomerData` to:
    - Fetch the `STORE_MANAGER` from the `users` table.
    - Include the manager's `username` and **hashed `password`** in the sync payload.
    - Remove dependency on `StoreProfile` for credentials.
- Update `startPeriodicSync` to trigger every hour if the app is open and online.
- Track `lastSyncTime` locally to ensure it doesn't sync more than once per hour unless data changes.

#### [auth_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/auth_service.dart)
- Update `_saveCredentialsForTracking` to call the updated `DatabaseService` method (removing plain-text credential passing).

---

## Verification Plan

### Automated Tests
- I will verify the database schema changes by running the app and inspecting the logs for migration success.
- I will verify the sync payload by adding debug prints to `CustomerTrackingService` to ensure the correct hashed password and username are being sent.

### Manual Verification
1.  **Login as Manager**: Ensure the login still works and triggers a silent sync.
2.  **Check Sync Payload**: Verify that `username` and hashed `password` are present in the POST request to `app-customer/sync`.
3.  **Silent Sync**: Verify that no UI notifications or loaders appear during the background sync.
4.  **Hourly Trigger**: Manually advance the system clock or reduce the timer interval to verify the hourly sync trigger.
