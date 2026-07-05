import '../utils/timestamp_formatter.dart';
import '../utils/password_utils.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../core/config/api_config.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'customer_tracking_service.dart';
import 'license_service.dart';
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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    headers: {
      'Accept': 'application/json',
      // A proper User-Agent is required — the server's ModSecurity blocks
      // requests with no User-Agent (returns HTTP 406).
      'User-Agent': 'AbdElhadiStore/1.0 (Dart/3.5; Android)',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  
  User? _currentUser;
  bool _isLoggedIn = false;
  String? _token;
  bool _allowMultipleInstances = false;

  AuthService(this._dbService, this._syncService);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;
  bool get allowMultipleInstances => _allowMultipleInstances;

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
    _allowMultipleInstances = prefs.getBool('allow_multiple_instances') ?? false;

    // Initialize background tracking sync immediately on startup
    CustomerTrackingService.instance.startPeriodicSync();
    CustomerTrackingService.instance.onCredentialReset = () {
      if (_isLoggedIn) {
        forceLogout();
      }
    };

    // Ensure the file matches the setting on startup
    if (kIsWeb == false && (Platform.isWindows)) {
      await _updateInstanceFlagFile(_allowMultipleInstances);
    }
    
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
    final cleanUsername = username.trim();
    _lastLoginError = null;

    // 1. Try offline login first (Instant & Local)
    try {
      final userInDb = await _dbService.getUserByUsername(cleanUsername);
      if (userInDb != null) {
        final localUser = await _dbService.authenticate(cleanUsername, password);
        if (localUser != null) {
          if (localUser.role == 'CUSTOMER') {
            return LoginResult.customerNotAllowed;
          }

          dev.log('Local login successful for $cleanUsername', name: 'AuthService');
          _currentUser = localUser;
          _isLoggedIn = true;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_username', cleanUsername);
          await prefs.setString('last_user_uuid', _currentUser!.uuid);
          await prefs.setString('last_logged_username', cleanUsername);
          await _secureStorage.write(key: 'last_logged_password', value: password);

          // Always save session expiry for 30 days unless explicitly logged out.
          final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
          await prefs.setInt('session_expiry', expiry);

          // Background: Save credentials and sync to server for app tracking
          _saveCredentialsForTracking(cleanUsername, password);

          if (isDeveloper()) {
            await _clearBiometricData();
          }

          notifyListeners();
          return LoginResult.success;
        } else {
          // USER FOUND BUT WRONG PASSWORD - Return immediately to prevent "No Internet" message
          _lastLoginError = 'خطأ في اسم المستخدم أو كلمة المرور';
          return LoginResult.wrongCredentials;
        }
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

      dev.log('Attempting online login for user: $cleanUsername', name: 'AuthService');
      final response = await _dio.post('login', data: {
        'username': cleanUsername,
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

        final bool userSwitched  = lastUser != null && lastUser != cleanUsername;
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

        final now = TimestampFormatter.nowWithOffset();

        // Prepare data for local DB
        final Map<String, dynamic> localUserDataMap = {
          'uuid': userData['uuid'],
          'parent_id': userData['parent_id'],
          'store_manager_id': userData['store_manager_id'],
          'username': userData['username'],
          'password': PasswordUtils.hashPassword(password), // Hash for local storage
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
        await prefs.setString('saved_username', cleanUsername);
        await prefs.setString('last_user_uuid', _currentUser!.uuid);
        await prefs.setString('last_logged_username', cleanUsername);
        if (incomingStoreManagerId != null) {
          await prefs.setString('last_store_manager_id', incomingStoreManagerId);
        }
        await _secureStorage.write(key: 'last_logged_password', value: password);

        // Always save session expiry for 30 days unless explicitly logged out.
        final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
        await prefs.setInt('session_expiry', expiry);

        // Background: Save credentials and sync to server for app tracking
        _saveCredentialsForTracking(cleanUsername, password);

        if (isDeveloper()) {
          await _clearBiometricData();
        }

        notifyListeners();
        return LoginResult.success;
      }

      _lastLoginError = 'خطأ في اسم المستخدم أو كلمة المرور';
      return LoginResult.wrongCredentials;
    } on DioException catch (e) {
      dev.log('Online login fallback failed (Network): ${e.message}', name: 'AuthService');

      // If server explicitly rejects credentials
      if (e.response?.statusCode == 401 || e.response?.statusCode == 422) {
        _lastLoginError = 'خطأ في اسم المستخدم أو كلمة المرور';
        return LoginResult.wrongCredentials;
      }

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
    
    // We NO LONGER delete the password from secure storage here.
    // This allows the user to log out but still use biometrics next time.
    // The password is only cleared if they explicitly disable biometrics 
    // or if the account is wiped.
    
    notifyListeners();
  }

  /// Forces a logout without attempting to notify the server (e.g. for remote resets).
  Future<void> forceLogout() async {
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
    final cleanNewUsername = username.trim();
    try {
      final db = await _dbService.database;

      // Check for username uniqueness locally (excluding current user)
      final existing = await db.query('users',
          where: 'username = ? AND id != ?',
          whereArgs: [cleanNewUsername, _currentUser!.id]);
      if (existing.isNotEmpty) {
        _lastLoginError = 'اسم المستخدم موجود بالفعل، يرجى اختيار اسم آخر.';
        return false;
      }

      final now = TimestampFormatter.nowWithOffset();
      await db.update(
        'users',
        {'name': name, 'username': cleanNewUsername, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );

      // Persist to SharedPreferences so the new username is remembered on restart/re-auth
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', cleanNewUsername);
      await prefs.setString('last_logged_username', cleanNewUsername);

      _currentUser = User(
        id: _currentUser!.id,
        uuid: _currentUser!.uuid,
        username: cleanNewUsername,
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
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );

      if (results.isEmpty) return false;

      final storedPassword = results.first['password'] as String;
      if (!PasswordUtils.verifyPassword(current, storedPassword)) {
        // Fallback for migration: check if it's plain text and matches
        if (PasswordUtils.isHashed(storedPassword) || storedPassword != current) {
          _lastLoginError = 'كلمة المرور الحالية غير صحيحة.';
          return false;
        }
      }

      // 2. Update local database and mark as unsynced
      final now = TimestampFormatter.nowWithOffset();
      await db.update(
        'users',
        {'password': PasswordUtils.hashPassword(newPass), 'updated_at': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );

      // 3. Update SecureStorage for biometric and future sessions
      await _secureStorage.write(key: 'last_logged_password', value: newPass);

      // 4. Update tracking profile and sync to server for app tracking
      await _saveCredentialsForTracking(
        _currentUser!.username,
        newPass,
        updateTimestamp: true,
      );

      // 5. Update the _currentUser object with new update_at
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
    final cleanUsername = username.trim();
    try {
      final user = await _dbService.getUserByUsername(cleanUsername);
      if (user == null || user.uuid != uuid) {
        return false;
      }

      final success = await _dbService.resetPasswordWithUuid(uuid, newPassword);
      
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_username', cleanUsername);
        await prefs.setString('last_logged_username', cleanUsername);
        await _secureStorage.write(key: 'last_logged_password', value: newPassword);
        dev.log('Password reset successful for $cleanUsername', name: 'AuthService');
      }
      
      return success;
    } catch (e) {
      dev.log('Error in resetPassword: $e', name: 'AuthService');
      return false;
    }
  }

  Future<LoginResult> authenticateWithBiometrics() async {
    try {
      dev.log('Starting biometric authentication...', name: 'AuthService');
      final bool canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      dev.log('Biometric support: $canAuthenticate', name: 'AuthService');
      if (!canAuthenticate) {
        _lastLoginError = 'جهازك لا يدعم البصمة أو لم يتم إعدادها';
        return LoginResult.unknownError;
      }

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'يرجى تسجيل الدخول باستخدام البصمة أو رمز المرور',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'تسجيل الدخول بالبصمة',
            biometricHint: 'المصادقة الحيوية',
            cancelButton: 'إلغاء',
          ),
          IOSAuthMessages(
            cancelButton: 'إلغاء',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      dev.log('Biometric scan result: $authenticated', name: 'AuthService');

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        
        // Priority: last_logged_username (most accurate), fallback to saved_username
        final String? username = prefs.getString('last_logged_username') ?? prefs.getString('saved_username');
        final String? password = await _secureStorage.read(key: 'last_logged_password');

        dev.log('Retrieved stored credentials: username=${username != null}, password=${password != null}', name: 'AuthService');

        if (username != null && password != null) {
          // Perform a FULL LOGIN pass to ensure all state is consistent.
          final result = await login(username, password);
          dev.log('Login result after biometrics: $result', name: 'AuthService');
          
          if (result == LoginResult.wrongCredentials) {
            // Password changed - must disable until manual login updates it
            _lastLoginError = 'تم تغيير كلمة المرور. يرجى تسجيل الدخول يدوياً مرة واحدة لتحديث البصمة.';
            await setBiometricEnabled(false);
          }
          return result;
        } else {
          _lastLoginError = 'لم يتم العثور على بيانات الدخول المحفوظة. يرجى تسجيل الدخول يدوياً أولاً.';
          dev.log('Biometrics succeeded but stored credentials missing.', name: 'AuthService');
        }
      } else {
        _lastLoginError = 'تم إلغاء أو فشل التحقق من البصمة';
      }
      return LoginResult.unknownError;
    } catch (e) {
      _lastLoginError = 'خطأ في نظام البصمة: $e';
      dev.log('Biometric authentication EXCEPTION: $e', name: 'AuthService', error: e);
      return LoginResult.unknownError;
    }
  }

  /// Verifies identity without logging in. Used for sensitive settings.
  Future<bool> verifyIdentityOnly() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuthenticate) return false;

      return await _localAuth.authenticate(
        localizedReason: 'يرجى تأكيد هويتك للمتابعة',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'تأكيد الهوية',
            biometricHint: 'المصادقة الحيوية',
            cancelButton: 'إلغاء',
          ),
          IOSAuthMessages(
            cancelButton: 'إلغاء',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      dev.log('verifyIdentityOnly error: $e', name: 'AuthService');
      return false;
    }
  }

  bool isAccountant() => _currentUser?.role == 'ACCOUNTANT';
  bool isManager() => ['STORE_MANAGER', 'SUPER_ADMIN', 'DEVELOPER'].contains(_currentUser?.role);
  bool isDeveloper() => _currentUser?.role == 'DEVELOPER';
  bool isCustomer() => _currentUser?.role == 'CUSTOMER';

  Future<void> _clearBiometricData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', false);
    await _secureStorage.delete(key: 'last_logged_password');
    dev.log('Biometric data cleared for developer session', name: 'AuthService');
  }

  /// Checks if the current user (especially accountants) has permission for a specific screen.
  bool hasPermission(int screenIndex) {
    if (isManager() || isDeveloper()) return true;
    if (_currentUser == null) return false;
    
    // Default permissions for accountants if none set
    // 0: Home, 1: Sales, 4: Customers, 8: Unpaid Invoices, 15: Profile, 16: Help
    final defaultAllowed = [0, 1, 4, 8, 15, 16];
    
    if (_currentUser!.permissions == null) {
      return defaultAllowed.contains(screenIndex);
    }

    try {
      final Map<String, dynamic> perms = jsonDecode(_currentUser!.permissions!);
      // If the permission is explicitly set to false, return false.
      // If it's not set, we might want to check against defaults or assume restricted.
      // Let's assume if it's set in JSON, we use that. If not, we use default.
      if (perms.containsKey(screenIndex.toString())) {
        return perms[screenIndex.toString()] == true;
      }
      return defaultAllowed.contains(screenIndex);
    } catch (e) {
      dev.log('Error parsing permissions: $e', name: 'AuthService');
      return defaultAllowed.contains(screenIndex);
    }
  }

  Future<void> setAllowMultipleInstances(bool allow) async {
    _allowMultipleInstances = allow;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allow_multiple_instances', allow);
    
    if (kIsWeb == false && (Platform.isWindows)) {
      await _updateInstanceFlagFile(allow);
    }
    
    notifyListeners();
  }

  Future<void> _updateInstanceFlagFile(bool allow) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final flagFile = File(join(docsDir.path, 'AbdElhadiStoreApp', 'allow_multiple_instances.txt'));
      
      if (allow) {
        if (!await flagFile.parent.exists()) {
          await flagFile.parent.create(recursive: true);
        }
        await flagFile.writeAsString('true');
      } else {
        if (await flagFile.exists()) {
          await flagFile.delete();
        }
      }
    } catch (e) {
      dev.log('Error updating instance flag file: $e', name: 'AuthService');
    }
  }

  /// Updates store metrics in the local tracking table and triggers background sync.
  Future<void> _saveCredentialsForTracking(String username, String password, {bool updateTimestamp = false}) async {
    try {
      final deviceId = await LicenseService.instance.getDeviceId();
      await _dbService.updateStoreProfileMetrics(deviceId);
      // Trigger background sync
      CustomerTrackingService.instance.syncCustomerData();
    } catch (e) {
      dev.log('Error triggering tracking sync: $e', name: 'AuthService');
    }
  }
}
