import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../models/models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storeNameController = TextEditingController(text: 'Elegant Store');
  final _adminNameController = TextEditingController();
  
  bool _notificationsEnabled = true;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final auth = context.read<AuthService>();
    _adminNameController.text = auth.currentUser?.name ?? '';
    
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      String? timeStr = prefs.getString('notification_time');
      if (timeStr != null) {
        final parts = timeStr.split(':');
        _notificationTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    });
  }

  Future<void> _saveNotificationSettings(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
    await prefs.setString('notification_time', "${_notificationTime.hour}:${_notificationTime.minute}");
    setState(() => _notificationsEnabled = enabled);
    
    if (enabled) {
      NotificationService.scheduleDailyCheck(context.read<DatabaseService>());
    }
  }

  Future<void> _exportData() async {
    try {
      final db = context.read<DatabaseService>();
      final customers = await db.getCustomers();
      final invoices = await db.getInvoices();
      final purchases = await db.getTodayPurchases();

      Map<String, dynamic> exportData = {
        'export_date': DateTime.now().toIso8601String(),
        'customers': customers.map((c) => c.toMap()).toList(),
        'invoices': invoices.map((i) => i.toMap()).toList(),
        'purchases': purchases.map((p) => p.toMap()).toList(),
      };

      String jsonString = jsonEncode(exportData);
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية',
        fileName: 'elegant_store_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(jsonString);
        _showSnackBar('تم تصدير البيانات بنجاح', Colors.green);
      }
    } catch (e) {
      _showSnackBar('فشل تصدير البيانات: $e', Colors.red);
    }
  }

  Future<void> _clearAllTransactions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف الشامل'),
          content: const Text('هل أنت متأكد من حذف كافة الفواتير والمشتريات؟\n\n'
              '- سيتم تصفير أرصدة الزبائن لمطابقة السجل الفارغ.\n'
              '- سيتم حذف سجل العمليات والإحصائيات بالكامل.\n'
              '- سيتم الحفاظ على بيانات الزبائن وطرق الدفع.\n\n'
              'لا يمكن التراجع عن هذه العملية!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('نعم، قم بالتفريغ'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await context.read<DatabaseService>().resetAllTransactions();
        _showSnackBar('تم تفريغ كافة الفواتير والعمليات بنجاح', Colors.green);
      } catch (e) {
        _showSnackBar('حدث خطأ أثناء عملية التفريغ: $e', Colors.red);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final isDark = themeNotifier.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإعدادات والتحكم', 
              style: TextStyle(
                fontSize: 32, 
                fontWeight: FontWeight.w900, 
                color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A)
              )
            ),
            const SizedBox(height: 32),

            _buildSection('الملف الشخصي والمتجر', isDark, [
              _buildTextField('اسم المتجر', _storeNameController, Icons.store, isDark),
              const SizedBox(height: 16),
              _buildTextField('اسم المسؤول', _adminNameController, Icons.person, isDark),
            ]),

            const SizedBox(height: 32),
            _buildSection('نظام التنبيهات الذكي', isDark, [
              SwitchListTile(
                title: const Text('تفعيل تنبيهات الديون والتحصيل', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('سيقوم النظام بإعلامك يومياً بالفواتير المتأخرة والزبائن المتجاوزين للسقف'),
                value: _notificationsEnabled,
                onChanged: _saveNotificationSettings,
                activeColor: const Color(0xFF0B74FF),
              ),
              if (_notificationsEnabled)
                ListTile(
                  title: const Text('وقت التنبيه اليومي'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _notificationTime);
                      if (picked != null) {
                        setState(() => _notificationTime = picked);
                        _saveNotificationSettings(true);
                      }
                    },
                    child: Text(_notificationTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  leading: const Icon(Icons.access_time_filled_rounded, color: Colors.orange),
                ),
            ]),

            const SizedBox(height: 32),
            _buildSection('النظام والبيانات', isDark, [
              SwitchListTile(
                title: Text(
                  'الوضع الداكن (Dark Mode)', 
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)
                ),
                value: isDark,
                onChanged: (val) => themeNotifier.toggleTheme(val),
                secondary: Icon(Icons.dark_mode, color: isDark ? const Color(0xFF00E5FF) : Colors.grey),
              ),
              const Divider(),
              ListTile(
                title: Text(
                  'تصدير نسخة احتياطية (Backup)', 
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)
                ),
                leading: const Icon(Icons.download, color: Color(0xFF0B74FF)),
                onTap: _exportData,
              ),
            ]),

            const SizedBox(height: 32),
            _buildSection('إدارة قاعدة البيانات (منطقة خطر)', isDark, [
              ListTile(
                title: const Text(
                  'تفريغ كافة الفواتير والعمليات', 
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)
                ),
                subtitle: const Text('سيتم حذف الفواتير والمشتريات وتصفير أرصدة الزبائن مع الحفاظ على بياناتهم وطرق الدفع'),
                leading: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                onTap: _clearAllTransactions,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0B74FF))),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, bool isDark) {
    return TextField(
      controller: controller,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.black54),
        prefixIcon: Icon(icon, color: const Color(0xFF0B74FF)),
        filled: true,
        fillColor: isDark ? const Color(0xFF071028) : Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}
