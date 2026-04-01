import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class PurchasesMethodsScreen extends StatefulWidget {
  const PurchasesMethodsScreen({Key? key}) : super(key: key);

  @override
  State<PurchasesMethodsScreen> createState() => _PurchasesMethodsScreenState();
}

class _PurchasesMethodsScreenState extends State<PurchasesMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = 'cash';

  final List<Map<String, String>> _types = [
    {'value': 'cash', 'label': 'كاش (نقدي)'},
    {'value': 'app', 'label': 'تطبيق إلكتروني'},
  ];

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMethodDialog(),
        label: const Text('إضافة وسيلة دفع للمشتريات'),
        icon: const Icon(Icons.add_business_rounded),
        backgroundColor: Colors.orange[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'طرق دفع المشتريات',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            const Text(
              'إدارة الوسائل المستخدمة لدفع مستحقات الموردين والمصروفات العامة',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: FutureBuilder<List<PaymentMethod>>(
                future: db.getPaymentMethods(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  // For purchases, we typically only use 'cash' and 'app' types
                  final allMethods = snapshot.data ?? [];
                  final purchaseMethods = allMethods.where((m) => m.type == 'cash' || m.type == 'app').toList();

                  if (purchaseMethods.isEmpty) {
                    return const Center(child: Text('لا يوجد طرق دفع مشتريات مسجلة'));
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 400,
                      mainAxisExtent: 180,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: purchaseMethods.length,
                    itemBuilder: (context, index) {
                      final method = purchaseMethods[index];
                      return _buildMethodCard(method);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodCard(PaymentMethod method) {
    IconData icon;
    Color color;

    if (method.type == 'cash') {
      icon = Icons.money_rounded;
      color = Colors.green;
    } else {
      icon = Icons.smartphone_rounded;
      color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF64748B)),
                onPressed: () => _showMethodDialog(method: method),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                onPressed: () => _confirmDelete(method),
              ),
            ],
          ),
          const Spacer(),
          Text(
            method.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            method.type == 'cash' ? 'كاش (نقدي)' : 'تطبيق إلكتروني',
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
          ),
          if (method.description != null && method.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              method.description!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  void _showMethodDialog({PaymentMethod? method}) {
    if (method != null) {
      _nameController.text = method.name;
      _descController.text = method.description ?? '';
      _selectedType = method.type;
    } else {
      _nameController.clear();
      _descController.clear();
      _selectedType = 'cash';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(method == null ? 'إضافة وسيلة دفع للمشتريات' : 'تعديل وسيلة الدفع'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم الوسيلة (مثلاً: كاش، تطبيق إبراهيم، ...)'),
                    validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(labelText: 'نوع الوسيلة'),
                    items: _types.map((t) => DropdownMenuItem(value: t['value'], child: Text(t['label']!))).toList(),
                    onChanged: (v) => setDialogState(() => _selectedType = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final db = context.read<DatabaseService>();
                  final newMethod = PaymentMethod(
                    id: method?.id,
                    name: _nameController.text,
                    type: _selectedType,
                    description: _descController.text,
                    isActive: method?.isActive ?? 1,
                  );

                  if (method == null) {
                    await db.insertPaymentMethod(newMethod);
                  } else {
                    await db.updatePaymentMethod(newMethod);
                  }
                  
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(PaymentMethod method) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "${method.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await context.read<DatabaseService>().deletePaymentMethod(method.id!);
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
