import 'package:flutter/material.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Purchases', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Add Purchase')),
          const SizedBox(height: 24),
          const Text('Today Purchases', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 2,
            itemBuilder: (context, index) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text('Supplier: Company ${index + 1}'),
                subtitle: const Text('Date: Today'),
                trailing: const Text('200 ₪'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
