import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/password_utils.dart';

class DeveloperUserEditScreen extends StatefulWidget {
  final User user;
  const DeveloperUserEditScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<DeveloperUserEditScreen> createState() => _DeveloperUserEditScreenState();
}

class _DeveloperUserEditScreenState extends State<DeveloperUserEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late String _selectedRole;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isPasswordHashed = false;
  String? _originalPassword;

  final List<String> _roles = ['STORE_MANAGER', 'SUPER_ADMIN', 'ACCOUNTANT'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _usernameController = TextEditingController(text: widget.user.username);
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _passwordController = TextEditingController(); // Initially empty
    _selectedRole = widget.user.role;
    
    // Fetch current password if possible, or just leave it empty for "no change"
    // Actually the user wants to "reset all passwords", so maybe I should allow setting a new one.
    // I'll check if I can get the password from the DB.
    _loadCurrentPassword();
  }

  Future<void> _loadCurrentPassword() async {
    final db = context.read<DatabaseService>();
    final result = await (await db.database).query(
      'users',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [widget.user.id],
    );
    if (result.isNotEmpty && mounted) {
      final password = result.first['password'] as String;
      setState(() {
        _isPasswordHashed = PasswordUtils.isHashed(password);
        _originalPassword = password;
        if (_isPasswordHashed) {
          _passwordController.text = ''; // Leave empty if hashed
        } else {
          _passwordController.text = password;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final auth = context.read<AuthService>();

      final updatedUser = User(
        id: widget.user.id,
        uuid: widget.user.uuid,
        parentId: widget.user.parentId,
        username: _usernameController.text.trim(),
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _selectedRole,
        balance: widget.user.balance,
        isPermanentCustomer: widget.user.isPermanentCustomer,
        creditLimit: widget.user.creditLimit,
        version: widget.user.version,
        createdAt: widget.user.createdAt,
      );

      await db.updateUser(updatedUser, widget.user, 
        performedById: auth.currentUser?.id, 
        performedByName: auth.currentUser?.name ?? auth.currentUser?.username,
        reason: 'تعديل من قبل المطور'
      );

      if (_passwordController.text.isNotEmpty && _passwordController.text != _originalPassword) {
        await db.updateUserPassword(widget.user.id!, _passwordController.text);
      }

      if (mounted) {
        AppSnackBar.success(context, 'تم حفظ البيانات بنجاح');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'خطأ في الحفظ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تعديل: ${widget.user.name}'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTextField(
                    controller: _nameController,
                    label: 'الاسم الكامل',
                    icon: Icons.person,
                    validator: (v) => v!.isEmpty ? 'يرجى إدخال الاسم' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _usernameController,
                    label: 'اسم المستخدم',
                    icon: Icons.alternate_email,
                    validator: (v) => v!.isEmpty ? 'يرجى إدخال اسم المستخدم' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _emailController,
                    label: 'البريد الإلكتروني',
                    icon: Icons.email,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _phoneController,
                    label: 'رقم الهاتف',
                    icon: Icons.phone,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      labelText: 'الدور الوظيفي',
                      prefixIcon: const Icon(Icons.security, color: Color(0xFF1E3A8A)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _roles.map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(r),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedRole = v!),
                  ),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('حفظ التغييرات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1E3A8A)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: _isPasswordHashed ? 'كلمة المرور (مشفرة - اتركها فارغة لعدم التغيير)' : 'كلمة المرور',
        prefixIcon: const Icon(Icons.lock, color: Color(0xFF1E3A8A)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        hintText: _isPasswordHashed ? 'ادخل كلمة مرور جديدة لتغييرها' : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            if (!_isPasswordHashed) 
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _passwordController.text));
                  AppSnackBar.success(context, 'تم نسخ كلمة المرور');
                },
              ),
          ],
        ),
      ),
      validator: (v) {
        if (!_isPasswordHashed && (v == null || v.isEmpty)) {
          return 'يرجى إدخال كلمة المرور';
        }
        return null;
      },
    );
  }
}
