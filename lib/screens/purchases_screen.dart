'''import 'package:flutter/material.dart';
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
  final _supplierController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  
  List<PaymentMethod> _appMethods = [];
  PaymentMethod? _selectedMethod;
  List<Purchase> _todayPurchases = [];
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
    final purchases = await db.getTodayPurchases();
    setState(() {
      _appMethods = methods.where((m) => m.type == 'app' || m.type == 'cash').toList();
      _todayPurchases = purchases;
      if (_appMethods.isNotEmpty) _selectedMethod = _appMethods.first;
    });
  }

  Future<void> _addPurchase() async {
    if (_supplierController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال اسم التاجر والمبلغ')));
      return;
    }

    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final now = DateTime.now();
    final purchaseDate = DateFormat('dd-MM-yyyy').format(now);

    final purchase = Purchase(
      supplier: _supplierController.text,
      amount: double.parse(_amountController.text),
      paymentMethodId: _selectedMethod?.id,
      purchaseDate: purchaseDate,
      notes: _notesController.text,
      createdAt: now.toIso8601String(),
    );

    await db.insertPurchase(purchase);
    _supplierController.clear();
    _amountController.clear();
    _notesController.clear();
    await _loadData();
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المشتريات بنجاح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مشتريات اليوم', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _supplierController,
                      decoration: const InputDecoration(labelText: 'اسم التاجر'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'المبلغ (شيكل)', prefixText: '₪ '),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaymentMethod>(
                      value: _selectedMethod,
                      decoration: const InputDecoration(labelText: 'طريقة الدفع (تطبيق/كاش)'),
                      items: _appMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                      onChanged: (val) => setState(() => _selectedMethod = val),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _addPurchase,
                        child: _isLoading ? const CircularProgressIndicator() : const Text('إضافة مشتريات'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('سجل مشتريات اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _todayPurchases.length,
              itemBuilder: (context, index) {
                final p = _todayPurchases[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${p.supplier} - ${p.amount} ₪'),
                    subtitle: Text('التاريخ: ${p.purchaseDate}\nملاحظات: ${p.notes ?? '-'}'),
                    trailing: const Icon(Icons.shopping_bag),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}'''
