import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class PurchasesMethodsScreen extends StatefulWidget {
  const PurchasesMethodsScreen({Key? key}) : super(key: key);

  @override
  State<PurchasesMethodsScreen> createState() =>
      _PurchasesMethodsScreenState();
}

class _PurchasesMethodsScreenState extends State<PurchasesMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = 'cash';
  bool _isLoading = true;
  List<PaymentMethod> _methods = [];

  final List<Map<String, String>> _types = [
    {'value': 'cash', 'label': 'نقدي (نقدي)'},
    {'value': 'app', 'label': 'تطبيق إلكتروني'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshMethods();
  }

  Future<void> _refreshMethods() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      // Management screen: show ALL non-deleted methods (active + inactive)
      final m = await db.getAllPaymentMethods(category: 'PURCHASE');
      setState(() {
        _methods = m;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── Toggle active/inactive ─────────────────────────────────────────────

  Future<void> _toggleActive(PaymentMethod method) async {
    final db = context.read<DatabaseService>();
    final updated = PaymentMethod(
      id: method.id,
      uuid: method.uuid,
      storeManagerId: method.storeManagerId,
      name: method.name,
      type: method.type,
      category: method.category,
      description: method.description,
      isActive: method.isActive == 1 ? 0 : 1,
      sortOrder: method.sortOrder,
      version: method.version,
      createdAt: method.createdAt,
      isSynced: 0,
    );
    await db.updatePaymentMethod(updated);
    _refreshMethods();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated.isActive == 1
            ? 'تم تفعيل "${method.name}" — ستظهر في المشتريات'
            : 'تم إيقاف "${method.name}" — لن تظهر في المشتريات'),
        backgroundColor: updated.isActive == 1 ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMethodDialog(),
        label: const Text('إضافة وسيلة دفع للمشتريات',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.add_business_rounded, color: Colors.white),
        backgroundColor: Colors.orange[800],
      ),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'طرق دفع المشتريات',
              style: TextStyle(
                  fontSize: isMobile ? 24 : 32,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'إدارة الوسائل المستخدمة لدفع مستحقات الموردين. الطرق غير الفعّالة لن تظهر عند تسجيل مشتريات جديدة.',
              style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _methods.isEmpty
                      ? Center(
                          child: Text('لا يوجد طرق دفع مشتريات مسجلة',
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white30
                                      : Colors.grey)))
                      : GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisExtent: isMobile ? 250 : 270,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                          ),
                          itemCount: _methods.length,
                          itemBuilder: (context, index) {
                            final method = _methods[index];
                            return _buildMethodCard(method, isDark);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodCard(PaymentMethod method, bool isDark) {
    final IconData icon;
    final Color color;

    if (method.type == 'cash') {
      icon = Icons.money_rounded;
      color = Colors.green;
    } else {
      icon = Icons.smartphone_rounded;
      color = Colors.blue;
    }

    final bool isInactive = method.isActive != 1;

    return Opacity(
      opacity: isInactive ? 0.65 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isInactive
                ? Colors.orange.withOpacity(0.5)
                : (isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0)),
            width: isInactive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 8),
                if (isInactive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('غير فعّال',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 20,
                      color: isDark
                          ? Colors.white60
                          : const Color(0xFF64748B)),
                  onPressed: () => _showMethodDialog(method: method),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(method),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              method.name,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              method.type == 'cash' ? 'نقدي (نقدي)' : 'تطبيق إلكتروني',
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600),
            ),
            if (method.description != null &&
                method.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                method.description!,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.white30
                        : const Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Spacer(),
            // Toggle active/inactive switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInactive ? 'إيقاف المشتريات' : 'فعّال في المشتريات',
                  style: TextStyle(
                      fontSize: 12,
                      color: isInactive ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.bold),
                ),
                Switch.adaptive(
                  value: !isInactive,
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.orange,
                  onChanged: (_) => _toggleActive(method),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMethodDialog({PaymentMethod? method}) {
    if (method != null) {
      _nameController.text = method.name;
      _descController.text = method.description ?? '';
      _selectedType = method.type;
    } else {
      _nameController.clear();
      _descController.clear();
      _selectedType = 'cash';
    }

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.transparent)),
            title: Text(
                method == null
                    ? 'إضافة وسيلة دفع للمشتريات'
                    : 'تعديل وسيلة الدفع',
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black)),
            content: SizedBox(
              width: 450,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText:
                              'اسم الوسيلة (مثلاً: نقدي، تطبيق إبراهيم، ...)',
                          labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: 'نوع الوسيلة',
                          labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87),
                        ),
                        items: _types
                            .map((t) => DropdownMenuItem(
                                value: t['value'],
                                child: Text(t['label']!)))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => _selectedType = v!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: 'ملاحظات',
                          labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('إلغاء',
                      style: TextStyle(
                          color: isDark
                              ? Colors.white60
                              : Colors.black54))),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final db = context.read<DatabaseService>();
                    final newMethod = PaymentMethod(
                      id: method?.id,
                      name: _nameController.text,
                      type: _selectedType,
                      category: 'PURCHASE',
                      description: _descController.text,
                      isActive: method?.isActive ?? 1,
                    );
                    if (method == null) {
                      await db.insertPaymentMethod(newMethod);
                    } else {
                      await db.updatePaymentMethod(newMethod);
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      _refreshMethods();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[800],
                    foregroundColor: Colors.white),
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(PaymentMethod method) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          title: Text('تأكيد الحذف',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black)),
          content: Text('هل أنت متأكد من حذف "${method.name}"؟',
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: isDark
                            ? Colors.white60
                            : Colors.black54))),
            TextButton(
              onPressed: () async {
                await context
                    .read<DatabaseService>()
                    .deletePaymentMethod(method.id!);
                if (mounted) {
                  Navigator.pop(context);
                  _refreshMethods();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم الحذف بنجاح'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('حذف',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
