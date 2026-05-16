import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import '../models/models.dart';
import '../core/config/api_config.dart';
import '../utils/timestamp_formatter.dart';
import 'dart:developer' as dev;
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class SyncDetails {
  final String lastSyncTime;
  final int customersUploaded;
  final int invoicesUploaded;
  final int customersDownloaded;
  final int invoicesDownloaded;
  final List<String> mergedCustomers;

  SyncDetails({
    required this.lastSyncTime,
    required this.customersUploaded,
    required this.invoicesUploaded,
    required this.customersDownloaded,
    required this.invoicesDownloaded,
    required this.mergedCustomers,
  });

  Map<String, dynamic> toJson() => {
    'lastSyncTime': lastSyncTime,
    'customersUploaded': customersUploaded,
    'invoicesUploaded': invoicesUploaded,
    'customersDownloaded': customersDownloaded,
    'invoicesDownloaded': invoicesDownloaded,
    'mergedCustomers': mergedCustomers,
  };

  factory SyncDetails.fromJson(Map<String, dynamic> json) => SyncDetails(
    lastSyncTime: json['lastSyncTime'] ?? 'غير معروف',
    customersUploaded: json['customersUploaded'] ?? 0,
    invoicesUploaded: json['invoicesUploaded'] ?? 0,
    customersDownloaded: json['customersDownloaded'] ?? 0,
    invoicesDownloaded: json['invoicesDownloaded'] ?? 0,
    mergedCustomers: List<String>.from(json['mergedCustomers'] ?? []),
  );
}

class SyncService extends ChangeNotifier {
  final DatabaseService _dbService;
  final SharedPreferences _prefs;
  late final Dio _dio;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  SyncDetails? _lastSyncDetails;
  SyncDetails? get lastSyncDetails => _lastSyncDetails;

  // ── Restore progress ─────────────────────────────────────────────────────
  double _restoreProgress = 0.0;
  double get restoreProgress => _restoreProgress;

  String _restoreStatus = '';
  String get restoreStatus => _restoreStatus;

  void _setRestoreProgress(double progress, String status) {
    _restoreProgress = progress;
    _restoreStatus = status;
    notifyListeners();
  }

  SyncService(this._dbService, this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'ElegantStore/1.0 (Dart/3.5; Android)',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _prefs.getString('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));

    _loadLastSyncDetails();
    checkConnectivity();
  }

  void startAutoSync() {
    // Sync disabled in product branch
  }

  void stopAutoSync() {
    // Sync disabled in product branch
  }

  Future<void> syncBeforeLogout() async {
    // Sync disabled in product branch
  }

  void _loadLastSyncDetails() {
    final data = _prefs.getString('last_sync_details_v2');
    if (data != null) {
      try {
        _lastSyncDetails = SyncDetails.fromJson(jsonDecode(data));
      } catch (e) {
        dev.log('Error loading sync details: $e');
      }
    }
  }

  Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      _isOffline = result.isEmpty || result[0].rawAddress.isEmpty;
    } catch (_) {
      _isOffline = true;
    }
    notifyListeners();
    return !_isOffline;
  }

  Future<void> performFullSync({bool isInitialSync = false}) async {
    // Sync disabled in product branch
  }

  Future<void> performFullRestore() async {
    // Sync disabled in product branch
  }

  Future<void> importFromFile({
    void Function(double progress, String status)? onProgress,
  }) async {
    // Sync disabled in product branch
  }

  Future<String> downloadFullExport({
    void Function(double progress, String status)? onProgress,
  }) async {
    // Sync disabled in product branch
    return '';
  }

  Future<void> forceFullReSync() async {
    // Sync disabled in product branch
  }
}
