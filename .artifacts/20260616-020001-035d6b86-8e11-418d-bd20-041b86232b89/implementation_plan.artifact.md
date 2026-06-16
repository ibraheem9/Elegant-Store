# Implementation Plan: Fix Remote Credentials and Add Default Admin Account

This plan addresses two main issues:
1. **Fix Remote Credential Update Targeting**: Ensuring that remote credential updates from the server target the correct manager account instead of the developer account.
2. **Default Admin Account for New Databases**: Creating a default `admin` / `123` account when a new database is initialized and displaying these credentials to the user on the login screen.

## Proposed Changes

### [Database Service](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)

#### 1. Improve Remote Credential Updates
Update `updateManagerCredentials` to accurately identify the manager user by matching the current tracking username and prioritizing the `STORE_MANAGER` role.

#### 2. Seed Default Admin Account
Modify `seedDeveloperAccount` (or create a new seeding method) to ensure a default `admin` / `123` account exists.

```dart
// Inside seedDeveloperAccount
// 3. Handle Default Admin Account (admin)
final defaultAdminRows = await txn.query('users', where: 'username = ?', whereArgs: ['admin']);
if (defaultAdminRows.isEmpty) {
  await txn.rawInsert(
    '''
    INSERT INTO users (
      uuid, username, password, name, email,
      role, version, created_at, updated_at, is_synced
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      'ADMIN_DEFAULT_UUID', 'admin', PasswordUtils.hashPassword('123'),
      'مدير النظام', 'admin@store.com', 'STORE_MANAGER', 1, now, now, 1
    ],
  );
}
```

### [Database Setup Screen](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/database_setup_screen.dart)

When a new database is created, set a flag in `SharedPreferences` to indicate that this is a fresh install.

```dart
Future<void> _createNewDatabase() async {
  // ... existing code ...
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_fresh_install', true);
  // ...
}
```

### [Login Screen](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/login_screen.dart)

Check for the `is_fresh_install` flag and display a "Welcome" banner or dialog with the default credentials (`admin` / `123`).

- In `initState`, check `is_fresh_install`.
- If true, show a persistent message or a dialog.
- Once the user logs in for the first time, clear the flag.

```dart
// Inside LoginScreen
bool _showFreshInstallHint = false;

@override
void initState() {
  super.initState();
  _checkFreshInstall();
  // ...
}

Future<void> _checkFreshInstall() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('is_fresh_install') ?? false) {
    setState(() => _showFreshInstallHint = true);
  }
}
```

## Verification Plan

### Manual Verification
1. **Delete Database**: Manually delete the database file to trigger the setup screen.
2. **Create New DB**: Select "Create New Database (Empty)".
3. **Check Login Screen**: Verify that a notice appears showing `admin` / `123`.
4. **Login**: Use `admin` / `123` to login and ensure it works.
5. **Relogin**: Log out and ensure the notice is gone (or stays until successfully logged in once).
6. **Remote Update**: (Theoretical) Verify `updateManagerCredentials` logic by reviewing the code to ensure it uses the `oldUsername` to target the correct user.
