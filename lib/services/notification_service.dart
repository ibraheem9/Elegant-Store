import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'database_service.dart';
import '../models/models.dart';
import '../main.dart';
import '../screens/customers_screen.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> init() async {
    tz.initializeTimeZones();

    // Notifications are not supported on Windows in the current setup
    if (Platform.isWindows) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    try {
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
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }
  }

  static void _navigateToCustomer(int customerId) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Fetch only the single customer needed instead of loading all customers
    final db = DatabaseService();
    final dbInstance = await db.database;
    final rows = await dbInstance.query(
      'users',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    try {
      final customer = User.fromMap(rows.first);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
      );
    } catch (e) {
      debugPrint('Customer not found for notification: $e');
    }
  }

  /// Runs daily checks using targeted SQL queries instead of loading all data into RAM.
  /// - Credit limit check: SQL WHERE balance >= credit_limit * 0.9
  /// - Unpaid invoices check: SQL GROUP BY user_id with COUNT
  static Future<void> scheduleDailyCheck(DatabaseService db) async {
    if (Platform.isWindows) return;

    final prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return;

    final dbInstance = await db.database;

    // ── 1. Credit limit alerts (SQL-only, no Dart loop over all customers) ──
    final creditRows = await dbInstance.rawQuery('''
      SELECT id, name, balance, credit_limit
      FROM users
      WHERE role = 'CUSTOMER'
        AND deleted_at IS NULL
        AND credit_limit > 0
        AND balance > 0
        AND balance >= (credit_limit * 0.9)
    ''');

    for (final row in creditRows) {
      final name    = row['name'] as String? ?? '';
      final balance = (row['balance'] as num?)?.toDouble() ?? 0.0;
      final id      = row['id'] as int?;
      final message = 'الزبون $name وصل لـ 90% من سقف الدين (${balance.toStringAsFixed(2)} ₪)';
      await _showImmediateNotification(
        'تنبيه سقف الدين',
        message,
        payload: 'customer_$id',
      );
    }

    // ── 2. Unpaid invoices alerts (SQL GROUP BY, no Dart loop over all invoices) ──
    final unpaidRows = await dbInstance.rawQuery('''
      SELECT u.id, u.name, COUNT(i.id) AS unpaid_count
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      WHERE i.deleted_at IS NULL
        AND i.payment_status IN ('UNPAID', 'DEFERRED')
        AND u.deleted_at IS NULL
      GROUP BY u.id, u.name
      HAVING unpaid_count > 0
    ''');

    for (final row in unpaidRows) {
      final name   = row['name'] as String? ?? 'مجهول';
      final count  = row['unpaid_count'] as int? ?? 0;
      final id     = row['id'] as int?;
      final message = 'الزبون $name لديه $count فواتير غير مدفوعة.';
      await _showImmediateNotification(
        'فواتير مستحقة',
        message,
        payload: 'customer_$id',
      );
    }
  }

  static Future<void> _showImmediateNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    if (!_isInitialized || Platform.isWindows) return;

    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'debt_channel',
        'Debt Alerts',
        channelDescription: 'Alerts for debts and unpaid invoices',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    try {
      await _notificationsPlugin.show(
        body.hashCode, // Unique ID per customer/message
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }
}
