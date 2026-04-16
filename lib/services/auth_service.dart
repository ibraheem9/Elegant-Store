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

class AuthService extends ChangeNotifier {
  final DatabaseService _dbService;
  final SyncService _syncService;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    headers: {'Accept': 'application/json'},
    connectTimeout: const Duration(seconds: 10),
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

  Future<bool> login(String username, String password, {bool saveSession = false}) async {
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
          return false;
        }

        final prefs = await SharedPreferences.getInstance();

        final lastUser = prefs.getString('last_logged_username');
        if (lastUser != null && lastUser != username) {
          dev.log('User switched! Clearing all local data for security.', name: 'AuthService');
          await _dbService.clearAllData();
          await prefs.remove('last_sync_time');
        }

        final now = DateTime.now().toIso8601String();

        // Prepare data for HQ Sync
        final Map<String, dynamic> localUserDataMap = {
          'uuid': userData['uuid'],
          'parent_id': userData['parent_id'],
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

        // Fix: Capture the local auto-incremented ID
        final int localId = await _dbService.upsertFromSync('users', localUserDataMap);
        localUserDataMap['id'] = localId;

        _currentUser = User.fromMap(localUserDataMap);
        _isLoggedIn = true;

        await prefs.setString('auth_token', _token!);
        await prefs.setString('saved_username', username);
        await prefs.setString('last_logged_username', username);
        await prefs.setString('last_logged_password', password);

        if (saveSession) {
          final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
          await prefs.setInt('session_expiry', expiry);
        }

        notifyListeners();

        // Trigger initial background sync only if online
        if (!await _syncService.checkConnectivity()) {
          dev.log('Offline, skipping initial sync after online login.', name: 'AuthService');
        } else {
          _syncService.performFullSync(isInitialSync: true).catchError((e) {
            dev.log('Initial sync error: $e', name: 'AuthService');
          });
        }

        return true;
      }
      dev.log('Server rejected login: ${response.statusCode} - ${response.data}', name: 'AuthService');
      return false;
    } on DioException catch (e) {
      dev.log('Online login failed (Network): ${e.message}', name: 'AuthService');
      // Offline fallback
      final prefs = await SharedPreferences.getInstance();
      final lastUser = prefs.getString('last_logged_username');

      if (lastUser == username) {
        final localUser = await _dbService.authenticate(username, password);
        if (localUser != null) {
          dev.log('Offline fallback successful for $username', name: 'AuthService');
          _currentUser = localUser;
          _isLoggedIn = true;
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      dev.log('Login error (Exception): $e', name: 'AuthService', error: e);
      return false;
    }
  }

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
    if (_token == null) return false;
    try {
      final response = await _dio.put('me',
        data: {'name': name, 'username': username},
        options: Options(headers: {'Authorization': 'Bearer $_token'})
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final Map<String, dynamic> userData = response.data['data'];
        final int localId = await _dbService.upsertFromSync('users', userData);
        userData['id'] = localId;
        _currentUser = User.fromMap(userData);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
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

  Future<bool> authenticateWithBiometrics() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuthenticate) {
        dev.log('Biometrics not available or device not supported.', name: 'AuthService');
        return false;
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
      return false;
    } catch (e) {
      dev.log('Biometric authentication failed: $e', name: 'AuthService');
      return false;
    }
  }

  bool isAccountant() => _currentUser?.role == 'ACCOUNTANT';
  bool isManager() => ['STORE_MANAGER', 'SUPER_ADMIN', 'DEVELOPER'].contains(_currentUser?.role);
  bool isDeveloper() => _currentUser?.role == 'DEVELOPER';
  bool isCustomer() => _currentUser?.role == 'CUSTOMER';
}
