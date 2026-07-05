import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'license_service.dart';
import 'customer_tracking_service.dart';
import 'auth_service.dart';
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
      'User-Agent': 'AbdElhadiStore/1.0 (Telemetry)',
    },
  ));

  TelemetryService(this._dbService);

  bool _isProfileComplete = true; // Default to true to avoid flash of setup screen
  bool get isProfileComplete => _isProfileComplete;

  Future<void> checkProfileCompletion() async {
    final deviceId = await getOrCreateDeviceId();
    _isProfileComplete = await _dbService.isProfileComplete(deviceId);
    notifyListeners();
  }

  Future<String> getOrCreateDeviceId() async {
    // Priority: License fingerprint (most stable across installs)
    final hardwareId = await LicenseService.instance.getDeviceId();
    if (hardwareId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_id', hardwareId);
      return hardwareId;
    }

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
      lastActiveTime: TimestampFormatter.nowWithOffset(),
      lastSyncTime: existing?.lastSyncTime,
    );

    await _dbService.saveStoreProfile(profile);
    _isProfileComplete = await _dbService.isProfileComplete(deviceId);
    notifyListeners(); // Notify UI that profile has changed
    
    // Trigger comprehensive sync
    await uploadProfile(profile);

    // Also trigger CustomerTrackingService to ensure consistent stats & metadata
    // ignore: unawaited_futures
    CustomerTrackingService.instance.syncCustomerData();
  }

  Future<bool> uploadProfile(StoreProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = profile.deviceId;
      
      // 1. Collect Device Info
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown';
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';
      
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceName = androidInfo.host;
          deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
          osVersion = 'Android ${androidInfo.version.release}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceName = iosInfo.name;
          deviceModel = iosInfo.utsname.machine;
          osVersion = 'iOS ${iosInfo.systemVersion}';
        } else if (Platform.isWindows) {
          final winInfo = await deviceInfo.windowsInfo;
          deviceName = winInfo.computerName;
          deviceModel = winInfo.productName;
          osVersion = 'Windows ${winInfo.releaseId}';
        }
      } catch (e) {
        dev.log('Error getting device info for sync: $e', name: 'TelemetryService');
      }

      // 2. Collect App Info
      String appVersion = 'Unknown';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (e) {
        dev.log('Error getting package info: $e', name: 'TelemetryService');
      }

      // 3. Collect Location (Silent)
      double? lat, lng;
      try {
        final position = await getCurrentLocation();
        if (position != null) {
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (_) {}

      // 4. Get Recovery Token
      final recoveryToken = prefs.getString('last_user_uuid') ?? '';

      // 5. Prepare Flat Payload
      final payload = {
        'device_id': deviceId,
        'store_name': profile.storeName ?? '',
        'owner_name': profile.ownerName ?? '',
        'address': profile.address ?? '',
        'city': profile.city ?? '',
        'mobile': profile.mobile ?? '',
        'whatsapp': profile.whatsapp ?? '',
        'device_name': deviceName,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'latitude': lat,
        'longitude': lng,
        'invoice_count': profile.invoiceCount,
        'customers_count': profile.customersCount,
        'total_sales': profile.totalSales,
        'total_purchase': profile.totalPurchase,
        'recovery_token': recoveryToken,
        'last_sync_time': profile.lastSyncTime ?? TimestampFormatter.nowWithOffset(),
        'last_active_time': profile.lastActiveTime ?? TimestampFormatter.nowWithOffset(),
      };

      final response = await _dio.post(ApiConfig.appCustomerSyncEndpoint, data: payload);
      
      if (response.statusCode == 200) {
        final updatedProfile = profile.copyWith(
          lastSyncTime: TimestampFormatter.nowWithOffset(),
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
        lastActiveTime: TimestampFormatter.nowWithOffset(),
      );
      await uploadProfile(refreshedProfile);
    }
  }
}
