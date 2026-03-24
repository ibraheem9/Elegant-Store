import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'database_service.dart';

class AuthService extends ChangeNotifier {
  final DatabaseService _dbService;
  User? _currentUser;
  bool _isLoggedIn = false;

  AuthService(this._dbService);

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;

  Future<bool> login(String username, String password) async {
    try {
      final user = await _dbService.authenticate(username, password);
      if (user != null) {
        _currentUser = user;
        _isLoggedIn = true;
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

  void logout() {
    _currentUser = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  bool isAccountant() {
    return _currentUser?.role == 'accountant';
  }

  bool isManager() {
    return _currentUser?.role == 'manager';
  }

  bool isCustomer() {
    return _currentUser?.role == 'customer';
  }
}
