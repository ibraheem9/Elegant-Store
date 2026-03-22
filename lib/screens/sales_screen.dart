import 'package:flutter/material.dart';
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
  User? _selectedCustomer;
  PaymentMethod? _selectedPaymentMethod;
  List<Invoice> _todayInvoices = [];

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  void _loadInvoices() async {
    final dbService = context.read<DatabaseService>();
    final invoices = await dbService.getTodayInvoices();
    setState(() {
      _todayInvoices = invoices;
    });
  }

  void _saveInvoice() async {
    if (_selectedCustomer == null || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final dbService = context.read<DatabaseService>();
    final invoice = Invoice(
      userId: _selectedCustomer!.id!,
      invoiceDate: DateTime.now().toIso8601String(),
      amount: double.parse(_amountController.text),
      notes: _notesController.text,
      paymentStatus: 'pending',
      paymentMethodId: _selectedPaymentMethod?.id,
      createdAt: DateTime.now().toIso8601String(),
    );

    await dbService.insertInvoice(invoice);

    _amountController.clear();
    _notesController.clear();
    setState(() {
      _selectedCustomer = null;
      _selectedPaymentMethod = null;
    });

    _loadInvoices();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice created successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = context.read<DatabaseService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Create invoice form
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Invoice',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Customer selection
                const Text('Customer'),
                const SizedBox(height: 8),
                FutureBuilder<List<User>>(
                  future: dbService.getCustomers(),
                  builder: (context, snapshot) {
                    final customers = snapshot.data ?? [];
                    return DropdownButton<User>(
                      isExpanded: true,
                      value: _selectedCustomer,
                      hint: const Text('Select customer'),
                      items: customers
                          .map((customer) => DropdownMenuItem(
                                value: customer,
                                child: Text(customer.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCustomer = value;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Amount
                const Text('Amount (₪)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Payment method
                const Text('Payment Method'),
                const SizedBox(height: 8),
                FutureBuilder<List<PaymentMethod>>(
                  future: dbService.getPaymentMethods(),
                  builder: (context, snapshot) {
                    final methods = snapshot.data ?? [];
                    return DropdownButton<PaymentMethod>(
                      isExpanded: true,
                      value: _selectedPaymentMethod,
                      hint: const Text('Select payment method'),
                      items: methods
                          .map((method) => DropdownMenuItem(
                                value: method,
                                child: Text(method.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMethod = value;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Notes
                const Text('Notes'),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter notes',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveInvoice,
                    child: const Text('Save Invoice'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Today's invoices
          const Text(
            'Today\'s Invoices',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          if (_todayInvoices.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No invoices today'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _todayInvoices.length,
              itemBuilder: (context, index) {
                final invoice = _todayInvoices[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invoice #${invoice.id}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₪${invoice.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: invoice.paymentStatus == 'paid'
                              ? Colors.green[100]
                              : Colors.orange[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          invoice.paymentStatus.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: invoice.paymentStatus == 'paid'
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
