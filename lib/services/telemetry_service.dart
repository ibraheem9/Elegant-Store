import 'dart:async';
import 'dart:convert';
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

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
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
    final deviceInfo = await getDeviceInfo();
    final stats = await _dbService.getTelemetryStats();
    final location = await getCurrentLocation();
    
    AppOwnerProfile? existing = await _dbService.getOwnerProfile();
    
    final profile = AppOwnerProfile(
      id: existing?.id,
      deviceId: deviceId,
      storeName: storeName ?? existing?.storeName ?? '',
      ownerName: ownerName ?? existing?.ownerName ?? '',
      address: address ?? existing?.address ?? '',
      city: city ?? existing?.city ?? '',
      phoneNumber: phoneNumber ?? existing?.phoneNumber ?? '',
      whatsappNumber: whatsappNumber ?? existing?.whatsappNumber ?? '',
      deviceModel: deviceInfo['model']!,
      deviceOs: deviceInfo['os']!,
      latitude: location?.latitude ?? existing?.latitude,
      longitude: location?.longitude ?? existing?.longitude,
      totalCustomers: stats['total_customers']!,
      totalInvoices: stats['total_invoices']!,
      lastActiveAt: TimestampFormatter.nowUtc(),
      isUploaded: 0,
    );

    await _dbService.upsertOwnerProfile(profile);
    notifyListeners(); // Notify UI that profile has changed
    await uploadProfile(profile);
  }

  Future<bool> uploadProfile(AppOwnerProfile profile) async {
    try {
      final response = await _dio.post('sync/telemetry', data: profile.toMap());
      
      if (response.statusCode == 200) {
        final updatedProfile = AppOwnerProfile(
          id: profile.id,
          deviceId: profile.deviceId,
          storeName: profile.storeName,
          ownerName: profile.ownerName,
          address: profile.address,
          city: profile.city,
          phoneNumber: profile.phoneNumber,
          whatsappNumber: profile.whatsappNumber,
          deviceModel: profile.deviceModel,
          deviceOs: profile.deviceOs,
          latitude: profile.latitude,
          longitude: profile.longitude,
          totalCustomers: profile.totalCustomers,
          totalInvoices: profile.totalInvoices,
          lastActiveAt: profile.lastActiveAt,
          isUploaded: 1,
          updatedAt: profile.updatedAt,
        );
        await _dbService.upsertOwnerProfile(updatedProfile);
        return true;
      }
    } catch (e) {
      dev.log('Error uploading telemetry: $e', name: 'TelemetryService');
    }
    return false;
  }

  Future<void> syncInBackground() async {
    final profile = await _dbService.getOwnerProfile();
    if (profile != null) {
      // Refresh stats before uploading
      final stats = await _dbService.getTelemetryStats();
      final refreshedProfile = AppOwnerProfile(
        id: profile.id,
        deviceId: profile.deviceId,
        storeName: profile.storeName,
        ownerName: profile.ownerName,
        address: profile.address,
        city: profile.city,
        phoneNumber: profile.phoneNumber,
        whatsappNumber: profile.whatsappNumber,
        deviceModel: profile.deviceModel,
        deviceOs: profile.deviceOs,
        latitude: profile.latitude,
        longitude: profile.longitude,
        totalCustomers: stats['total_customers']!,
        totalInvoices: stats['total_invoices']!,
        lastActiveAt: TimestampFormatter.nowUtc(),
        isUploaded: 0,
      );
      await uploadProfile(refreshedProfile);
    }
  }
}
