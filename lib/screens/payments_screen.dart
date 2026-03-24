import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<Invoice> _pendingInvoices = [];
  List<PaymentMethod> _appMethods = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final invoices = await db.getTodayInvoices();
    final methods = await db.getPaymentMethods();
    
    setState(() {
      _pendingInvoices = invoices.where((inv) => inv.paymentStatus == 'pending').toList();
      _appMethods = methods.where((m) => m.type == 'app').toList();
      _isLoading = false;
    });
  }

  Future<void> _markAsPaid(Invoice invoice, PaymentMethod method) async {
    final db = context.read<DatabaseService>();
    final now = DateTime.now();
    
    final updatedInvoice = Invoice(
      id: invoice.id,
      userId: invoice.userId,
      invoiceDate: invoice.invoiceDate,
      amount: invoice.amount,
      notes: invoice.notes,
      paymentStatus: 'paid',
      paymentMethodId: method.id,
      createdAt: invoice.createdAt,
      updatedAt: now.toIso8601String(),
      editHistory: '${invoice.editHistory ?? ""}\nتم الدفع عبر ${method.name} في ${now.toIso8601String()}',
    );

    await db.updateInvoice(updatedInvoice);
    _loadData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تأكيد دفع الفاتورة عبر ${method.name}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('مراجعة المدفوعات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('الفواتير المعلقة لليوم (تحتاج لمراجعة البنك)', style: TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pendingInvoices.isEmpty
                    ? const Center(child: Text('لا توجد فواتير معلقة حالياً'))
                    : ListView.builder(
                        itemCount: _pendingInvoices.length,
                        itemBuilder: (context, index) {
                          final inv = _pendingInvoices[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ExpansionTile(
                              title: Text('فاتورة بقيمة ${inv.amount} ₪'),
                              subtitle: Text('التاريخ: ${inv.invoiceDate}'),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text('اختر التطبيق الذي تم استلام الدفعة عليه:'),
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: _appMethods.map((method) {
                                    return ActionChip(
                                      label: Text(method.name),
                                      onPressed: () => _markAsPaid(inv, method),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
