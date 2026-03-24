import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({Key? key}) : super(key: key);

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<User> _customers = [];
  List<User> _filteredCustomers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    setState(() {
      _customers = customers;
      _filteredCustomers = customers;
      _isLoading = false;
    });
  }

  void _filterCustomers(String query) {
    setState(() {
      _filteredCustomers = _customers
          .where((c) => c.name.toLowerCase().contains(query.toLowerCase()) || c.username.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'البحث عن زبون...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterCustomers,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = _filteredCustomers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(customer.name.isNotEmpty ? customer.name[0] : '')),
                          title: Text(customer.name),
                          subtitle: FutureBuilder<double>(
                            future: context.read<DatabaseService>().getCustomerDebt(customer.id!),
                            builder: (context, snapshot) {
                              final debt = snapshot.data ?? 0;
                              return Text(
                                'إجمالي الدين: ${debt.toStringAsFixed(2)} ₪',
                                style: TextStyle(
                                  color: debt > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showEditCustomerDialog(customer),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomerDialog,
        child: const Icon(Icons.add),
        tooltip: 'إضافة زبون جديد',
      ),
    );
  }

  void _showAddCustomerDialog() {
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    bool isPermanent = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة زبون جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('زبون دائم'),
                value: isPermanent,
                onChanged: (val) => setState(() => isPermanent = val!),
              ),
              if (isPermanent)
                TextField(
                  controller: limitController,
                  decoration: const InputDecoration(labelText: 'سقف الدين'),
                  keyboardType: TextInputType.number,
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                final db = context.read<DatabaseService>();
                final newUser = User(
                  username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
                  email: 'cust_${DateTime.now().millisecondsSinceEpoch}@store.com',
                  name: nameController.text,
                  role: 'customer',
                  isPermanentCustomer: isPermanent ? 1 : 0,
                  creditLimit: isPermanent ? double.tryParse(limitController.text) : null,
                  createdAt: DateTime.now().toIso8601String(),
                );
                await db.insertUser(newUser, '123');
                Navigator.pop(context);
                _loadCustomers();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCustomerDialog(User customer) {
    final nameController = TextEditingController(text: customer.name);
    final limitController = TextEditingController(text: customer.creditLimit?.toString() ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل بيانات الزبون'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 16),
            if (customer.isPermanentCustomer == 1)
              TextField(
                controller: limitController,
                decoration: const InputDecoration(labelText: 'سقف الدين'),
                keyboardType: TextInputType.number,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              final db = context.read<DatabaseService>();
              final updatedUser = User(
                id: customer.id,
                username: customer.username,
                email: customer.email,
                name: nameController.text,
                role: customer.role,
                isPermanentCustomer: customer.isPermanentCustomer,
                creditLimit: double.tryParse(limitController.text),
                createdAt: customer.createdAt,
              );
              await db.updateUser(updatedUser);
              Navigator.pop(context);
              _loadCustomers();
            },
            child: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    );
  }
}
