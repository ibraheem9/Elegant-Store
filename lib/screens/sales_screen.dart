import 'package:flutter/material.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sales', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Create Invoice')),
          const SizedBox(height: 24),
          const Text('Today Invoices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (context, index) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text('Invoice #${1000 + index}'),
                subtitle: const Text('Customer: Hassan'),
                trailing: const Text('100 ₪'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
