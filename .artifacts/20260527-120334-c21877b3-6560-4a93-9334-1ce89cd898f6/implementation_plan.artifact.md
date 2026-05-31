# Improved Sync Process with Last-Write-Wins and Manual Control

This plan addresses the synchronization issues in the Elegant Store application, focusing on reliability after data imports, manual user control, and better progress visualization.

## User Review Required

> [!IMPORTANT]
> - **Initial Sync**: I will remove the automatic sync that occurs immediately after login. Users will need to tap the "Sync" button on the dashboard to fetch their data for the first time or update it.
> - **Chunked Uploads**: Large data sets (e.g., after a JSON import) will be uploaded in chunks of 200 records. This prevents server timeouts and "Request Entity Too Large" errors.
> - **Redundancy Removal**: I will eliminate the duplicate "Pull" operation that currently happens because both `SyncService` and `DeviceSyncService` were being called.

## Proposed Changes

### Core Sync Services

#### [sync_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/sync_service.dart)
- Add `onProgress` callback to `performFullSync`.
- Implement chunked push logic in `_sendPushPayload` to handle large datasets.
- Add `pushOnly` flag to `performFullSync` to skip the redundant pull phase when used by `SyncManager`.

#### [device_sync_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/device_sync_service.dart)
- Refine progress reporting to ensure it integrates smoothly with the overall sync progress in `SyncManager`.

#### [sync_manager.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/sync_manager.dart)
- Orchestrate the overall progress (0% - 100%):
    - **10% - 50%**: Granular progress from `SyncService` (Push).
    - **50% - 95%**: Granular progress from `DeviceSyncService` (Pull).
- Implement a `SyncSummary` result that details precisely how many records were inserted vs. updated across all tables.

---

### Database Layer

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)
- Verify and enforce "Last Write Wins" logic in `upsertFromSyncInTxn` using the `version` column.
- Ensure the result map consistently returns `INSERT`, `UPDATE`, or `SKIP` for all tables.

---

### User Interface

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)
- Update the sync progress bar to show "Actual" progress (0-100% based on chunks and records).
- Add a success dialog/alert that summarizes what was updated, fulfilling the "alert the manager" requirement.
- Ensure the sync button is clearly visible and behaves as the primary trigger.

#### [login_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/login_screen.dart)
- Remove the automatic `performFullSync` call after login.

---

## Verification Plan

### Automated Tests
- I will add a mock-based test in a new file `test/sync_chunking_test.dart` to verify that `SyncService` correctly splits a large payload into chunks.

### Manual Verification
1. **Scenario: Fresh Install + JSON Import**:
    - Delete app data.
    - Reinstall and Login.
    - Import a JSON file with >500 records.
    - Click "Sync" and verify the progress bar moves smoothly and all data is pushed to the server.
2. **Scenario: Manual Sync Trigger**:
    - Verify that no sync starts automatically on login.
    - Verify that the sync button works and shows the new summary alert.
3. **Scenario: Last Write Wins**:
    - Edit a record locally.
    - Edit the same record on the server (if possible) or simulate a newer version in the pull response.
    - Verify that the higher `version` persists.
