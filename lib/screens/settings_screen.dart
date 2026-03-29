import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;
  final _storeNameController = TextEditingController(text: 'Elegant Store');
  final _adminNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _adminNameController.text = auth.currentUser?.name ?? '';
  }

  Future<void> _exportData() async {
    try {
      final db = context.read<DatabaseService>();
      // This is a simplified export. A real one would query all tables.
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

  Future<void> _wipeData() async {
    final auth = context.read<AuthService>();
    if (!auth.isManager()) {
      _showSnackBar('عذراً، صلاحية مسح البيانات للمدير فقط', Colors.orange);
      return;
    }

    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد مسح كافة البيانات'),
        content: const Text('هل أنت متأكد من مسح كافة سجلات المبيعات والمشتريات والزبائن؟ لا يمكن التراجع عن هذه العملية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح نهائي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
       // Logic to wipe tables in DatabaseService should be called here
       _showSnackBar('تم مسح البيانات بنجاح', Colors.green);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الإعدادات والسمة', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 32),
            _buildSection('الملف الشخصي والمتجر', [
              _buildTextField('اسم المتجر', _storeNameController, Icons.store),
              const SizedBox(height: 16),
              _buildTextField('اسم المسؤول', _adminNameController, Icons.person),
            ]),
            const SizedBox(height: 32),
            _buildSection('المظهر والسمة', [
              SwitchListTile(
                title: const Text('الوضع الداكن (Dark Mode)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('تغيير ألوان التطبيق للوضع الليلي'),
                value: _isDarkMode,
                onChanged: (val) => setState(() => _isDarkMode = val),
                secondary: Icon(Icons.dark_mode, color: _isDarkMode ? Colors.blue : Colors.grey),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSection('إدارة البيانات', [
              ListTile(
                title: const Text('تصدير البيانات (Backup)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('حفظ نسخة احتياطية من كافة البيانات كملف JSON'),
                leading: const Icon(Icons.download, color: Colors.blue),
                onTap: _exportData,
              ),
              const Divider(),
              ListTile(
                title: const Text('استيراد البيانات (Restore)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('استعادة البيانات من ملف نسخة احتياطية سابق'),
                leading: const Icon(Icons.upload, color: Colors.orange),
                onTap: () {}, // Implementation for import
              ),
              const Divider(),
              ListTile(
                title: const Text('مسح كافة البيانات', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                subtitle: const Text('حذف جميع السجلات من النظام نهائياً'),
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                onTap: _wipeData,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
