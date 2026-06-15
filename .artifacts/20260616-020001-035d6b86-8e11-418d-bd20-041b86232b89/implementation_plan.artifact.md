# Fix Remote Credential Update Targeting

The goal is to ensure that when username and password are changed from the server, the correct manager account is updated on the app. Currently, the app updates the first manager account it finds (often the seeded developer account) instead of the account actively being used by the store manager.

## Proposed Changes

### [Database Service](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)

Improve `updateManagerCredentials` to accurately identify the manager user to update by matching the current tracking username and prioritizing the `STORE_MANAGER` role.

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)

- Fetch the `oldUsername` from `product_customers` before updating it.
- Search for a user in the `users` table that matches this `oldUsername`.
- Fallback to finding a user with role `STORE_MANAGER` (excluding the seeded `DEVELOPER` account if possible).
- Update only the identified user's credentials.

```dart
  Future<void> updateManagerCredentials({
    required String deviceId,
    required String username,
    required String password,
    required String updatedAt,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 0. Get the OLD username from the profile BEFORE updating it
      final profiles = await txn.query(
        'product_customers',
        columns: ['username'],
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );

      String? oldUsername;
      if (profiles.isNotEmpty) {
        oldUsername = profiles.first['username'] as String?;
      }

      // 1. Update the tracking profile (plain text for panel)
      await txn.update(
        'product_customers',
        {
          'username': username,
          'password': password,
          'credentials_updated_at': updatedAt,
        },
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );

      // 2. Find and update the manager user in the login table (hashed)
      // First, try to find by oldUsername (most accurate)
      List<Map<String, dynamic>> targetUsers = [];
      if (oldUsername != null && oldUsername.isNotEmpty) {
        targetUsers = await txn.query(
          'users',
          where: "username = ? AND role IN ('STORE_MANAGER', 'SUPER_ADMIN', 'DEVELOPER') AND deleted_at IS NULL",
          whereArgs: [oldUsername],
        );
      }

      // Fallback 1: If not found by username, find the first STORE_MANAGER (the primary manager)
      if (targetUsers.isEmpty) {
        targetUsers = await txn.query(
          'users',
          where: "role = 'STORE_MANAGER' AND deleted_at IS NULL",
          orderBy: 'id ASC', // Most likely the first created/seeded manager
          limit: 1,
        );
      }

      // Fallback 2: If still not found, find ANY other manager/admin
      if (targetUsers.isEmpty) {
        targetUsers = await txn.query(
          'users',
          where: "role IN ('SUPER_ADMIN', 'DEVELOPER') AND deleted_at IS NULL",
          limit: 1,
        );
      }

      if (targetUsers.isNotEmpty) {
        final userId = targetUsers.first['id'] as int;
        final currentVersion = (targetUsers.first['version'] as int?) ?? 1;

        await txn.update(
          'users',
          {
            'username': username,
            'password': PasswordUtils.hashPassword(password),
            'version': currentVersion + 1,
            'is_synced': 1, // Mark as synced since this came from server
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
    });

    dev.log('Manager credentials updated successfully from remote sync', name: 'DatabaseService');
  }
```

## Verification Plan

### Manual Verification
- I will simulate the `CustomerTrackingService` behavior or directly call `updateManagerCredentials` in a test script (if possible) to verify that it updates the correct user when multiple manager/developer accounts exist.
- Since I cannot easily run the full app with a real server, I will rely on logic verification and ensuring that `oldUsername` is correctly retrieved and used.
- I will check that if `ibraheem` (DEVELOPER) and `i7` (STORE_MANAGER) both exist, and `i7` is the one in `product_customers`, only `i7`'s credentials are changed.
