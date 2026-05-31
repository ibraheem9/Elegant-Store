# Offline Profile and Password Updates

Enable users to update their username, name, and password without an internet connection. The changes will be saved locally in the SQLite database and synchronized with the server later.

## Proposed Changes

### [Authentication Service]

#### [auth_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/auth_service.dart)

- **Update `updateProfile`**:
    - Add a check for username uniqueness locally to provide better feedback.
    - Update `SharedPreferences` (`saved_username`, `last_logged_username`) so the app remembers the new identity on restart or re-authentication.
    - Ensure `_currentUser` is updated with the new values.
- **Update `changePassword`**:
    - Make it offline-first:
        1. Verify the current password against the local database record.
        2. Update the password in the local database and set `is_synced = 0`.
        3. Update `SharedPreferences` (`last_logged_password`) for biometric and future re-authentication.
        4. (Optional/Background) Attempt to call the existing API endpoint if online to update the server immediately, but return `true` as long as the local update succeeds.

### [Synchronization Service]

#### [sync_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/sync_service.dart)

- **Update `_prepareSyncPayload`**:
    - Modify the logic for the `users` table to include the `password` field for **all roles** (not just `ACCOUNTANT`) if the record is unsynced (`is_synced == 0`) and has a password. This allows managers and admins to sync their password changes made while offline.

### [Settings UI]

#### [settings_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/settings_screen.dart)

- **Update Error Messages**:
    - In `_updateProfile`, change the error message to be more general (e.g., mentioning that the username might be taken) instead of assuming a connection failure.
    - In `_changePassword`, update the error message to focus on the current password being incorrect, as the connection is no longer a hard requirement for the local change.

---

## Verification Plan

### Manual Verification
1. **Code Analysis**: Run `analyze_file` on modified files to ensure no syntax or type errors.
2. **Logic Review**:
    - Verify `updateProfile` now persists the new username to `SharedPreferences`.
    - Verify `changePassword` no longer returns `false` solely due to `_token == null` or network failure.
    - Verify `SyncService` now includes passwords in the sync payload for all roles when unsynced.
