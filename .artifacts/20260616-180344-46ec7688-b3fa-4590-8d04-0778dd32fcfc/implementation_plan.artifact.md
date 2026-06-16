# Implementation Plan - User Account Seeding and UI Alignment

The user wants to swap the default username for the developer and store manager accounts during database seeding. Specifically, the developer account should now use the username `i7`. Additionally, the username and password input fields should be left-aligned (LTR) for better usability. Finally, when importing data from JSON, the store manager's username and password should be imported from the JSON file rather than being protected/skipped.

## User Review Required

> [!NOTE]
> I am changing the default developer username to `i7` and the default store manager username to `admin`. If the store manager account is imported from JSON, it will use the username from the JSON file.

## Proposed Changes

### Database Service

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)

- Update `seedDeveloperAccount` to:
    - Set developer username to `i7`.
    - Set default admin username to `admin`.

```diff
-        [
-          devUuid, 'ibraheem', PasswordUtils.hashPassword('ibraheem77**\$\$'),
-          'Ibraheem Abd Elhadi', 'i7r10k8@gmail.com', 'DEVELOPER', 1, now, now, 1
-        ],
+        [
+          devUuid, 'i7', PasswordUtils.hashPassword('ibraheem77**\$\$'),
+          'Ibraheem Abd Elhadi', 'i7r10k8@gmail.com', 'DEVELOPER', 1, now, now, 1
+        ],
...
-            'username': 'ibraheem',
+            'username': 'i7',
...
-        [
-          adminUuid, 'i7', PasswordUtils.hashPassword('123'),
-          'Ibraheem', 'admin@elegant.store', 'STORE_MANAGER', 1, now, now, 1
-        ],
+        [
+          adminUuid, 'admin', PasswordUtils.hashPassword('123'),
+          'Ibraheem', 'admin@elegant.store', 'STORE_MANAGER', 1, now, now, 1
+        ],
```

---

### Import Service

#### [import_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/import_service.dart)

- Modify `importFromJsonString` to stop skipping `username` and `password` updates for `STORE_MANAGER` roles.

```diff
                 if (table == 'users') {
                   final String? incomingRole = row['role'] as String?;
-                  if (incomingRole == 'DEVELOPER' || incomingRole == 'STORE_MANAGER') {
+                  if (incomingRole == 'DEVELOPER') {
                     row.remove('password');
                     row.remove('username');
                   }
                 }
```

---

### UI Changes

#### [login_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/login_screen.dart)

- Update `_buildTextField` to use `textAlign: TextAlign.left` and `textDirection: TextDirection.ltr`.

#### [developer_user_edit_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/developer_user_edit_screen.dart)

- Update `_buildTextField` and `_buildPasswordField` to use `textAlign: TextAlign.left` and `textDirection: TextDirection.ltr`.

## Verification Plan

### Automated Tests
- I will run the app (simulated through code analysis and manual check of logic) to ensure the seeding logic is correct.
- Since I cannot run the full Flutter app with UI, I will verify the code changes through `analyze_file`.

### Manual Verification
- Verify `DatabaseService.seedDeveloperAccount` sets `i7` for developer.
- Verify `ImportService` doesn't remove username for store managers.
- Verify `LoginScreen` text fields have left alignment.
- Verify `DeveloperUserEditScreen` text fields have left alignment.
