# Fix Offline Login and Ensure Default Account

The user is still facing issues with offline login, likely because the default `admin` account was only seeded during initial database creation and may have an incorrect role mapping (`MANAGER` instead of `STORE_MANAGER`). This plan ensures the default account is always available and the login logic is more robust.

## User Review Required

> [!IMPORTANT]
> This change will ensure that the default account `admin` with password `123` is always available locally, even if the database was created in a previous version.

## Proposed Changes

### [DatabaseService](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)

1.  **Ensure Seeding on Every Startup**: Update `initDatabase` to call `_seedDeveloperAccount` if no manager/developer account exists, ensuring it's not just limited to `onCreate`.
2.  **Fix Role Discrepancy**: Change the seeded role for `admin` from `MANAGER` to `STORE_MANAGER` to match `AuthService.isManager()`.
3.  **Case-Insensitive Authentication**: Update `authenticate` to use `LOWER(username)` for more flexible login.

```dart
// Conceptual change for DatabaseService
Future<User?> authenticate(String username, String password) async {
  final db = await database;
  final r = await db.query(
    'users',
    where: 'LOWER(username) = ? AND password = ?',
    whereArgs: [username.toLowerCase(), password],
  );
  if (r.isNotEmpty) return User.fromMap(r.first);
  return null;
}
```

### [AuthService](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/auth_service.dart)

1.  **Simplify Offline-First Logic**: Ensure that if local authentication fails, we don't immediately throw a network error unless we are absolutely sure the user intended to login online.
2.  **Better Error Handling**: If local authentication fails, check if the username exists locally. If it does, report "Wrong password" instead of "Network error".

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure code correctness.

### Manual Verification
1.  **Test Default Login**:
    -   Open the app (even if it had a previous DB).
    -   Log in with `admin` / `123`.
    -   **Expected**: Success, even without internet.
2.  **Test Case-Insensitivity**:
    -   Log in with `Admin` / `123`.
    -   **Expected**: Success.
3.  **Test Incorrect Password**:
    -   Log in with `admin` / `wrong`.
    -   **Expected**: "Wrong credentials" error, NOT "Network error".
