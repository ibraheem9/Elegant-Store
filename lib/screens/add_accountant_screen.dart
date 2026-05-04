import '../utils/timestamp_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class AddAccountantScreen extends StatefulWidget {
  const AddAccountantScreen({Key? key}) : super(key: key);

  @override
  State<AddAccountantScreen> createState() => _AddAccountantScreenState();
}

class _AddAccountantScreenState extends State<AddAccountantScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveAccountant() async {
    if (_nameController.text.isEmpty || _usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
        const SnackBar(content: Text('يرجى ملء جميع الحقول'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = context.read<DatabaseService>();
      final auth = context.read<AuthService>();

      final accountant = User(
        uuid: '',
        username: _usernameController.text.trim(),
        name: _nameController.text.trim(),
        role: 'ACCOUNTANT',
        parentId: auth.currentUser?.getStoreManagerIdLocal(),
        createdAt: TimestampFormatter.nowUtc(),
      );

      final newAccId = await db.insertUser(accountant, _passwordController.text);
      final actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: newAccId,
        targetType: 'ACCOUNTANT',
        action: 'CREATE',
        summary: 'إضافة محاسب جديد: \${accountant.name}',
        performedById: actUser?.id,
        performedByName: actUser?.name,
        storeManagerId: actUser?.parentId ?? actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: \$e'));

      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          const SnackBar(content: Text('تمت إضافة الموظف بنجاح'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
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
        title: const Text('إضافة موظف جديد'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 56),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'بيانات الموظف',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(height: 8),
                Text(
                  'سيتمكن الموظف (المحاسب) من الوصول إلى شاشات البيع والزبائن فقط',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                _buildField('الاسم الكامل للموظف', _nameController, Icons.person, isDark),
                const SizedBox(height: 20),
                _buildField('اسم المستخدم للدخول', _usernameController, Icons.alternate_email, isDark),
                const SizedBox(height: 20),
                _buildField('كلمة المرور', _passwordController, Icons.lock, isDark, obscure: true),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveAccountant,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('حفظ الموظف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, bool isDark, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF3B82F6)),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            hintText: 'أدخل $label',
          ),
        ),
      ],
    );
  }
}
