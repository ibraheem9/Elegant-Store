import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class AccountantPermissionsScreen extends StatefulWidget {
  final User accountant;
  const AccountantPermissionsScreen({Key? key, required this.accountant}) : super(key: key);

  @override
  State<AccountantPermissionsScreen> createState() => _AccountantPermissionsScreenState();
}

class _AccountantPermissionsScreenState extends State<AccountantPermissionsScreen> {
  late Map<int, bool> _permissions;
  bool _isLoading = false;

  final Map<int, String> _screenTitles = {
    0: 'لوحة التحكم',
    1: 'شاشة البيع',
    2: 'إحصائيات اليوم',
    3: 'المشتريات',
    4: 'إدارة الزبائن',
    6: 'مراجعة المدفوعات',
    7: 'أرصدة الزبائن',
    8: 'الفواتير غير المدفوعة',
    9: 'طرق دفع المبيعات',
    10: 'طرق دفع المشتريات',
    11: 'سلة المحذوفات',
    12: 'الإعدادات والسمة',
    13: 'تواصل معنا',
    14: 'عن المطور',
    15: 'الملف الشخصي للمتجر',
    16: 'دليل الاستخدام',
  };

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  void _initPermissions() {
    _permissions = {};
    // Default allowed for accountants
    final defaultAllowed = [0, 1, 4, 8, 15, 16];
    
    for (var key in _screenTitles.keys) {
      _permissions[key] = defaultAllowed.contains(key);
    }

    if (widget.accountant.permissions != null) {
      try {
        final Map<String, dynamic> saved = jsonDecode(widget.accountant.permissions!);
        saved.forEach((key, value) {
          final intKey = int.tryParse(key);
          if (intKey != null && _screenTitles.containsKey(intKey)) {
            _permissions[intKey] = value == true;
          }
        });
      } catch (e) {
        debugPrint('Error parsing saved permissions: $e');
      }
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final auth = context.read<AuthService>();

      final Map<String, bool> permsToSave = {};
      _permissions.forEach((key, value) {
        permsToSave[key.toString()] = value;
      });

      final jsonPerms = jsonEncode(permsToSave);
      
      final updatedUser = User(
        id: widget.accountant.id,
        uuid: widget.accountant.uuid,
        username: widget.accountant.username,
        name: widget.accountant.name,
        role: widget.accountant.role,
        parentId: widget.accountant.parentId,
        createdAt: widget.accountant.createdAt,
        email: widget.accountant.email,
        phone: widget.accountant.phone,
        notes: widget.accountant.notes,
        permissions: jsonPerms,
      );

      await db.updateUser(
        updatedUser,
        widget.accountant,
        performedById: auth.currentUser?.id,
        performedByName: auth.currentUser?.name ?? auth.currentUser?.username,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الصلاحيات بنجاح'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        title: Text('صلاحيات ${widget.accountant.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _screenTitles.keys.map((index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: CheckboxListTile(
                    title: Text(_screenTitles[index]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    value: _permissions[index],
                    activeColor: Colors.blue,
                    onChanged: (val) {
                      setState(() {
                        _permissions[index] = val ?? false;
                      });
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('حفظ الصلاحيات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
