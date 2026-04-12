import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import '../models/models.dart';
import 'database_service.dart';

class AuthService extends ChangeNotifier {
  final DatabaseService _dbService;
  final LocalAuthentication _localAuth = LocalAuthentication();
  User? _currentUser;
  bool _isLoggedIn = false;

  AuthService(this._dbService);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;

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
      return false;
    }
  }

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString('saved_username');
    final String? password = prefs.getString('saved_password');
    final int? expiry = prefs.getInt('session_expiry');
    
    if (username != null && password != null) {
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        await logout();
        return;
      }
      // If biometric is NOT enabled, we try auto-login if it was "remembered"
      // If it IS enabled, we usually wait for the user to trigger it on LoginScreen
      // But if session hasn't expired, we might as well log them in.
      await login(username, password, saveSession: false);
    }
  }

  Future<bool> login(String username, String password, {bool saveSession = false}) async {
    try {
      final user = await _dbService.authenticate(username, password);
      if (user != null) {
        _currentUser = user;
        _isLoggedIn = true;
        
        final prefs = await SharedPreferences.getInstance();
        if (saveSession) {
          await prefs.setString('saved_username', username);
          await prefs.setString('saved_password', password);
          final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
          await prefs.setInt('session_expiry', expiry);
        }

        // Always update these if we want to support biometric login later for this user
        await prefs.setString('last_logged_username', username);
        await prefs.setString('last_logged_password', password);
        
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Login error: $e');
      }
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      // Windows doesn't support biometricOnly: true. 
      // It uses Windows Hello which can be PIN, Fingerprint, or Face.
      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'يرجى تسجيل الدخول باستخدام البصمة أو رمز المرور',
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: !Platform.isWindows,
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
      if (kDebugMode) {
        print('Biometric auth error: $e');
      }
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    _isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await prefs.remove('session_expiry');
    notifyListeners();
  }

  bool isAccountant() {
    return _currentUser?.role == 'ACCOUNTANT';
  }

  bool isManager() {
    return _currentUser?.role == 'SUPER_ADMIN' || _currentUser?.role == 'DEVELOPER';
  }

  bool isDeveloper() {
    return _currentUser?.role == 'DEVELOPER';
  }

  bool isCustomer() {
    return _currentUser?.role == 'CUSTOMER';
  }
}
