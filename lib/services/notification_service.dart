import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'database_service.dart';
import '../models/models.dart';
import '../main.dart';
import '../screens/customers_screen.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const LinuxInitializationSettings initializationSettingsLinux = LinuxInitializationSettings(defaultActionName: 'Open notification');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final String? payload = response.payload;
        if (payload != null && payload.startsWith('customer_')) {
          final int? customerId = int.tryParse(payload.split('_')[1]);
          if (customerId != null) {
            _navigateToCustomer(customerId);
          }
        }
      },
    );
  }

  static void _navigateToCustomer(int customerId) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final db = DatabaseService();
    final customers = await db.getCustomers();
    try {
      final customer = customers.firstWhere((c) => c.id == customerId);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer))
      );
    } catch (e) {
      debugPrint('Customer not found for notification: $e');
    }
  }

  static Future<void> scheduleDailyCheck(DatabaseService db) async {
    final prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return;

    final customers = await db.getCustomers();
    
    for (var c in customers) {
      if (c.creditLimit != null && c.creditLimit! > 0) {
        if (c.balance > 0 && c.balance >= (c.creditLimit! * 0.9)) {
          String message = "الزبون ${c.name} وصل لـ 90% من سقف الدين (${c.balance} ₪)";
          await _showImmediateNotification("تنبيه سقف الدين", message, payload: 'customer_${c.id}');
        }
      }
    }

    final unpaidInvoices = await db.getInvoices();
    final unpaidGrouped = <int, int>{}; // userId -> count
    for (var inv in unpaidInvoices) {
       if (inv.paymentStatus == 'UNPAID' || inv.paymentStatus == 'DEFERRED') {
         unpaidGrouped[inv.userId] = (unpaidGrouped[inv.userId] ?? 0) + 1;
       }
    }

    for (var entry in unpaidGrouped.entries) {
      final customer = customers.firstWhere((cust) => cust.id == entry.key, orElse: () => User(id: -1, username: '', name: 'مجهول', role: 'customer', createdAt: ''));
      if (customer.id != -1) {
        String message = "الزبون ${customer.name} لديه ${entry.value} فواتير غير مدفوعة.";
        await _showImmediateNotification("فواتير مستحقة", message, payload: 'customer_${customer.id}');
      }
    }
  }

  static Future<void> _showImmediateNotification(String title, String body, {String? payload}) async {
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'debt_channel', 
        'Debt Alerts', 
        channelDescription: 'Alerts for debts and unpaid invoices', 
        importance: Importance.max, 
        priority: Priority.high
      ),
    );
    await _notificationsPlugin.show(
      body.hashCode, // Unique ID per customer/message
      title, 
      body, 
      notificationDetails, 
      payload: payload
    );
  }
}
