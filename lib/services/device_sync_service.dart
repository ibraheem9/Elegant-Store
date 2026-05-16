import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'auth_service.dart';

class DeviceSyncService {
  final Dio _dio;
  final AuthService _authService;
  final DatabaseService _databaseService;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  VoidCallback? onSyncStart;
  VoidCallback? onSyncComplete;
  Function(String)? onSyncError;
  Function(int)? onRecordsReceived;

  DeviceSyncService({
    required Dio dio,
    required AuthService authService,
    required DatabaseService databaseService,
  })  : _dio = dio,
        _authService = authService,
        _databaseService = databaseService;

  Future<String> getDeviceId() async => '';
  Future<String> getDeviceName() async => '';

  Future<bool> initSync() async => false;
  Future<bool> startSync() async => false;
  Future<bool> completeSync() async => false;
  Future<bool> failSync() async => false;

  Future<Map<String, dynamic>?> getSyncStatus() async => null;
  Future<List<Map<String, dynamic>>> getDevices() async => [];

  Future<bool> performFullSync(List<String> tables) async => false;
  Future<bool> performFullSyncDefault() async => false;

  void reset() {}
}
