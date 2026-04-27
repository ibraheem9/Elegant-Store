import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'add_accountant_screen.dart';

class AccountantsScreen extends StatefulWidget {
  const AccountantsScreen({Key? key}) : super(key: key);

  @override
  State<AccountantsScreen> createState() => _AccountantsScreenState();
}

class _AccountantsScreenState extends State<AccountantsScreen> {
  List<User> _accountants = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAccountants();
  }

  Future<void> _loadAccountants() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final accountants = await db.getAccountants();
    if (mounted) {
      setState(() {
        _accountants = accountants;
        _isLoading = false;
      });
    }
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<void> _deleteAccountant(User accountant) async {
    final db = context.read<DatabaseService>();

    // Guard: employee has linked operations
    final hasOps = await db.accountantHasOperations(accountant.id!);
    if (!mounted) return;

    if (hasOps) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.block_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('لا يمكن الحذف', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'الموظف "${accountant.name}" مرتبط بعمليات في النظام.\n'
            'لا يمكن حذفه للحفاظ على سجلات العمليات.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد الحذف', fontWeight: FontWeight.bold),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من حذف الموظف؟'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(accountant.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'لن يتمكن الموظف من تسجيل الدخول بعد الحذف.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await db.softDeleteUser(accountant.id!);
      final actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: accountant.id!,
        targetType: 'ACCOUNTANT',
        action: 'DELETE',
        summary: 'حذف الموظف: ${accountant.name}',
        performedById: actUser?.id,
        performedByName: actUser?.name,
        storeManagerId: actUser?.parentId ?? actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      _loadAccountants();
    }
  }

  // ── EDIT ──────────────────────────────────────────────────────────────────

  Future<void> _editAccountant(User accountant) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAccountantSheet(
        accountant: accountant,
        onSaved: _loadAccountants,
      ),
    );
  }

  // ── ADD ───────────────────────────────────────────────────────────────────

  Future<void> _navigateToAddAccountant() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddAccountantScreen()),
    );
    if (result == true) _loadAccountants();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إدارة الموظفين',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'إضافة وإدارة الموظفين (المحاسبين) وصلاحياتهم',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _accountants.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: isDark ? Colors.white24 : Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'لا يوجد موظفون حالياً',
                              style: TextStyle(color: isDark ? Colors.white30 : Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
                        itemCount: _accountants.length,
                        itemBuilder: (context, index) => _buildAccountantCard(
                          _accountants[index],
                          isDark,
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddAccountant,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'إضافة موظف',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAccountantCard(User acc, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  acc.name.isNotEmpty ? acc.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    acc.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.alternate_email, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        acc.username,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'محاسب',
                      style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF3B82F6)),
                  tooltip: 'تعديل',
                  onPressed: () => _editAccountant(acc),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'حذف',
                  onPressed: () => _deleteAccountant(acc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _EditAccountantSheet extends StatefulWidget {
  final User accountant;
  final VoidCallback onSaved;

  const _EditAccountantSheet({required this.accountant, required this.onSaved});

  @override
  State<_EditAccountantSheet> createState() => _EditAccountantSheetState();
}

class _EditAccountantSheetState extends State<_EditAccountantSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.accountant.name);
    _usernameController = TextEditingController(text: widget.accountant.username);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء الاسم واسم المستخدم'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = context.read<DatabaseService>();
      final auth = context.read<AuthService>();

      // Build updated user — preserve all original fields
      final updated = User(
        id: widget.accountant.id,
        uuid: widget.accountant.uuid,
        username: username,
        name: name,
        role: widget.accountant.role,
        parentId: widget.accountant.parentId,
        createdAt: widget.accountant.createdAt,
        email: widget.accountant.email,
        phone: widget.accountant.phone,
        notes: widget.accountant.notes,
      );

      await db.updateUser(updated, widget.accountant);

      // Update password if provided
      if (password.isNotEmpty) {
        await db.updateUserPassword(widget.accountant.id!, password);
      }

      // Log the edit
      final actUser = auth.currentUser;
      db.logActivity(
        targetId: widget.accountant.id!,
        targetType: 'ACCOUNTANT',
        action: 'UPDATE',
        summary: 'تعديل بيانات الموظف: ${widget.accountant.name}',
        performedById: actUser?.id,
        performedByName: actUser?.name,
        storeManagerId: actUser?.parentId ?? actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث بيانات الموظف بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'تعديل بيانات الموظف',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'يمكنك تعديل الاسم، اسم المستخدم، أو كلمة المرور',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 24),
            _buildField('الاسم الكامل', _nameController, Icons.person_outline, isDark),
            const SizedBox(height: 16),
            _buildField('اسم المستخدم', _usernameController, Icons.alternate_email, isDark),
            const SizedBox(height: 16),
            _buildPasswordField(isDark),
            const SizedBox(height: 8),
            Text(
              'اتركها فارغة إذا لم تريد تغيير كلمة المرور',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'حفظ التعديلات',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('كلمة المرور الجديدة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF3B82F6), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.grey,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            hintText: '••••••••',
          ),
        ),
      ],
    );
  }
}
