import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../widgets/shimmer_loading.dart';
import 'purchases_recycle_bin_screen.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({Key? key}) : super(key: key);

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _merchantController = TextEditingController();
  final _amountController   = TextEditingController();
  final _notesController    = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  List<PaymentMethod> _purchaseMethods = [];
  PaymentMethod? _selectedMethod;
  Map<int, List<Purchase>> _groupedPurchases = {};
  double _totalPurchases = 0.0;
  bool _isLoading        = false;
  bool _isInitialLoading = true;

  // Filter state
  DateTime _startDate  = DateTime.now();
  DateTime _endDate    = DateTime.now();
  String _activeFilter = 'today'; // today, week, month, custom

  @override
  void initState() {
    super.initState();
    _setFilter('today');
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Date filter helpers ──────────────────────────────────────────────────

  void _setFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _activeFilter = filter;
      if (filter == 'today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'week') {
        _startDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        _endDate   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _loadData();
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.orange[800]!,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _activeFilter = 'custom';
        _startDate    = picked.start;
        _endDate      = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    final db = context.read<DatabaseService>();
    try {
      final methods = await db.getPaymentMethods(category: 'PURCHASE');
      final seen    = <int?>{};
      final unique  = methods.where((m) => seen.add(m.id)).toList();

      Map<int, List<Purchase>> grouped = {};
      double total = 0.0;
      for (var m in unique) {
        final list = await db.getPurchasesByMethod(m.id!, start: _startDate, end: _endDate);
        grouped[m.id!] = list;
        for (var p in list) total += p.amount;
      }

      if (!mounted) return;
      setState(() {
        _purchaseMethods  = unique;
        _groupedPurchases = grouped;
        _totalPurchases   = total;
        if (unique.isNotEmpty) {
          _selectedMethod = _selectedMethod != null
              ? unique.firstWhere((m) => m.id == _selectedMethod!.id,
                  orElse: () => unique.first)
              : unique.first;
        }
        _isInitialLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading purchases: $e');
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  // ── Add purchase ─────────────────────────────────────────────────────────

  Future<void> _addPurchase() async {
    final amount = double.tryParse(_amountController.text);
    if (_merchantController.text.trim().isEmpty || amount == null || amount <= 0) {
      _snack('يرجى إدخال اسم المورد ومبلغ صحيح', Colors.redAccent);
      return;
    }
    if (_selectedMethod == null) {
      _snack('يرجى اختيار وسيلة الدفع أولاً', Colors.redAccent);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final db  = context.read<DatabaseService>();
      final now = DateTime.now();
      final dt  = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
          now.hour, now.minute, now.second);
      final purchaseId = await db.insertPurchase(Purchase(
        merchantName:  _merchantController.text.trim(),
        amount:        amount,
        paymentSource: _selectedMethod?.type == 'app' ? 'APP' : 'CASH',
        paymentMethodId: _selectedMethod?.id,
        notes:         _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdAt:     dt.toIso8601String(),
      ));
      final actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: purchaseId,
        targetType: 'PURCHASE',
        action: 'CREATE',
        summary: 'مشتريات جديدة من ${_merchantController.text.trim()} بمبلغ ${amount.toStringAsFixed(2)} ₪',
        performedById: actUser?.id,
        performedByName: actUser?.name,
        storeManagerId: actUser?.parentId ?? actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      _merchantController.clear();
      _amountController.clear();
      _notesController.clear();
      await _loadData();
      _snack('تمت إضافة المشتريات بنجاح', Colors.green);
    } catch (e) {
      _snack('خطأ أثناء الحفظ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Delete purchase (soft) ───────────────────────────────────────────────

  Future<void> _deletePurchase(Purchase p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد نقل فاتورة "${p.merchantName}" (${p.amount.toStringAsFixed(2)} ₪) إلى سلة المحذوفات؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && p.id != null) {
      final db2 = context.read<DatabaseService>();
      await db2.softDeletePurchase(p.id!);
      final actUser = context.read<AuthService>().currentUser;
      db2.logActivity(
        targetId: p.id!,
        targetType: 'PURCHASE',
        action: 'DELETE',
        summary: 'حذف مشتريات ${p.merchantName} بمبلغ ${p.amount.toStringAsFixed(2)} ₪',
        performedById: actUser?.id,
        performedByName: actUser?.name,
        storeManagerId: actUser?.parentId ?? actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      await _loadData();
      _snack('تم نقل الفاتورة إلى سلة المحذوفات', Colors.redAccent);
    }
  }

  // ── Edit purchase with audit log ─────────────────────────────────────────

  Future<void> _showEditDialog(Purchase p) async {
    final amountCtrl   = TextEditingController(text: p.amount.toStringAsFixed(2));
    final merchantCtrl = TextEditingController(text: p.merchantName);
    final notesCtrl    = TextEditingController(text: p.notes ?? '');
    final reasonCtrl   = TextEditingController();
    // Parse existing createdAt to pre-fill the date picker
    DateTime editSelectedDate = DateTime.tryParse(p.createdAt) ?? DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('تعديل فاتورة مشتريات'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: merchantCtrl,
                decoration: const InputDecoration(labelText: 'اسم المورد', prefixIcon: Icon(Icons.business, size: 18)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: const InputDecoration(labelText: 'المبلغ الجديد', prefixIcon: Icon(Icons.payments, size: 18)),
              ),
              const SizedBox(height: 10),
              // Date picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: editSelectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) {
                    setDialogState(() => editSelectedDate = DateTime(
                      picked.year, picked.month, picked.day,
                      editSelectedDate.hour, editSelectedDate.minute, editSelectedDate.second,
                    ));
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الفاتورة',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(DateFormat('yyyy/MM/dd').format(editSelectedDate)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.note, size: 18)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'سبب التعديل *',
                  prefixIcon: Icon(Icons.edit_note, size: 18),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final newAmount = double.tryParse(amountCtrl.text) ?? p.amount;
      if (newAmount <= 0) return;
      final auth   = context.read<AuthService>();
      final editor = auth.currentUser;
      final db     = context.read<DatabaseService>();
      // Build new createdAt from selected date + original time
      final newCreatedAt = editSelectedDate.toIso8601String();
      await db.editPurchaseWithLog(
        oldPurchase: p,
        newPurchase: Purchase(
          id:             p.id,
          uuid:           p.uuid,
          storeManagerId: p.storeManagerId,
          merchantName:   merchantCtrl.text.trim().isEmpty ? p.merchantName : merchantCtrl.text.trim(),
          amount:         newAmount,
          paymentSource:  p.paymentSource,
          paymentMethodId: p.paymentMethodId,
          notes:          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          version:        p.version,
          createdAt:      newCreatedAt,
          isSynced:       0,
        ),
        reason:     reasonCtrl.text.trim(),
        editorName: editor?.name ?? 'غير معروف',
        editorId:   editor?.id ?? 0,
      );
      db.logActivity(
        targetId: p.id!,
        targetType: 'PURCHASE',
        action: 'UPDATE',
        summary: 'تعديل مشتريات ${p.merchantName}: المبلغ من ${p.amount.toStringAsFixed(2)} إلى ${newAmount.toStringAsFixed(2)} ₪ - السبب: ${reasonCtrl.text.trim()}',
        reason: reasonCtrl.text.trim(),
        performedById: editor?.id,
        performedByName: editor?.name,
        storeManagerId: editor?.parentId ?? editor?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      await _loadData();
      _snack('تم تعديل الفاتورة بنجاح', Colors.blue);
    }
  }

  // ── Edit history dialog ──────────────────────────────────────────────────

  Future<void> _showHistoryDialog(Purchase p) async {
    final db      = context.read<DatabaseService>();
    final history = await db.getPurchaseEditHistory(p.id!);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سجل تعديلات: ${p.merchantName}'),
        content: SizedBox(
          width: 400,
          child: history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد تعديلات مسجلة'),
                )
              : Builder(builder: (_) {
                    // Filter out null→null entries (no meaningful change)
                    final filtered = history.where((h) {
                      final oldVal = h['old_value'] as String?;
                      final newVal = h['new_value'] as String?;
                      return !(oldVal == null && newVal == null);
                    }).toList();
                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد تعديلات مسجلة'),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final h = filtered[i];
                        final fieldName = h['field_name'] as String? ?? '';
                        final fieldLabel = _fieldLabel(fieldName);
                        final rawOld = h['old_value'] as String?;
                        final rawNew = h['new_value'] as String?;
                        // Format ISO date strings to readable format
                        final displayOld = _formatHistoryValue(fieldName, rawOld);
                        final displayNew = _formatHistoryValue(fieldName, rawNew);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.edit, size: 14, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(fieldLabel,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ]),
                              const SizedBox(height: 2),
                              Text('من: $displayOld  →  إلى: $displayNew',
                                  style: const TextStyle(fontSize: 12)),
                              Text('السبب: ${h['edit_reason'] ?? '-'}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('بواسطة: ${h['edited_by_name'] ?? '-'}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                DateFormat('yyyy/MM/dd HH:mm').format(
                                    DateTime.tryParse(h['created_at'] as String? ?? '') ?? DateTime.now()),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'amount':        return 'المبلغ';
      case 'merchant_name': return 'اسم المورد';
      case 'notes':         return 'الملاحظات';
      case 'created_at':    return 'تاريخ الفاتورة';
      case 'payment_method_id': return 'طريقة الدفع';
      default:              return field.isEmpty ? 'تعديل عام' : field;
    }
  }

  /// Formats a raw history value — if it looks like an ISO date, convert to readable format.
  String _formatHistoryValue(String fieldName, String? raw) {
    if (raw == null || raw == 'null') return '-';
    if (fieldName == 'created_at') {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return DateFormat('yyyy/MM/dd').format(dt);
    }
    return raw;
  }

  // ── Recycle bin dialog ───────────────────────────────────────────────────

  Future<void> _showRecycleBin() async {
    final db      = context.read<DatabaseService>();
    var deleted = await db.getDeletedPurchases();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.delete_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('سلة المحذوفات'),
          ]),
          content: SizedBox(
            width: 460,
            child: deleted.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('سلة المحذوفات فارغة'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: deleted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = deleted[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.merchantName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '${p.amount.toStringAsFixed(2)} ₪  •  ${DateFormat('yyyy/MM/dd').format(DateTime.tryParse(p.createdAt) ?? DateTime.now())}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('استعادة', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            await db.restorePurchase(p.id!);
                            final refreshed = await db.getDeletedPurchases();
                            setS(() => deleted = refreshed);
                            await _loadData();
                            _snack('تمت استعادة الفاتورة', Colors.green);
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  // ── Snackbar helper ──────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final size    = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      body: _isInitialLoading
          ? ShimmerLoading(isDark: isDark, itemCount: 5)
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTopBar(isMobile, isDark),
                        const SizedBox(height: 16),
                        _buildSummaryRow(isDark),
                        const SizedBox(height: 16),
                        _buildPurchaseForm(isMobile, isDark),
                        const SizedBox(height: 24),
                        if (_purchaseMethods.isEmpty)
                          _buildEmptyState(isDark)
                        else
                          ..._purchaseMethods.map((method) {
                            final items = _groupedPurchases[method.id] ?? [];
                            final color = _methodColor(method);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: _buildSection(method, items, color, isDark),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                _buildTotalFooter(isMobile, isDark),
              ],
            ),
    );
  }

  // ── Top bar: filter tabs + recycle bin ───────────────────────────────────

  Widget _buildTopBar(bool isMobile, bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildFilterBar(isDark)),
        const SizedBox(width: 8),
        _buildRecycleBinButton(isDark),
      ],
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(child: _filterBtn('اليوم', 'today', isDark)),
          Expanded(child: _filterBtn('أسبوع', 'week', isDark)),
          Expanded(child: _filterBtn('شهر', 'month', isDark)),
          Expanded(child: _filterBtn('تاريخ', 'custom', isDark, icon: Icons.calendar_today)),
        ],
      ),
    );
  }

  Widget _filterBtn(String label, String value, bool isDark, {IconData? icon}) {
    final active = _activeFilter == value;
    return GestureDetector(
      onTap: () => value == 'custom' ? _selectCustomRange() : _setFilter(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.orange[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13,
                  color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRecycleBinButton(bool isDark) {
    return Tooltip(
      message: 'سلة المحذوفات',
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PurchasesRecycleBinScreen(),
          ),
        ).then((_) => _loadData()),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Icon(Icons.delete_outline_rounded,
              size: 20, color: Colors.redAccent.withOpacity(0.8)),
        ),
      ),
    );
  }

  // ── Summary row ──────────────────────────────────────────────────────────

  Widget _buildSummaryRow(bool isDark) {
    if (_purchaseMethods.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _purchaseMethods.map((m) {
          final sum   = (_groupedPurchases[m.id] ?? []).fold(0.0, (s, p) => s + p.amount);
          final color = _methodColor(m);
          return Container(
            margin: const EdgeInsets.only(left: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25)),
              boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 6)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54)),
                const SizedBox(height: 2),
                Text('${sum.toStringAsFixed(2)} ₪',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Purchase form ────────────────────────────────────────────────────────

  Widget _buildPurchaseForm(bool isMobile, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة فاتورة مشتريات',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 12),
          if (isMobile) ...([
            _buildInput('اسم المورد', _merchantController, Icons.business, isDark),
            const SizedBox(height: 10),
            _buildInput('المبلغ', _amountController, Icons.payments, isDark, isNumeric: true),
            const SizedBox(height: 10),
            _buildDatePicker(isDark),
            const SizedBox(height: 10),
            _buildMethodDropdown(isDark),
          ])
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildInput('اسم المورد', _merchantController, Icons.business, isDark)),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: _buildInput('المبلغ', _amountController, Icons.payments, isDark, isNumeric: true)),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: _buildDatePicker(isDark)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _buildMethodDropdown(isDark)),
              ],
            ),
          const SizedBox(height: 10),
          _buildInput('ملاحظات (اختياري)', _notesController, Icons.note_outlined, isDark),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _isLoading ? 'جاري الحفظ...' : 'تسجيل المشتريات',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, bool isDark,
      {bool isNumeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: isNumeric ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2101),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.light(primary: Colors.orange[800]!),
            ),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _selectedDate = picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'التاريخ',
          labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
          prefixIcon: const Icon(Icons.calendar_today, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        child: Text(
          DateFormat('yyyy/MM/dd').format(_selectedDate),
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
        ),
      ),
    );
  }

  Widget _buildMethodDropdown(bool isDark) {
    return DropdownButtonFormField<PaymentMethod>(
      value: _selectedMethod,
      isExpanded: true,
      icon: const Icon(Icons.arrow_drop_down, size: 20),
      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo'),
      items: _purchaseMethods.map((m) =>
          DropdownMenuItem(value: m, child: Text(m.name, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (val) => setState(() => _selectedMethod = val),
      decoration: InputDecoration(
        labelText: 'وسيلة الدفع',
        labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
        prefixIcon: const Icon(Icons.account_balance_wallet, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
    );
  }

  // ── Section ──────────────────────────────────────────────────────────────

  Widget _buildSection(PaymentMethod method, List<Purchase> items, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: Text('مشتريات ${method.name}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text('لا توجد مشتريات للفترة المختارة',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.grey)),
          )
        else
          ...items.map((p) => _buildPurchaseCard(p, color, isDark)),
      ],
    );
  }

  Widget _buildPurchaseCard(Purchase p, Color color, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final isEdited = p.version > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.merchantName,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.access_time, size: 11, color: isDark ? Colors.white30 : Colors.grey),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      DateFormat('yyyy/MM/dd  HH:mm').format(
                          DateTime.tryParse(p.createdAt) ?? DateTime.now()),
                      style: TextStyle(
                          fontSize: 11, color: isDark ? Colors.white30 : Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                if (p.notes != null && p.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(p.notes!,
                      style: TextStyle(
                          fontSize: 11, color: isDark ? Colors.white38 : Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right: amount + action buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${p.amount.toStringAsFixed(2)} ₪',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16, color: color)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // History button — only if edited
                  if (isEdited)
                    _iconBtn(
                      icon: Icons.history_rounded,
                      color: Colors.purple,
                      tooltip: 'سجل التعديلات',
                      onTap: () => _showHistoryDialog(p),
                    ),
                  if (isEdited) const SizedBox(width: 4),
                  // Edit button
                  _iconBtn(
                    icon: Icons.edit_outlined,
                    color: color,
                    tooltip: 'تعديل',
                    onTap: () => _showEditDialog(p),
                  ),
                  const SizedBox(width: 4),
                  // Delete button
                  _iconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    tooltip: 'حذف',
                    onTap: () => _deletePurchase(p),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 17, color: color.withOpacity(0.8)),
        ),
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(children: [
        Icon(Icons.account_balance_wallet_outlined,
            size: 48, color: isDark ? Colors.white24 : Colors.grey),
        const SizedBox(height: 12),
        Text('يرجى تعريف "طرق دفع المشتريات" أولاً من الإعدادات',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600])),
      ]),
    );
  }

  // ── Total footer ─────────────────────────────────────────────────────────

  Widget _buildTotalFooter(bool isMobile, bool isDark) {
    final fmt = DateFormat('yyyy/MM/dd');
    String dateRange = fmt.format(_startDate);
    if (_startDate.day != _endDate.day || _startDate.month != _endDate.month) {
      dateRange += ' - ${fmt.format(_endDate)}';
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
            top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -3))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('إجمالي المشتريات',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF64748B))),
            Text(dateRange,
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white30 : Colors.grey)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange[800]!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange[800]!.withOpacity(0.3)),
            ),
            child: Text('${_totalPurchases.toStringAsFixed(2)} ₪',
                style: TextStyle(
                    fontSize: isMobile ? 18 : 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange[800])),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Color _methodColor(PaymentMethod m) {
    if (m.type == 'cash') return Colors.green;
    if (m.name.contains('حمودة')) return Colors.orange;
    return Colors.blue;
  }
}
