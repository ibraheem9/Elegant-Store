import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'database_service.dart';
import '../core/config/api_config.dart';
import '../utils/timestamp_formatter.dart';
import 'dart:developer' as dev;

class TelemetryService extends ChangeNotifier {
  final DatabaseService _dbService;
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'ElegantStore/1.0 (Telemetry)',
    },
  ));

  TelemetryService(this._dbService);

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  Future<Map<String, String>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String model = 'Unknown';
    String os = Platform.operatingSystem;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        model = '${androidInfo.brand} ${androidInfo.model}';
        os = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        model = iosInfo.utsname.machine;
        os = 'iOS ${iosInfo.systemVersion}';
      } else if (Platform.isWindows) {
        final winInfo = await deviceInfo.windowsInfo;
        model = winInfo.computerName;
        os = 'Windows ${winInfo.releaseId}';
      }
    } catch (e) {
      dev.log('Error getting device info: $e', name: 'TelemetryService');
    }

    return {'model': model, 'os': os};
  }

  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      // Using LocationSettings as desiredAccuracy and timeLimit are deprecated
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      );

      return await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
    } catch (e) {
      dev.log('Error getting location: $e', name: 'TelemetryService');
      return null;
    }
  }

  Future<void> updateAndUploadProfile({
    String? storeName,
    String? ownerName,
    String? address,
    String? city,
    String? phoneNumber,
    String? whatsappNumber,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final metrics = await _dbService.recalculateStoreMetrics();
    
    StoreProfile? existing = await _dbService.getStoreProfile(deviceId);
    
    final profile = StoreProfile(
      id: existing?.id,
      deviceId: deviceId,
      storeName: storeName ?? existing?.storeName,
      ownerName: ownerName ?? existing?.ownerName,
      address: address ?? existing?.address,
      city: city ?? existing?.city,
      mobile: phoneNumber ?? existing?.mobile,
      whatsapp: whatsappNumber ?? existing?.whatsapp,
      customersCount: (metrics['customers_count'] as num?)?.toInt() ?? existing?.customersCount ?? 0,
      invoiceCount: (metrics['invoice_count'] as num?)?.toInt() ?? existing?.invoiceCount ?? 0,
      totalSales: (metrics['total_sales'] as num?)?.toDouble() ?? existing?.totalSales ?? 0.0,
      totalPurchase: (metrics['total_purchase'] as num?)?.toDouble() ?? existing?.totalPurchase ?? 0.0,
      lastActiveTime: TimestampFormatter.nowUtc(),
      lastSyncTime: existing?.lastSyncTime,
    );

    await _dbService.saveStoreProfile(profile);
    notifyListeners(); // Notify UI that profile has changed
    await uploadProfile(profile);
  }

  Future<bool> uploadProfile(StoreProfile profile) async {
    try {
      final response = await _dio.post('sync/telemetry', data: profile.toMap());
      
      if (response.statusCode == 200) {
        final updatedProfile = profile.copyWith(
          lastSyncTime: TimestampFormatter.nowUtc(),
        );
        await _dbService.saveStoreProfile(updatedProfile);
        return true;
      }
    } catch (e) {
      dev.log('Error uploading telemetry: $e', name: 'TelemetryService');
    }
    return false;
  }

  Future<void> syncInBackground() async {
    final deviceId = await getOrCreateDeviceId();
    final profile = await _dbService.getStoreProfile(deviceId);
    if (profile != null) {
      // Refresh stats before uploading
      final metrics = await _dbService.recalculateStoreMetrics();
      final refreshedProfile = profile.copyWith(
        customersCount: (metrics['customers_count'] as num?)?.toInt(),
        invoiceCount: (metrics['invoice_count'] as num?)?.toInt(),
        totalSales: (metrics['total_sales'] as num?)?.toDouble(),
        totalPurchase: (metrics['total_purchase'] as num?)?.toDouble(),
        lastActiveTime: TimestampFormatter.nowUtc(),
      );
      await uploadProfile(refreshedProfile);
    }
  }
}
