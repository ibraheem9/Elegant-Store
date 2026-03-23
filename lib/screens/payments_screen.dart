import 'package:flutter/material.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payments', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text('Pending Invoices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            itemBuilder: (context, index) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text('Invoice #${2000 + index}'),
                subtitle: const Text('Customer: Hassan'),
                trailing: ElevatedButton(onPressed: () {}, child: const Text('Pay')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
