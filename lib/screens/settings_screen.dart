import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/models.dart';
import '../main.dart'; // Import ThemeNotifier

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storeNameController = TextEditingController(text: 'Elegant Store');
  final _adminNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _adminNameController.text = auth.currentUser?.name ?? '';
  }

  // --- دوال التصدير والمسح الحالية ---
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
                  'تصدير البيانات (Backup)', 
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)
                ),
                leading: const Icon(Icons.download, color: Color(0xFF0B74FF)),
                onTap: _exportData,
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
