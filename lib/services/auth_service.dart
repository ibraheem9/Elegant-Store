import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'database_service.dart';

class AuthService extends ChangeNotifier {
  final DatabaseService _dbService;
  User? _currentUser;
  bool _isLoggedIn = false;

  AuthService(this._dbService);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;

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
      await login(username, password, saveSession: false);
    }
  }

  Future<bool> login(String username, String password, {bool saveSession = false}) async {
    try {
      final user = await _dbService.authenticate(username, password);
      if (user != null) {
        _currentUser = user;
        _isLoggedIn = true;
        
        if (saveSession) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_username', username);
          await prefs.setString('saved_password', password);
          // Set expiry to 30 days from now
          final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
          await prefs.setInt('session_expiry', expiry);
        }
        
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
