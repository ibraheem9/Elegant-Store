import '../utils/timestamp_formatter.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_windows/local_auth_windows.dart';
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
  final SyncService _syncService;
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
    
    if (_token != null && username != null) {
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
        // Start background auto-sync every 10 minutes (session resume)
        _syncService.startAutoSync();
        // Fire-and-forget sync — never block startup
        Future.microtask(() async {
          try {
            final isOnline = await _syncService.checkConnectivity()
                .timeout(const Duration(seconds: 3), onTimeout: () => false);
            if (isOnline) {
              _syncService.performFullSync().catchError((e) {
                dev.log('Session init sync failed: $e', name: 'AuthService');
              });
            } else {
              dev.log('Offline, skipping initial sync during session init.', name: 'AuthService');
            }
          } catch (e) {
            dev.log('Connectivity check failed: $e', name: 'AuthService');
          }
        });
      }
    }
  }

  Future<LoginResult> login(String username, String password, {bool saveSession = false}) async {
    try {
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
        // For STORE_MANAGER / SUPER_ADMIN this is their own UUID/id;
        // for ACCOUNTANT it is their parent's id.
        final incomingStoreManagerId =
            userData['store_manager_id']?.toString() ??
            userData['id']?.toString();

        final lastUser           = prefs.getString('last_logged_username');
        final lastStoreManagerId = prefs.getString('last_store_manager_id');

        final bool userSwitched  = lastUser != null && lastUser != username;
        final bool storeSwitched = lastStoreManagerId != null &&
            incomingStoreManagerId != null &&
            lastStoreManagerId != incomingStoreManagerId;
        // Also force a full sync when a brand-new user logs in on this device
        // for the first time (lastUser == null means no prior session).
        final bool freshDevice   = lastUser == null && lastStoreManagerId == null;

        if (userSwitched || storeSwitched) {
          dev.log(
            'Account/store switched ($lastUser → $username | '
            'store $lastStoreManagerId → $incomingStoreManagerId). '
            'Clearing all local data.',
            name: 'AuthService',
          );
          await _dbService.clearAllData();
          await prefs.remove('last_sync_time');
        } else if (freshDevice) {
          // First-ever login on this device — ensure a full sync runs.
          await prefs.remove('last_sync_time');
          dev.log('Fresh device — cleared last_sync_time to force full sync.', name: 'AuthService');
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
        final int localId = await _dbService.upsertFromSync('users', localUserDataMap);
        localUserDataMap['id'] = localId;

        _currentUser = User.fromMap(localUserDataMap);
        _isLoggedIn = true;

        await prefs.setString('auth_token', _token!);
        await prefs.setString('saved_username', username);
        await prefs.setString('last_logged_username', username);
        if (incomingStoreManagerId != null) {
          await prefs.setString('last_store_manager_id', incomingStoreManagerId);
        }
        await prefs.setString('last_logged_password', password);

        if (saveSession) {
          final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
          await prefs.setInt('session_expiry', expiry);
        }

        notifyListeners();
        // Start background auto-sync every 10 minutes
        _syncService.startAutoSync();
        // Initial sync is triggered by LoginScreen on first login so the UI
        // can display a loading message. Subsequent logins use session init sync.
        return LoginResult.success;
      }

      dev.log(
        'Server rejected login: HTTP ${response.statusCode} → ${response.data}',
        name: 'AuthService',
      );
      return LoginResult.wrongCredentials;
    } on DioException catch (e) {
      dev.log('Online login failed (Network): ${e.message}', name: 'AuthService');
      _lastLoginError = 'Network error: ${e.message}';

      // Offline fallback — try to authenticate using local database
      // This allows both returning users and potentially new users if data was synced
      final prefs = await SharedPreferences.getInstance();

      // Try offline login for any user (not just last logged user)
      // This is more flexible and allows new users to login if they were synced locally
      try {
        final localUser = await _dbService.authenticate(username, password);
        if (localUser != null) {
          // Block CUSTOMER from offline login
          if (localUser.role == 'CUSTOMER') {
            return LoginResult.customerNotAllowed;
          }
          dev.log('Offline fallback successful for $username', name: 'AuthService');
          _currentUser = localUser;
          _isLoggedIn = true;
          notifyListeners();
          return LoginResult.success;
        }
      } catch (offlineError) {
        dev.log('Offline fallback also failed: $offlineError', name: 'AuthService');
      }
      
      // If we get here, both online and offline login failed
      return LoginResult.networkError;
    } catch (e, stackTrace) {
      dev.log('Login error (Exception): $e\n$stackTrace', name: 'AuthService', error: e);
      _lastLoginError = e.toString();
      return LoginResult.unknownError;
    }
  }

  /// Holds the last exception message from a failed login attempt.
  /// Used to surface detailed error info to the UI for debugging.
  String? _lastLoginError;
  String? get lastLoginError => _lastLoginError;

  Future<void> logout() async {
    // 1. Sync any unsynced data before signing out (non-blocking if offline)
    await _syncService.syncBeforeLogout();

    // 2. Invalidate server token
    try {
      if (_token != null) {
        await _dio.post('logout', options: Options(headers: {'Authorization': 'Bearer $_token'}));
      }
    } catch (_) {}

    // 3. Clear local session state
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
      // Always update locally first — instant and offline-safe.
      final db = await _dbService.database;
      final now = TimestampFormatter.nowUtc();
      await db.update(
        'users',
        {'name': name, 'username': username, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [_currentUser!.id],
      );
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
      );
      notifyListeners();

      // Attempt remote sync in the background — failure is silent.
      if (_token != null) {
        _dio.put(
          'me',
          data: {'name': name, 'username': username},
          options: Options(headers: {'Authorization': 'Bearer $_token'}),
        ).then((response) {
          if (response.statusCode == 200 && response.data['success'] == true) {
            dev.log('Profile synced to server', name: 'AuthService');
          }
        }).catchError((e) {
          dev.log('Profile remote sync failed (offline): $e', name: 'AuthService');
        });
      }
      return true;
    } catch (e) {
      dev.log('updateProfile error: $e', name: 'AuthService');
      return false;
    }
  }

  Future<bool> changePassword(String current, String newPass) async {
    if (_token == null) return false;
    try {
      final response = await _dio.put('me/password',
        data: {
          'current_password': current,
          'new_password': newPass,
          'new_password_confirmation': newPass
        },
        options: Options(headers: {'Authorization': 'Bearer $_token'})
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (_currentUser != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_logged_password', newPass);
          // Also update local DB
          final db = await _dbService.database;
          await db.update('users', {'password': newPass}, where: 'id = ?', whereArgs: [_currentUser!.id]);
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<LoginResult> authenticateWithBiometrics() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuthenticate) {
        dev.log('Biometrics not available or device not supported.', name: 'AuthService');
        return LoginResult.unknownError;
      }

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'يرجى تسجيل الدخول باستخدام البصمة أو رمز المرور',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Important for Windows to allow Hello PIN
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
