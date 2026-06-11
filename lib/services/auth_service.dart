import '../utils/timestamp_formatter.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../core/config/api_config.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'dart:developer' as dev;

/// Result of a login attempt.
enum LoginResult {
  success,
  wrongCredentials,
  customerNotAllowed,
  networkError,
  unknownError,
}

class AuthService extends ChangeNotifier {
  final DatabaseService _dbService;
  final SyncService? _syncService;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    headers: {
      'Accept': 'application/json',
      // A proper User-Agent is required — the server's ModSecurity blocks
      // requests with no User-Agent (returns HTTP 406).
      'User-Agent': 'ElegantStore/1.0 (Dart/3.5; Android)',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  
  User? _currentUser;
  bool _isLoggedIn = false;
  String? _token;

  AuthService(this._dbService, this._syncService);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;

  Future<bool> get isBiometricEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_enabled') ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
    notifyListeners();
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      dev.log('Error checking biometrics: $e', name: 'AuthService');
      return false;
    }
  }

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    final String? username = prefs.getString('saved_username');
    final int? expiry = prefs.getInt('session_expiry');
    
    // Allow session restoration if username is present, even without a token (offline support)
    if (username != null) {
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        await logout();
        return;
      }
      
      final db = await _dbService.database;
      final r = await db.query('users', where: 'username = ?', whereArgs: [username]);
      if (r.isNotEmpty) {
        _currentUser = User.fromMap(r.first);
        _isLoggedIn = true;
        notifyListeners();
      }
    }
  }

  Future<LoginResult> login(String username, String password, {bool saveSession = false}) async {
    // 1. Try offline login first (Instant & Local)
    try {
      final localUser = await _dbService.authenticate(username, password);
      if (localUser != null) {
        if (localUser.role == 'CUSTOMER') {
          return LoginResult.customerNotAllowed;
        }
        
        dev.log('Local login successful for $username', name: 'AuthService');
        _currentUser = localUser;
        _isLoggedIn = true;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_username', username);
        await prefs.setString('last_user_uuid', _currentUser!.uuid);
        await prefs.setString('last_logged_username', username);
        await prefs.setString('last_logged_password', password);
        
        // Always save session expiry for 30 days unless explicitly logged out.
        // This fulfills the user request for a month-long session.
        final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
        await prefs.setInt('session_expiry', expiry);
        
        notifyListeners();
        return LoginResult.success;
      }
    } catch (e) {
      dev.log('Local login attempt failed with error: $e', name: 'AuthService');
    }

    // 2. Fallback to online login (For new users or first-time device setup)
    try {
      // Check for internet first to avoid long timeouts
      final bool isOnline = await _syncService?.checkConnectivity() ?? false;
      if (!isOnline) {
        _lastLoginError = 'أنت غير متصل بالإنترنت. يرجى التأكد من كتابة بيانات صحيحة أو الاتصال بالشبكة للدخول لأول مرة.';
        return LoginResult.networkError;
      }

      dev.log('Attempting online login for user: $username', name: 'AuthService');
      final response = await _dio.post('login', data: {
        'username': username,
        'password': password,
      });

      // Robust response parsing
      dynamic responseData = response.data;
      if (responseData is String) {
        try {
          responseData = jsonDecode(responseData);
        } catch (e) {
          dev.log('Failed to decode response string: $e', name: 'AuthService');
        }
      }

      final bool isSuccess = responseData != null &&
          (responseData['success'] == true || responseData['success'] == 'true' || responseData['success'] == 1);

      if (response.statusCode == 200 && isSuccess) {
        _token = responseData['token']?.toString();
        final Map<String, dynamic>? userData = responseData['user'] != null
            ? Map<String, dynamic>.from(responseData['user'])
            : null;

        if (userData == null || _token == null) {
          dev.log('Login response missing user data or token', name: 'AuthService');
          return LoginResult.unknownError;
        }

        final prefs = await SharedPreferences.getInstance();

        // Determine the incoming store_manager_id from the server response.
        final incomingStoreManagerId =
            userData['store_manager_id']?.toString() ??
            userData['id']?.toString();

        final lastUser           = prefs.getString('last_logged_username');
        final lastStoreManagerId = prefs.getString('last_store_manager_id');

        final bool userSwitched  = lastUser != null && lastUser != username;
        final bool storeSwitched = lastStoreManagerId != null &&
            incomingStoreManagerId != null &&
            lastStoreManagerId != incomingStoreManagerId;
        final bool freshDevice   = lastUser == null && lastStoreManagerId == null;

        if (userSwitched || storeSwitched) {
          dev.log('Store/User switched. Clearing all local data.', name: 'AuthService');
          await _dbService.clearAllData();
          await prefs.remove('last_sync_time');
        } else if (freshDevice) {
          await prefs.remove('last_sync_time');
        }

        final now = TimestampFormatter.nowUtc();

        // Prepare data for local DB
        final Map<String, dynamic> localUserDataMap = {
          'uuid': userData['uuid'],
          'parent_id': userData['parent_id'],
          'store_manager_id': userData['store_manager_id'],
          'username': userData['username'],
          'password': password, // Store plain text locally for offline re-auth
          'name': userData['name'],
          'role': userData['role'],
          'email': userData['email'],
          'version': userData['version'] ?? 1,
          'created_at': userData['created_at'] ?? now,
          'updated_at': userData['updated_at'] ?? now,
          'is_synced': 1,
        };

        // Capture the local auto-incremented ID
        final Map<String, dynamic> upsertResult = await _dbService.upsertFromSync('users', localUserDataMap);
        final int localId = upsertResult['id'] as int;
        localUserDataMap['id'] = localId;

        _currentUser = User.fromMap(localUserDataMap);
        _isLoggedIn = true;

        await prefs.setString('auth_token', _token!);
        await prefs.setString('saved_username', username);
        await prefs.setString('last_user_uuid', _currentUser!.uuid);
        await prefs.setString('last_logged_username', username);
        if (incomingStoreManagerId != null) {
          await prefs.setString('last_store_manager_id', incomingStoreManagerId);
        }
        await prefs.setString('last_logged_password', password);

        // Always save session expiry for 30 days unless explicitly logged out.
        // This fulfills the user request for a month-long session.
        final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
        await prefs.setInt('session_expiry', expiry);

        notifyListeners();
        return LoginResult.success;
      }

      return LoginResult.wrongCredentials;
    } on DioException catch (e) {
      dev.log('Online login fallback failed (Network): ${e.message}', name: 'AuthService');
      _lastLoginError = 'لا يوجد اتصال بالإنترنت. يرجى المحاولة لاحقاً أو التأكد من إدخال بيانات صحيحة للدخول لأول مرة.';
      return LoginResult.networkError;
    } catch (e) {
      dev.log('Login error (Exception): $e', name: 'AuthService');
      _lastLoginError = e.toString();
      return LoginResult.unknownError;
    }
  }

  /// Holds the last exception message from a failed login attempt.
  String? _lastLoginError;
  String? get lastLoginError => _lastLoginError;

  Future<void> logout() async {
    try {
      if (_token != null) {
        await _dio.post('logout', options: Options(headers: {'Authorization': 'Bearer $_token'}));
      }
    } catch (_) {}

    _currentUser = null;
    _isLoggedIn = false;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('saved_username');
    await prefs.remove('session_expiry');
    notifyListeners();
  }

  Future<bool> updateProfile(String name, String username) async {
    if (_currentUser == null) return false;
    try {
      final db = await _dbService.database;

      // Check for username uniqueness locally (excluding current user)
      final existing = await db.query('users',
          where: 'username = ? AND id != ?',
          whereArgs: [username, _currentUser!.id]);
      if (existing.isNotEmpty) {
        _lastLoginError = 'اسم المستخدم موجود بالفعل، يرجى اختيار اسم آخر.';
        return false;
      }

      final now = TimestampFormatter.nowUtc();
      await db.update(
        'users',
        {'name': name, 'username': username, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );

      // Persist to SharedPreferences so the new username is remembered on restart/re-auth
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('saved_username') == _currentUser!.username) {
        await prefs.setString('saved_username', username);
      }
      if (prefs.getString('last_logged_username') == _currentUser!.username) {
        await prefs.setString('last_logged_username', username);
      }

      _currentUser = User(
        id: _currentUser!.id,
        uuid: _currentUser!.uuid,
        username: username,
        name: name,
        role: _currentUser!.role,
        balance: _currentUser!.balance,
        isPermanentCustomer: _currentUser!.isPermanentCustomer,
        createdAt: _currentUser!.createdAt,
        updatedAt: now,
        parentId: _currentUser!.parentId,
        nickname: _currentUser!.nickname,
        phone: _currentUser!.phone,
        notes: _currentUser!.notes,
        creditLimit: _currentUser!.creditLimit,
        version: _currentUser!.version,
        isSynced: 0,
      );
      notifyListeners();
      return true;
    } catch (e) {
      dev.log('updateProfile error: $e', name: 'AuthService');
      return false;
    }
  }

  Future<bool> changePassword(String current, String newPass) async {
    if (_currentUser == null) return false;
    try {
      // 1. Verify current password against local database
      final db = await _dbService.database;
      final results = await db.query(
        'users',
        where: 'id = ? AND password = ?',
        whereArgs: [_currentUser!.id, current],
      );

      if (results.isEmpty) {
        _lastLoginError = 'كلمة المرور الحالية غير صحيحة.';
        return false;
      }

      // 2. Update local database and mark as unsynced
      final now = TimestampFormatter.nowUtc();
      await db.update(
        'users',
        {'password': newPass, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );

      // 3. Update SharedPreferences for biometric and future sessions
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_logged_password', newPass);

      // 4. Update the _currentUser object with new update_at
      _currentUser = User(
        id: _currentUser!.id,
        uuid: _currentUser!.uuid,
        username: _currentUser!.username,
        name: _currentUser!.name,
        role: _currentUser!.role,
        balance: _currentUser!.balance,
        isPermanentCustomer: _currentUser!.isPermanentCustomer,
        createdAt: _currentUser!.createdAt,
        updatedAt: now,
        parentId: _currentUser!.parentId,
        nickname: _currentUser!.nickname,
        phone: _currentUser!.phone,
        notes: _currentUser!.notes,
        creditLimit: _currentUser!.creditLimit,
        version: _currentUser!.version,
        isSynced: 0,
      );

      // 5. Attempt background server update if online
      if (_token != null && (await _syncService?.checkConnectivity() ?? false)) {
        _dio.put('me/password',
            data: {
              'current_password': current,
              'new_password': newPass,
              'new_password_confirmation': newPass
            },
            options: Options(headers: {'Authorization': 'Bearer $_token'})
        ).then((response) {
          if (response.statusCode == 200 && response.data['success'] == true) {
            // Mark as synced if the background update was successful
            db.update('users', {'is_synced': 1}, where: 'id = ?', whereArgs: [_currentUser!.id]);
          }
        }).catchError((e) {
          dev.log('Background password sync failed: $e', name: 'AuthService');
        });
      }

      notifyListeners();
      return true;
    } catch (e) {
      dev.log('changePassword error: $e', name: 'AuthService');
      return false;
    }
  }

  Future<bool> resetPassword(String username, String uuid, String newPassword) async {
    try {
      final user = await _dbService.getUserByUsername(username);
      if (user == null || user.uuid != uuid) {
        return false;
      }

      final success = await _dbService.resetPasswordWithUuid(uuid, newPassword);
      
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        final lastUser = prefs.getString('last_logged_username');
        if (lastUser != null && lastUser.toLowerCase() == username.toLowerCase()) {
          await prefs.setString('last_logged_password', newPassword);
        }
        dev.log('Password reset successful for $username', name: 'AuthService');
      }
      
      return success;
    } catch (e) {
      dev.log('Error in resetPassword: $e', name: 'AuthService');
      return false;
    }
  }

  Future<LoginResult> authenticateWithBiometrics() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuthenticate) {
        return LoginResult.unknownError;
      }

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'يرجى تسجيل الدخول باستخدام البصمة أو رمز المرور',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        final String? username = prefs.getString('last_logged_username');
        final String? password = prefs.getString('last_logged_password');

        if (username != null && password != null) {
          return await login(username, password);
        }
      }
      return LoginResult.wrongCredentials;
    } catch (e) {
      dev.log('Biometric authentication failed: $e', name: 'AuthService');
      return LoginResult.unknownError;
    }
  }

  bool isAccountant() => _currentUser?.role == 'ACCOUNTANT';
  bool isManager() => ['STORE_MANAGER', 'SUPER_ADMIN', 'DEVELOPER'].contains(_currentUser?.role);
  bool isDeveloper() => _currentUser?.role == 'DEVELOPER';
  bool isCustomer() => _currentUser?.role == 'CUSTOMER';
}
