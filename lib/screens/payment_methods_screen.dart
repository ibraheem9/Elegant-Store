import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = 'cash';
  bool _isReordering = false;
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;

  final List<Map<String, String>> _types = [
    {'value': 'cash', 'label': 'كاش (نقدي)'},
    {'value': 'app', 'label': 'تطبيق إلكتروني'},
    {'value': 'deferred', 'label': 'أجل (دين)'},
    {'value': 'credit_balance', 'label': 'رصيد المحفظة'},
    {'value': 'unpaid', 'label': 'غير مدفوع'},
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
      // so the user can see, edit, toggle, or permanently remove any method.
      final m = await db.getAllPaymentMethods(category: 'SALE');
      setState(() {
        _methods = m;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('فشل تحميل البيانات: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
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
            ? 'تم تفعيل "${method.name}" — ستظهر في شاشة البيع'
            : 'تم إيقاف "${method.name}" — لن تظهر في شاشة البيع'),
        backgroundColor: updated.isActive == 1 ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isReordering)
            FloatingActionButton.extended(
              heroTag: 'addBtn',
              onPressed: () => _showMethodDialog(),
              label: const Text('إضافة طريقة دفع مبيعات',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              backgroundColor: const Color(0xFF0B74FF),
            ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'reorderBtn',
            onPressed: () async {
              if (_isReordering) {
                await context
                    .read<DatabaseService>()
                    .updatePaymentMethodsOrder(_methods);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الترتيب الجديد')));
              }
              setState(() => _isReordering = !_isReordering);
            },
            label: Text(_isReordering ? 'حفظ الترتيب' : 'تغيير الترتيب',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            icon: Icon(
                _isReordering ? Icons.check_rounded : Icons.reorder_rounded,
                color: Colors.white),
            backgroundColor:
                _isReordering ? Colors.green[600] : const Color(0xFF1E293B),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32.0, 32.0, 32.0, 150.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'طرق دفع المبيعات',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
                const Spacer(),
                if (_isReordering)
                  const Text(
                    'قم بسحب العناصر لترتيبها',
                    style: TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'إدارة طرق الدفع المتاحة للزبائن. الطرق غير الفعّالة لن تظهر في شاشة البيع لكن تبقى هنا للإدارة.',
              style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
            const SizedBox(height: 32),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isReordering
                    ? _buildReorderableList(isDark)
                    : _buildMethodsGrid(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodsGrid(bool isDark) {
    if (_methods.isEmpty) {
      return Center(
          child: Text('لا يوجد طرق دفع مبيعات مسجلة',
              style: TextStyle(
                  color: isDark ? Colors.white30 : Colors.grey)));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 250,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _methods.length,
      itemBuilder: (context, index) {
        final method = _methods[index];
        return _buildMethodCard(method, isDark);
      },
    );
  }

  Widget _buildReorderableList(bool isDark) {
    return Theme(
      data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
      child: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _methods.removeAt(oldIndex);
            _methods.insert(newIndex, item);
          });
        },
        children: [
          for (final method in _methods)
            Card(
              key: ValueKey(method.id),
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0))),
              child: ListTile(
                leading:
                    const Icon(Icons.drag_indicator_rounded, color: Colors.grey),
                title: Text(method.name,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                subtitle: Text(
                    _types
                            .firstWhere((t) => t['value'] == method.type,
                                orElse: () => {'label': method.type})['label'] ??
                        method.type,
                    style: const TextStyle(color: Colors.blue)),
                trailing: const Icon(Icons.reorder_rounded, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(PaymentMethod method, bool isDark) {
    IconData icon;
    Color color;

    switch (method.type) {
      case 'cash':
        icon = Icons.money_rounded;
        color = Colors.green;
        break;
      case 'app':
        icon = Icons.smartphone_rounded;
        color = const Color(0xFF0B74FF);
        break;
      case 'deferred':
        icon = Icons.timer_outlined;
        color = Colors.orange;
        break;
      case 'credit_balance':
        icon = Icons.account_balance_wallet_rounded;
        color = Colors.purple;
        break;
      case 'unpaid':
        icon = Icons.warning_amber_rounded;
        color = Colors.redAccent;
        break;
      default:
        icon = Icons.payment_rounded;
        color = Colors.grey;
    }

    final bool isInactive = method.isActive != 1;

    return Opacity(
      opacity: isInactive ? 0.65 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
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
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, size: 26, color: color),
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
                _buildActionButton(Icons.edit_outlined, Colors.orange,
                    () => _showMethodDialog(method: method), isDark),
                const SizedBox(width: 6),
                _buildActionButton(
                    Icons.delete_outline_rounded,
                    Colors.redAccent,
                    () => _confirmDelete(method),
                    isDark),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              method.name,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            Text(
              _types
                      .firstWhere((t) => t['value'] == method.type,
                          orElse: () => {'label': method.type})['label'] ??
                  method.type,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.bold),
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
                  isInactive ? 'إيقاف البيع' : 'فعّال في البيع',
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

  Widget _buildActionButton(
      IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: color),
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
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.transparent)),
            title: Text(
              method == null ? 'إضافة طريقة دفع مبيعات' : 'تعديل طريقة الدفع',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black),
            ),
            content: SizedBox(
              width: 450,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('اسم الطريقة', isDark),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: _inputDecoration(
                            'مثلاً: كاش، بنك فلسطين، حمودة...', isDark),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'يرجى إدخال الاسم' : null,
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('نوع العملية', isDark),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: _inputDecoration('', isDark),
                        items: _types
                            .map((t) => DropdownMenuItem(
                                value: t['value'],
                                child: Text(t['label']!)))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => _selectedType = v!),
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('وصف إضافي (اختياري)', isDark),
                      TextFormField(
                        controller: _descController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        maxLines: 2,
                        decoration: _inputDecoration(
                            'اكتب ملاحظات بسيطة عن هذه الطريقة...', isDark),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                    try {
                      final db = context.read<DatabaseService>();
                      final newMethod = PaymentMethod(
                        id: method?.id,
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        category: 'SALE',
                        description: _descController.text.trim(),
                        isActive: method?.isActive ?? 1,
                        sortOrder: method?.sortOrder ?? 0,
                      );
                      if (method == null) {
                        await db.insertPaymentMethod(newMethod);
                      } else {
                        await db.updatePaymentMethod(newMethod);
                      }
                      if (mounted) {
                        Navigator.pop(context);
                        _refreshMethods();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(method == null
                                  ? 'تمت الإضافة بنجاح'
                                  : 'تم التعديل بنجاح'),
                              backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      _showErrorSnackBar('خطأ أثناء الحفظ: $e');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B74FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('حفظ البيانات',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87)),
    );
  }

  InputDecoration _inputDecoration(String hint, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: isDark ? Colors.white24 : Colors.black26, fontSize: 14),
      filled: true,
      fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : Colors.transparent)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  void _confirmDelete(PaymentMethod method) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          title: const Text('تأكيد الحذف',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
              'هل أنت متأكد من حذف "${method.name}"؟ ستبقى البيانات القديمة محفوظة ولكن لن تظهر هذه الطريقة مجدداً.'),
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
                try {
                  await context
                      .read<DatabaseService>()
                      .deletePaymentMethod(method.id!);
                  if (mounted) {
                    Navigator.pop(context);
                    _refreshMethods();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم الحذف بنجاح'),
                            backgroundColor: Colors.orange));
                  }
                } catch (e) {
                  _showErrorSnackBar('فشل الحذف: $e');
                }
              },
              child: const Text('حذف',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
