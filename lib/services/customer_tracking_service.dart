import 'dart:io';
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

  /// Collects and syncs customer data to the server in the background.
  Future<void> syncCustomerData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await LicenseService.instance.getDeviceId();
      
      // 1. Collect Device Info
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceModel = iosInfo.utsname.machine;
        osVersion = 'iOS ${iosInfo.systemVersion}';
      } else if (Platform.isWindows) {
        final winInfo = await _deviceInfo.windowsInfo;
        deviceModel = winInfo.computerName;
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
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5),
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (_) {}

      // 4. Collect Usa      // 4. Collect Stats
      final db = DatabaseService.instance;
      final totalInvoices = await db.getTotalInvoicesCount();
      final totalCustomers = await db.getTotalCustomersCount();
      final totalSales = await db.getTotalSalesAmount();     // 5. Get User Info from Settings
      final storeName = prefs.getString('settings_store_name') ?? '';
      final fullName = prefs.getString('settings_owner_name') ?? '';
      final phone = prefs.getString('settings_phone') ?? '';
      final whatsapp = prefs.getString('settings_whatsapp') ?? '';

      // 6. Prepare Payload
      final payload = {
        'device_id': deviceId,
        'store_name': storeName,
        'full_name': fullName,
        'phone': phone,
        'whatsapp': whatsapp,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'latitude': lat,
        'longitude': lng,
        'total_invoices': totalInvoices,
        'total_customers': totalCustomers,
        'total_sales_amount': totalSales,
        'last_active_at': DateTime.now().toIso8601String(),
      };

      // 7. Send to Server (Background)
      await _dio.post(ApiConfig.appCustomerSyncEndpoint, data: payload);
      
      print('Customer tracking data synced successfully');
    } catch (e) {
      print('Error syncing customer tracking data: $e');
    }
  }
}
