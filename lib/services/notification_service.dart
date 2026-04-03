import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import '../models/models.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const LinuxInitializationSettings initializationSettingsLinux = LinuxInitializationSettings(defaultActionName: 'Open notification');
    
    // Windows logic is handled via platform specific implementations or plugins that wrap it
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> scheduleDailyCheck(DatabaseService db) async {
    final prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return;

    final String? timeStr = prefs.getString('notification_time'); // Format: "HH:mm"
    if (timeStr == null) return;

    final parts = timeStr.split(':');
    final int hour = int.parse(parts[PartiallyMatch.first]);
    final int minute = int.parse(parts[1]);

    // Perform DB check
    final stats = await db.getGlobalStats();
    final customers = await db.getCustomers();
    
    int debtCriticalCount = 0;
    for (var c in customers) {
      if (c.creditLimit != null && c.creditLimit! > 0) {
        if (c.balance < 0 && c.balance.abs() >= (c.creditLimit! * 0.9)) {
          debtCriticalCount++;
        }
      }
    }

    final unpaidInvoices = await db.getInvoices();
    int unpaidCount = unpaidInvoices.where((i) => i.paymentStatus == 'UNPAID').length;

    if (debtCriticalCount > 0 || unpaidCount > 0) {
      String message = "يوجد $unpaidCount فواتير غير مدفوعة و $debtCriticalCount زبائن قاربوا على سقف الدين.";
      await _showImmediateNotification("تنبيه الديون والتحصيل", message);
    }
  }

  static Future<void> _showImmediateNotification(String title, String body) async {
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails('debt_channel', 'Debt Alerts', channelDescription: 'Alerts for debts and unpaid invoices', importance: Importance.max, priority: Priority.high),
    );
    await _notificationsPlugin.show(0, title, body, notificationDetails);
  }
}

class PartiallyMatch {
  static const int first = 0;
}
