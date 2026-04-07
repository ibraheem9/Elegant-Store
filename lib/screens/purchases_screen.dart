import 'package:flutter/material.dart';
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
  bool _isLoading = false;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final db = context.read<DatabaseService>();
    try {
      // جلب طرق الدفع الخاصة بالمشتريات فقط
      final methods = await db.getPaymentMethods(category: 'PURCHASE');
      
      Map<int, List<Purchase>> grouped = {};
      for (var m in methods) {
        grouped[m.id!] = await db.getPurchasesByMethod(m.id!);
      }

      setState(() {
        _purchaseMethods = methods;
        _groupedPurchases = grouped;

        if (_purchaseMethods.isNotEmpty && _selectedMethod == null) {
          _selectedMethod = _purchaseMethods.first;
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

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      body: _isInitialLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إدارة المشتريات', 
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(height: 32),
                _buildPurchaseForm(theme, isDark),
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
                      child: _buildSection('مشتريات ${method.name}', items, color, isDark),
                    );
                  }).toList(),
              ],
            ),
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
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildPurchaseForm(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة فاتورة مشتريات جديدة', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildInput('اسم المورد', _merchantController, Icons.business, isDark, fontSize: 18)),
              const SizedBox(width: 20),
              Expanded(child: _buildInput('المبلغ', _amountController, Icons.payments, isDark, isNumeric: true, fontSize: 18)),
              const SizedBox(width: 20),
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  value: _selectedMethod,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  items: _purchaseMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 18)))).toList(),
                  onChanged: (val) => setState(() => _selectedMethod = val),
                  decoration: InputDecoration(
                    labelText: 'وسيلة الدفع', 
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                    prefixIcon: const Icon(Icons.account_balance_wallet)
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInput('ملاحظات', _notesController, Icons.note, isDark, fontSize: 18),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800], 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              child: Text(_isLoading ? 'جاري الحفظ...' : 'تسجيل المشتريات', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, IconData icon, bool isDark, {bool isNumeric = false, double fontSize = 16}) {
    return TextField(
      controller: controller,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontSize: fontSize, color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label, 
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        prefixIcon: Icon(icon)
      ),
    );
  }

  Widget _buildSection(String title, List<Purchase> items, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(padding: const EdgeInsets.all(16), 
            child: Text('لا توجد مشتريات اليوم لهذه الفئة', 
              style: TextStyle(fontSize: 16, color: isDark ? Colors.white30 : Colors.grey)))
        else
          ...items.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white, 
              borderRadius: BorderRadius.circular(16), 
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
            ),
            child: Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.merchantName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: isDark ? Colors.white : Colors.black)),
                  if (p.notes != null && p.notes!.isNotEmpty) 
                    Text(p.notes!, style: TextStyle(fontSize: 16, color: isDark ? Colors.white30 : Colors.grey)),
                ])),
                Text('${p.amount.toStringAsFixed(2)} ₪', 
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: color)),
              ],
            ),
          )).toList(),
      ],
    );
  }
}
