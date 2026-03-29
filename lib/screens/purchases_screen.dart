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
  
  List<PaymentMethod> _appMethods = [];
  PaymentMethod? _selectedMethod;
  List<Purchase> _ibraheemPurchases = [];
  List<Purchase> _hamodaPurchases = [];
  List<Purchase> _cashPurchases = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final db = context.read<DatabaseService>();
    final methods = await db.getPaymentMethods();

    final ibraheem = await db.getPurchasesByMethod('تطبيق إبراهيم');
    final hamoda = await db.getPurchasesByMethod('تطبيق حمودة');

    final allToday = await db.getTodayPurchases();
    final cash = allToday.where((p) => p.paymentSource == 'CASH').toList();

    setState(() {
      _appMethods = methods.where((m) =>
        m.name == 'تطبيق إبراهيم' || m.name == 'تطبيق حمودة' || m.name == 'كاش'
      ).toList();

      _ibraheemPurchases = ibraheem;
      _hamodaPurchases = hamoda;
      _cashPurchases = cash;

      if (_appMethods.isNotEmpty && _selectedMethod == null) {
        _selectedMethod = _appMethods.firstWhere((m) => m.name == 'كاش', orElse: () => _appMethods.first);
      }
    });
  }

  Future<void> _addPurchase() async {
    if (_merchantController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال اسم المورد والمبلغ'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final now = DateTime.now();

    final purchase = Purchase(
      merchantName: _merchantController.text,
      amount: double.parse(_amountController.text),
      paymentSource: _selectedMethod?.type == 'app' ? 'APP' : 'CASH',
      paymentMethodId: _selectedMethod?.id,
      notes: _notesController.text,
      createdAt: now.toIso8601String(),
    );

    await db.insertPurchase(purchase);
    _merchantController.clear();
    _amountController.clear();
    _notesController.clear();
    await _loadData();
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المشتريات بنجاح'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إدارة المشتريات', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 32),
            _buildPurchaseForm(theme),
            const SizedBox(height: 48),
            _buildSection('مشتريات إبراهيم (Ibraheem)', _ibraheemPurchases, Colors.blue),
            const SizedBox(height: 32),
            _buildSection('مشتريات حمودة (Hamoda)', _hamodaPurchases, Colors.orange),
            const SizedBox(height: 32),
            _buildSection('مشتريات كاش (Cash)', _cashPurchases, Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseForm(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('إضافة فاتورة مشتريات جديدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildInput('اسم المورد', _merchantController, Icons.business, fontSize: 18)),
              const SizedBox(width: 20),
              Expanded(child: _buildInput('المبلغ', _amountController, Icons.payments, isNumeric: true, fontSize: 18)),
              const SizedBox(width: 20),
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  value: _selectedMethod,
                  items: _appMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 18)))).toList(),
                  onChanged: (val) => setState(() => _selectedMethod = val),
                  decoration: const InputDecoration(labelText: 'وسيلة الدفع', prefixIcon: Icon(Icons.account_balance_wallet)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInput('ملاحظات', _notesController, Icons.note, fontSize: 18),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addPurchase,
              style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('تسجيل المشتريات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, IconData icon, {bool isNumeric = false, double fontSize = 16}) {
    return TextField(
      controller: controller,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontSize: fontSize),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Widget _buildSection(String title, List<Purchase> items, Color color) {
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
          const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد مشتريات اليوم لهذه الفئة', style: TextStyle(fontSize: 16, color: Colors.grey)))
        else
          ...items.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.merchantName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  if (p.notes != null && p.notes!.isNotEmpty) Text(p.notes!, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                ])),
                Text('${p.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: color)),
              ],
            ),
          )).toList(),
      ],
    );
  }
}
