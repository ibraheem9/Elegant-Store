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
    setState(() {
      _accountants = accountants;
      _isLoading = false;
    });
  }

  Future<void> _deleteAccountant(User accountant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الموظف "${accountant.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final db = context.read<DatabaseService>();
      await db.softDeleteUser(accountant.id!);
      _loadAccountants();
    }
  }

  void _navigateToAddAccountant() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddAccountantScreen()),
    );
    if (result == true) {
      _loadAccountants();
    }
  }

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
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إدارة الموظفين', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text('إضافة وإدارة الموظفين (المحاسبين) وصلاحياتهم', style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B), fontSize: 15)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _accountants.isEmpty
                    ? Center(child: Text('لا يوجد موظفون حالياً', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        itemCount: _accountants.length,
                        itemBuilder: (context, index) {
                          final acc = _accountants[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.withOpacity(0.1),
                                child: Text(acc.name[0], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('@${acc.username}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteAccountant(acc),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddAccountant,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('إضافة موظف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
