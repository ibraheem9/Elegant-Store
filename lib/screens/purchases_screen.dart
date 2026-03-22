import 'package:flutter/material.dart';
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
  PaymentMethod? _selectedPaymentMethod;
  List<Purchase> _todayPurchases = [];

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  void _loadPurchases() async {
    final dbService = context.read<DatabaseService>();
    final purchases = await dbService.getTodayPurchases();
    setState(() {
      _todayPurchases = purchases;
    });
  }

  void _savePurchase() async {
    if (_supplierController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final dbService = context.read<DatabaseService>();
    final purchase = Purchase(
      supplier: _supplierController.text,
      amount: double.parse(_amountController.text),
      paymentMethodId: _selectedPaymentMethod?.id,
      purchaseDate: DateTime.now().toIso8601String(),
      createdAt: DateTime.now().toIso8601String(),
    );

    await dbService.insertPurchase(purchase);

    _supplierController.clear();
    _amountController.clear();
    setState(() {
      _selectedPaymentMethod = null;
    });

    _loadPurchases();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase recorded successfully')),
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
                  'Record Purchase',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Supplier'),
                const SizedBox(height: 8),
                TextField(
                  controller: _supplierController,
                  decoration: InputDecoration(
                    hintText: 'Enter supplier name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _savePurchase,
                    child: const Text('Save Purchase'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Today\'s Purchases',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_todayPurchases.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No purchases today'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _todayPurchases.length,
              itemBuilder: (context, index) {
                final purchase = _todayPurchases[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        purchase.supplier,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₪${purchase.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
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
    _supplierController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
