import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import 'database_service.dart';
import 'license_service.dart';

class CustomerTrackingService {
  static final CustomerTrackingService instance = CustomerTrackingService._();
  CustomerTrackingService._();

  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  Timer? _periodicTimer;

  /// Starts an hourly timer for background sync and triggers an immediate sync on startup.
  void startPeriodicSync() {
    _periodicTimer?.cancel();
    
    // Trigger immediate sync on startup
    syncCustomerData();

    // Set up hourly timer
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      print('Hourly background tracking sync triggered');
      syncCustomerData();
    });
  }

  /// Collects and syncs customer data to the server in the background.
  Future<void> syncCustomerData({String? recoveryToken}) async {
    try {
      dev.log('Starting silent customer tracking sync...', name: 'CustomerTrackingService');
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await LicenseService.instance.getDeviceId();
      
      // Use provided token or try to get from prefs if saved (for background)
      final actualRecoveryToken = recoveryToken ?? prefs.getString('last_user_uuid') ?? '';
      
      // 1. Collect Device Info
      String deviceName = 'Unknown';
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceName = androidInfo.host;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        deviceModel = iosInfo.utsname.machine;
        osVersion = 'iOS ${iosInfo.systemVersion}';
      } else if (Platform.isWindows) {
        final winInfo = await _deviceInfo.windowsInfo;
        deviceName = winInfo.computerName;
        deviceModel = winInfo.productName;
        osVersion = 'Windows ${winInfo.releaseId}';
      }

      // 2. Collect App Info
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      // 3. Collect Location (Silent)
      double? lat, lng;
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (_) {}

      // 4. Collect Stats
      final db = DatabaseService.instance;
      
      final invoiceCount = await db.getTotalInvoicesCount();
      final customersCount = await db.getTotalCustomersCount();
      final totalSales = await db.getTotalSalesAmount();
      final totalPurchase = await db.getTotalPurchaseAmount();

      // 5. Get User Info from Settings
      final storeName = prefs.getString('settings_store_name') ?? '';
      final ownerName = prefs.getString('settings_owner_name') ?? '';
      final address = prefs.getString('settings_address') ?? '';
      final city = prefs.getString('settings_city') ?? '';
      final mobile = prefs.getString('settings_phone') ?? '';
      final whatsapp = prefs.getString('settings_whatsapp') ?? '';

      // 6. Prepare Payload (Simplified: NO CREDENTIALS SENT)
      final payload = {
        'device_id': deviceId,
        'store_name': storeName,
        'owner_name': ownerName,
        'address': address,
        'city': city,
        'mobile': mobile,
        'whatsapp': whatsapp,
        'device_name': deviceName,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'latitude': lat,
        'longitude': lng,
        'invoice_count': invoiceCount,
        'customers_count': customersCount,
        'total_sales': totalSales,
        'total_purchase': totalPurchase,
        'recovery_token': actualRecoveryToken,
        'last_sync_time': DateTime.now().toIso8601String(),
        'last_active_time': DateTime.now().toIso8601String(),
      };

      // 7. Send to Server (Background)
      final response = await _dio.post(
        ApiConfig.appCustomerSyncEndpoint, 
        data: payload,
        options: Options(
          headers: {'Accept': 'application/json'},
          responseType: ResponseType.json,
        ),
      );
      
      dev.log('Sync response received: ${response.statusCode}', name: 'CustomerTrackingService');

      // 8. Handle Simplified Remote Credential Resets (Server -> App)
      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (e) {
            dev.log('Failed to decode sync response string: $e', name: 'CustomerTrackingService');
          }
        }

        if (data is Map && data.containsKey('remote_credentials')) {
          final remote = data['remote_credentials'];
          if (remote is Map && 
              remote['username'] != null && 
              remote['password'] != null) {
            final String remoteUser = remote['username'].toString();
            final String remotePass = remote['password'].toString();
            
            dev.log('Remote Reset command received for user: $remoteUser', name: 'CustomerTrackingService');
            
            await db.updateManagerCredentials(
              username: remoteUser,
              password: remotePass,
            );

            dev.log('Credentials updated in local DB. Triggering force logout...', name: 'CustomerTrackingService');
            _notifyCredentialReset();
          }
        }
      }
      
      dev.log('Customer tracking sync finished successfully', name: 'CustomerTrackingService');
    } catch (e) {
      dev.log('Error syncing customer tracking data: $e', name: 'CustomerTrackingService');
    }
  }

  // Support for notifying AuthService about resets without direct dependency
  VoidCallback? onCredentialReset;
  void _notifyCredentialReset() {
    onCredentialReset?.call();
  }
}
