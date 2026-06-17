import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'developer_user_edit_screen.dart';

class DeveloperManagementScreen extends StatefulWidget {
  const DeveloperManagementScreen({Key? key}) : super(key: key);

  @override
  State<DeveloperManagementScreen> createState() => _DeveloperManagementScreenState();
}

class _DeveloperManagementScreenState extends State<DeveloperManagementScreen> {
  List<User> _staff = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final staff = await db.getAllStaff();
    if (mounted) {
      setState(() {
        _staff = staff;
        _isLoading = false;
      });
    }
  }

  String _translateRole(String role) {
    switch (role) {
      case 'STORE_MANAGER':
        return 'مدير متجر';
      case 'SUPER_ADMIN':
        return 'مدير عام';
      case 'ACCOUNTANT':
        return 'محاسب';
      default:
        return role;
    }
  }

  Future<void> _handleLogout(AuthService auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.logout_rounded, color: Colors.red),
          ],
        ),
        content: const Text(
          'هل تريد تسجيل الخروج؟',
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.start,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('تسجيل الخروج'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة طاقم العمل (Developer)'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(auth),
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text('الاسم', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('اسم المستخدم', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الدور', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('إجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: _staff.map((user) {
                          return DataRow(cells: [
                            DataCell(Text(user.name)),
                            DataCell(Text(user.username)),
                            DataCell(Text(_translateRole(user.role))),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DeveloperUserEditScreen(user: user),
                                    ),
                                  );
                                  if (result == true) _loadStaff();
                                },
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
