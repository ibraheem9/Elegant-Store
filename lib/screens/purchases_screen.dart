import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({Key? key}) : super(key: key);

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  
  List<PaymentMethod> _purchaseMethods = [];
  PaymentMethod? _selectedMethod;
  Map<int, List<Purchase>> _groupedPurchases = {};
  double _totalPurchases = 0.0;
  bool _isLoading = false;
  bool _isInitialLoading = true;

  // Filter state
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _activeFilter = 'today'; // today, week, month, custom

  @override
  void initState() {
    super.initState();
    _setFilter('today');
  }

  void _setFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _activeFilter = filter;
      if (filter == 'today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'week') {
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.orange[800]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _activeFilter = 'custom';
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final db = context.read<DatabaseService>();
    try {
      final methods = await db.getPaymentMethods(category: 'PURCHASE');
      
      Map<int, List<Purchase>> grouped = {};
      double total = 0.0;
      
      for (var m in methods) {
        final purchases = await db.getPurchasesByMethod(m.id!, start: _startDate, end: _endDate);
        grouped[m.id!] = purchases;
        for (var p in purchases) {
          total += p.amount;
        }
      }

      // Deduplicate by id to prevent DropdownButton duplicate-value assertion
      final seen = <int?>{};
      final uniqueMethods = methods.where((m) => seen.add(m.id)).toList();

      setState(() {
        _purchaseMethods = uniqueMethods;
        _groupedPurchases = grouped;
        _totalPurchases = total;
        // Re-match _selectedMethod from the refreshed deduplicated list
        if (_purchaseMethods.isNotEmpty) {
          if (_selectedMethod != null) {
            _selectedMethod = _purchaseMethods.firstWhere(
              (m) => m.id == _selectedMethod!.id,
              orElse: () => _purchaseMethods.first,
            );
          } else {
            _selectedMethod = _purchaseMethods.first;
          }
        }
        _isInitialLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading purchases data: $e');
      setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _addPurchase() async {
    final amount = double.tryParse(_amountController.text);
    if (_merchantController.text.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المورد ومبلغ صحيح'), backgroundColor: Colors.redAccent)
      );
      return;
    }

    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار وسيلة الدفع أولاً'), backgroundColor: Colors.redAccent)
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final now = DateTime.now();

      final purchase = Purchase(
        merchantName: _merchantController.text.trim(),
        amount: amount,
        paymentSource: _selectedMethod?.type == 'app' ? 'APP' : 'CASH',
        paymentMethodId: _selectedMethod?.id,
        notes: _notesController.text.trim(),
        createdAt: now.toIso8601String(),
      );

      await db.insertPurchase(purchase);
      
      _merchantController.clear();
      _amountController.clear();
      _notesController.clear();
      
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة المشتريات بنجاح'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red)
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
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      body: _isInitialLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 16 : 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(isMobile, isDark, size),
                      const SizedBox(height: 32),
                      _buildSummaryGrid(size, isDark),
                      const SizedBox(height: 32),
                      _buildPurchaseForm(theme, isMobile, isDark),
                      const SizedBox(height: 48),
                      if (_purchaseMethods.isEmpty)
                        _buildEmptyState(isDark)
                      else
                        ..._purchaseMethods.map((method) {
                          final items = _groupedPurchases[method.id] ?? [];
                          Color color = method.type == 'cash' ? Colors.green : Colors.blue;
                          if (method.name.contains('حمودة')) color = Colors.orange;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 32),
                            child: _buildSection('مشتريات ${method.name}', items, color, isDark, isMobile),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
              _buildTotalFooter(isMobile, isDark),
            ],
          ),
    );
  }

  Widget _buildHeader(bool isMobile, bool isDark, Size size) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إدارة المشتريات', 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          const SizedBox(height: 16),
          _buildFilterBar(isDark, size),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('إدارة المشتريات', 
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
        _buildFilterBar(isDark, size),
      ],
    );
  }

  Widget _buildFilterBar(bool isDark, Size size) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 450),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
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
    bool active = _activeFilter == value;
    return GestureDetector(
      onTap: () => value == 'custom' ? _selectCustomRange() : _setFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.orange[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54)), const SizedBox(width: 4)],
            Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54), fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(Size size, bool isDark) {
    int crossAxisCount = (size.width > 1200) ? 4 : (size.width > 800 ? 2 : 1);
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 110,
      ),
      itemCount: _purchaseMethods.length,
      itemBuilder: (context, index) => _buildSummaryItem(_purchaseMethods[index], isDark),
    );
  }

  Widget _buildSummaryItem(PaymentMethod m, bool isDark) {
    final items = _groupedPurchases[m.id] ?? [];
    double sum = items.fold(0, (prev, element) => prev + element.amount);
    Color color = m.type == 'cash' ? Colors.green : Colors.blue;
    if (m.name.contains('حمودة')) color = Colors.orange;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(m.name, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('${sum.toStringAsFixed(2)} ₪', 
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTotalFooter(bool isMobile, bool isDark) {
    String dateRange = DateFormat('yyyy/MM/dd').format(_startDate);
    if (_startDate.day != _endDate.day || _startDate.month != _endDate.month) {
      dateRange += ' - ' + DateFormat('yyyy/MM/dd').format(_endDate);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('إجمالي المشتريات:', 
                  style: TextStyle(fontSize: isMobile ? 14 : 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF64748B))),
                Text(dateRange, style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.grey)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange[800]!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[800]!.withOpacity(0.3))
            ),
            child: Text('${_totalPurchases.toStringAsFixed(2)} ₪', 
              style: TextStyle(fontSize: isMobile ? 18 : 28, fontWeight: FontWeight.w900, color: Colors.orange[800])),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey),
          const SizedBox(height: 16),
          Text('يرجى تعريف "طرق دفع المشتريات" أولاً من الإعدادات',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPurchaseForm(ThemeData theme, bool isMobile, bool isDark) {
    final formItems = [
      Expanded(flex: isMobile ? 0 : 2, child: _buildInput('اسم المورد', _merchantController, Icons.business, isDark, fontSize: 16)),
      if (isMobile) const SizedBox(height: 16),
      if (!isMobile) const SizedBox(width: 20),
      Expanded(flex: isMobile ? 0 : 1, child: _buildInput('المبلغ', _amountController, Icons.payments, isDark, isNumeric: true, fontSize: 16)),
      if (isMobile) const SizedBox(height: 16),
      if (!isMobile) const SizedBox(width: 20),
      Expanded(
        flex: isMobile ? 0 : 2,
        child: DropdownButtonFormField<PaymentMethod>(
          value: _selectedMethod,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontFamily: 'Cairo'),
          items: _purchaseMethods.map((m) => DropdownMenuItem(
            value: m, 
            child: Text(m.name, overflow: TextOverflow.ellipsis)
          )).toList(),
          onChanged: (val) => setState(() => _selectedMethod = val),
          decoration: InputDecoration(
            labelText: 'وسيلة الدفع', 
            labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
            prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
          ),
        ),
      ),
    ];

    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة فاتورة مشتريات جديدة', 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 24),
          if (isMobile) ...formItems.map((e) => e is Expanded ? e.child : e).toList() 
          else Row(crossAxisAlignment: CrossAxisAlignment.start, children: formItems),
          const SizedBox(height: 20),
          _buildInput('ملاحظات', _notesController, Icons.note, isDark, fontSize: 16),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800], 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              child: Text(_isLoading ? 'جاري الحفظ...' : 'تسجيل المشتريات', 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, IconData icon, bool isDark, {bool isNumeric = false, double fontSize = 16}) {
    return TextField(
      controller: controller,
      keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      // Prevent letters in numeric fields
      inputFormatters: isNumeric ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
      style: TextStyle(fontSize: fontSize, color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Future<void> _showEditPurchaseDialog(Purchase p) async {
    final amountController = TextEditingController(text: p.amount.toString());
    final merchantController = TextEditingController(text: p.merchantName);
    final notesController = TextEditingController(text: p.notes ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المشتريات'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: merchantController,
              decoration: const InputDecoration(labelText: 'اسم المورد'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'المبلغ الجديد'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (result == true) {
      final newAmount = double.tryParse(amountController.text) ?? p.amount;
      if (newAmount <= 0) return;
      final db = context.read<DatabaseService>();
      await db.updatePurchase(Purchase(
        id: p.id,
        uuid: p.uuid,
        storeManagerId: p.storeManagerId,
        merchantName: merchantController.text.trim().isEmpty ? p.merchantName : merchantController.text.trim(),
        amount: newAmount,
        paymentSource: p.paymentSource,
        paymentMethodId: p.paymentMethodId,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        version: p.version,
        createdAt: p.createdAt,
        isSynced: 0,
      ));
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تعديل المشتريات بنجاح'), backgroundColor: Colors.blue),
        );
      }
    }
  }

  Widget _buildSection(String title, List<Purchase> items, Color color, bool isDark, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('لا توجد مشتريات للفترة المختارة لهذه الفئة',
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white30 : Colors.grey)),
          )
        else
          ...items.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.merchantName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: isDark ? Colors.white30 : Colors.grey),
                          const SizedBox(width: 4),
                          Text(DateFormat('MM/dd HH:mm').format(DateTime.parse(p.createdAt)),
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.grey)),
                        ],
                      ),
                      // Always show notes below on a new line
                      if (p.notes != null && p.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(p.notes!,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p.amount.toStringAsFixed(2)} ₪',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
                    const SizedBox(height: 4),
                    // Edit button
                    InkWell(
                      onTap: () => _showEditPurchaseDialog(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined, size: 18, color: color.withOpacity(0.7)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )).toList(),
      ],
    );
  }
}
