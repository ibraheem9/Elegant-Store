import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({Key? key}) : super(key: key);

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  
  List<User> _allCustomers = [];
  List<User> _filteredCustomers = [];
  User? _selectedCustomer;
  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedPaymentMethod;
  List<Invoice> _todayInvoices = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    final methods = await db.getPaymentMethods();
    final invoices = await db.getTodayInvoices();
    
    setState(() {
      _allCustomers = customers;
      _paymentMethods = methods;
      _todayInvoices = invoices;
      if (methods.isNotEmpty) _selectedPaymentMethod = methods.first;
    });
  }

  void _filterCustomers(String query) {
    setState(() {
      _filteredCustomers = _allCustomers
          .where((c) => c.name.contains(query) || c.username.contains(query))
          .toList();
    });
  }

  Future<void> _createInvoice() async {
    if (_amountController.text.isEmpty || (_selectedCustomer == null && _customerSearchController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إكمال البيانات')));
      return;
    }

    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    
    // If customer is new, create them
    User customer;
    if (_selectedCustomer != null) {
      customer = _selectedCustomer!;
    } else {
      customer = User(
        username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
        email: 'new_${DateTime.now().millisecondsSinceEpoch}@store.com',
        name: _customerSearchController.text,
        role: 'customer',
        isPermanentCustomer: 0,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await db.insertUser(customer, '123');
      customer = User(
        id: id,
        username: customer.username,
        email: customer.email,
        name: customer.name,
        role: customer.role,
        isPermanentCustomer: 0,
        createdAt: customer.createdAt,
      );
    }

    final now = DateTime.now();
    final invoiceDate = DateFormat('dd-MM-yyyy EEEE', 'ar').format(now);

    final invoice = Invoice(
      userId: customer.id!,
      invoiceDate: invoiceDate,
      amount: double.parse(_amountController.text),
      notes: _notesController.text,
      paymentStatus: _selectedPaymentMethod?.type == 'deferred' ? 'pending' : 'paid',
      paymentMethodId: _selectedPaymentMethod?.id,
      createdAt: now.toIso8601String(),
    );

    await db.insertInvoice(invoice);
    _amountController.clear();
    _notesController.clear();
    _customerSearchController.clear();
    _selectedCustomer = null;
    
    await _loadData();
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الفاتورة بنجاح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(now);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('شاشة البيع الرئيسية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(todayStr, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _customerSearchController,
                      decoration: InputDecoration(
                        labelText: 'اسم المشتري',
                        suffixIcon: _selectedCustomer != null ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _selectedCustomer = null)) : const Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        if (_selectedCustomer == null) _filterCustomers(val);
                      },
                    ),
                    if (_filteredCustomers.isNotEmpty && _selectedCustomer == null)
                      Container(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final c = _filteredCustomers[index];
                            return ListTile(
                              title: Text(c.name),
                              subtitle: FutureBuilder<double>(
                                future: context.read<DatabaseService>().getCustomerDebt(c.id!),
                                builder: (context, snapshot) {
                                  final debt = snapshot.data ?? 0;
                                  return Text('الدين: $debt ₪', style: TextStyle(color: debt > 0 ? Colors.red : Colors.green));
                                },
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedCustomer = c;
                                  _customerSearchController.text = c.name;
                                  _filteredCustomers = [];
                                });
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'المبلغ (شيكل)', prefixText: '₪ '),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaymentMethod>(
                      value: _selectedPaymentMethod,
                      decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                      items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                      onChanged: (val) => setState(() => _selectedPaymentMethod = val),
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
                        onPressed: _isLoading ? null : _createInvoice,
                        child: _isLoading ? const CircularProgressIndicator() : const Text('إضافة فاتورة'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('فواتير اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _todayInvoices.length,
              itemBuilder: (context, index) {
                final inv = _todayInvoices[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('فاتورة بقيمة ${inv.amount} ₪'),
                    subtitle: Text('التاريخ: ${inv.invoiceDate}\nالحالة: ${inv.paymentStatus == "paid" ? "مدفوع" : "أجل"}'),
                    trailing: const Icon(Icons.receipt),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
