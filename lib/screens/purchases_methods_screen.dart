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
  bool _isReordering = false;
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;

  final List<Map<String, String>> _types = [
    {'value': 'cash', 'label': 'نقدي'},
    {'value': 'app',  'label': 'تطبيق إلكتروني'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshMethods();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _refreshMethods() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final m = await db.getAllPaymentMethods(category: 'PURCHASE');
      setState(() {
        _methods = m;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('فشل تحميل البيانات: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

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
        backgroundColor:
            updated.isActive == 1 ? Colors.green : const Color(0xFF1E3A5F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    final inactiveCount = _methods.where((m) => m.isActive != 1).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 32,
              isMobile ? 16 : 24,
              isMobile ? 16 : 32,
              120, // space for fixed bottom buttons
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Warning banner ──────────────────────────────────────
                if (inactiveCount > 0) ...[
                  _buildWarningBanner(inactiveCount, isDark),
                  const SizedBox(height: 16),
                ],

                // ── Reorder hint ────────────────────────────────────────
                if (_isReordering)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B74FF).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF0B74FF).withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.drag_indicator_rounded,
                            size: 18, color: Color(0xFF0B74FF)),
                        SizedBox(width: 8),
                        Text('اسحب البطاقات لتغيير الترتيب',
                            style: TextStyle(
                                color: Color(0xFF0B74FF),
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ],
                    ),
                  ),

                // ── List ────────────────────────────────────────────────
                if (_isLoading)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: CircularProgressIndicator(),
                  ))
                else if (_methods.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Text('لا يوجد طرق دفع مشتريات مسجلة',
                          style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.grey)),
                    ),
                  )
                else if (_isReordering)
                  _buildReorderableList(isDark)
                else
                  _buildMethodsGrid(isDark, isMobile),
              ],
            ),
          ),

          // ── Fixed bottom buttons ────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomButtons(isDark, isMobile),
          ),
        ],
      ),
    );
  }

  // ── Warning banner ─────────────────────────────────────────────────────────
  Widget _buildWarningBanner(int count, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withOpacity(isDark ? 0.3 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF1E3A5F).withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: Color(0xFF1E3A5F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'طريقة دفع غير فعّالة' : 'طرق دفع غير فعّالة'} — لن تظهر عند تسجيل مشتريات جديدة',
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1E3A5F),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fixed bottom buttons ───────────────────────────────────────────────────
  Widget _buildBottomButtons(bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          isMobile ? 16 : 32, 12, isMobile ? 16 : 32, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
            top: BorderSide(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Row(
        children: [
          // Add button
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isReordering ? null : () => _showMethodDialog(),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(
                  isMobile ? 'إضافة' : 'إضافة طريقة دفع',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B74FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sort / Save order button
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (_isReordering) {
                    await context
                        .read<DatabaseService>()
                        .updatePaymentMethodsOrder(_methods);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('تم حفظ الترتيب الجديد'),
                          backgroundColor: Colors.green),
                    );
                  }
                  setState(() => _isReordering = !_isReordering);
                },
                icon: Icon(
                    _isReordering
                        ? Icons.check_rounded
                        : Icons.reorder_rounded,
                    size: 20),
                label: Text(
                  _isReordering ? 'حفظ الترتيب' : 'تغيير الترتيب',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isReordering
                      ? Colors.green[600]
                      : const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid ───────────────────────────────────────────────────────────────────
  Widget _buildMethodsGrid(bool isDark, bool isMobile) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: isMobile ? 160 : 170,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _methods.length,
      itemBuilder: (context, index) =>
          _buildMethodCard(_methods[index], isDark),
    );
  }

  // ── Reorderable list ───────────────────────────────────────────────────────
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
            Container(
              key: ValueKey(method.id),
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator_rounded,
                      color: Colors.grey, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(method.name,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black)),
                        Text(
                          method.type == 'cash' ? 'نقدي' : 'تطبيق إلكتروني',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF0B74FF)),
                        ),
                      ],
                    ),
                  ),
                  if (method.isActive != 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('غير فعّال',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1E3A5F),
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Slim method card ───────────────────────────────────────────────────────
  Widget _buildMethodCard(PaymentMethod method, bool isDark) {
    final bool isCash = method.type == 'cash';
    final Color typeColor =
        isCash ? Colors.green : const Color(0xFF0B74FF);
    final IconData typeIcon =
        isCash ? Icons.money_rounded : Icons.smartphone_rounded;
    final bool isInactive = method.isActive != 1;

    return Opacity(
      opacity: isInactive ? 0.7 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isInactive
                ? const Color(0xFF1E3A5F).withOpacity(0.35)
                : (isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0)),
            width: isInactive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.02), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(typeIcon, size: 20, color: typeColor),
                ),
                const SizedBox(width: 8),
                if (isInactive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('غير فعّال',
                        style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF1E3A5F),
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                _actionBtn(Icons.edit_outlined, const Color(0xFF0B74FF),
                    () => _showMethodDialog(method: method), isDark),
                const SizedBox(width: 4),
                _actionBtn(Icons.delete_outline_rounded, Colors.redAccent,
                    () => _confirmDelete(method), isDark),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              method.name,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              isCash ? 'نقدي' : 'تطبيق إلكتروني',
              style: TextStyle(
                  fontSize: 12,
                  color: typeColor,
                  fontWeight: FontWeight.w600),
            ),
            if (method.description != null &&
                method.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                method.description!,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white30
                        : const Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInactive ? 'غير فعّال' : 'فعّال في المشتريات',
                  style: TextStyle(
                      fontSize: 11,
                      color: isInactive
                          ? const Color(0xFF1E3A5F)
                          : Colors.green,
                      fontWeight: FontWeight.bold),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: !isInactive,
                    activeColor: Colors.green,
                    inactiveThumbColor: const Color(0xFF1E3A5F),
                    onChanged: (_) => _toggleActive(method),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  // ── Dialog ─────────────────────────────────────────────────────────────────
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
                  ? 'إضافة طريقة دفع للمشتريات'
                  : 'تعديل طريقة الدفع',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black),
            ),
            content: SizedBox(
              width: 420,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('اسم الطريقة', isDark),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: _inputDeco(
                            'مثلاً: نقدي، تطبيق إبراهيم...', isDark),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'يرجى إدخال الاسم' : null,
                      ),
                      const SizedBox(height: 16),
                      _label('نوع الوسيلة', isDark),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        decoration: _inputDeco('', isDark),
                        items: _types
                            .map((t) => DropdownMenuItem(
                                value: t['value'],
                                child: Text(t['label']!)))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => _selectedType = v!),
                      ),
                      const SizedBox(height: 16),
                      _label('وصف إضافي (اختياري)', isDark),
                      TextFormField(
                        controller: _descController,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black),
                        maxLines: 2,
                        decoration: _inputDeco(
                            'ملاحظات بسيطة عن هذه الطريقة...', isDark),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    try {
                      final db = context.read<DatabaseService>();
                      final newMethod = PaymentMethod(
                        id: method?.id,
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        category: 'PURCHASE',
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
                      _showError('خطأ أثناء الحفظ: $e');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B74FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('حفظ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87)),
      );

  InputDecoration _inputDeco(String hint, bool isDark) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
        filled: true,
        fillColor:
            isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : Colors.transparent)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      );

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
              'هل أنت متأكد من حذف "${method.name}"؟\nستبقى البيانات القديمة محفوظة ولكن لن تظهر هذه الطريقة مجدداً.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54)),
            ),
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
                          backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  _showError('فشل الحذف: $e');
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
