import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = 'cash';
  bool _isReordering = false;
  List<PaymentMethod> _methods = [];

  final List<Map<String, String>> _types = [
    {'value': 'cash', 'label': 'كاش (نقدي)'},
    {'value': 'app', 'label': 'تطبيق إلكتروني'},
    {'value': 'deferred', 'label': 'أجل (دين)'},
    {'value': 'credit_balance', 'label': 'رصيد المحفظة'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshMethods();
  }

  Future<void> _refreshMethods() async {
    final db = context.read<DatabaseService>();
    final m = await db.getPaymentMethods();
    setState(() {
      _methods = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isReordering)
            FloatingActionButton.extended(
              heroTag: 'addBtn',
              onPressed: () => _showMethodDialog(),
              label: const Text('إضافة طريقة دفع'),
              icon: const Icon(Icons.add_rounded),
              backgroundColor: Colors.blue[700],
            ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'reorderBtn',
            onPressed: () async {
              if (_isReordering) {
                await context.read<DatabaseService>().updatePaymentMethodsOrder(_methods);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الترتيب الجديد')));
              }
              setState(() => _isReordering = !_isReordering);
            },
            label: Text(_isReordering ? 'حفظ الترتيب' : 'تغيير الترتيب'),
            icon: Icon(_isReordering ? Icons.check_rounded : Icons.reorder_rounded),
            backgroundColor: _isReordering ? Colors.green[700] : Colors.blueGrey[700],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'إدارة طرق الدفع',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const Spacer(),
                if (_isReordering)
                  const Text(
                    'قم بسحب العناصر لترتيبها',
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك إضافة أو تعديل طرق الدفع المتاحة عند تسجيل الفواتير وترتيبها لتظهر في شاشة البيع بالشكل المطلوب',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _isReordering ? _buildReorderableList() : _buildMethodsGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodsGrid() {
    if (_methods.isEmpty) {
      return const Center(child: Text('لا يوجد طرق دفع مسجلة'));
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 180,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _methods.length,
      itemBuilder: (context, index) {
        final method = _methods[index];
        return _buildMethodCard(method);
      },
    );
  }

  Widget _buildReorderableList() {
    return Theme(
      data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
      child: ReorderableListView(
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _methods.removeAt(oldIndex);
            _methods.insert(newIndex, item);
          });
        },
        children: [
          for (final method in _methods)
            Card(
              key: ValueKey(method.id),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.drag_indicator_rounded, color: Colors.grey),
                title: Text(method.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_types.firstWhere((t) => t['value'] == method.type)['label'] ?? method.type),
                trailing: const Icon(Icons.reorder_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(PaymentMethod method) {
    IconData icon;
    Color color;

    switch (method.type) {
      case 'cash':
        icon = Icons.money_rounded;
        color = Colors.green;
        break;
      case 'app':
        icon = Icons.smartphone_rounded;
        color = Colors.blue;
        break;
      case 'deferred':
        icon = Icons.timer_outlined;
        color = Colors.orange;
        break;
      case 'credit_balance':
        icon = Icons.account_balance_wallet_rounded;
        color = Colors.purple;
        break;
      default:
        icon = Icons.payment_rounded;
        color = Colors.grey;
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
            _types.firstWhere((t) => t['value'] == method.type)['label'] ?? method.type,
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
          title: Text(method == null ? 'إضافة طريقة دفع جديدة' : 'تعديل طريقة الدفع'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم الطريقة (مثلاً: كاش، بنك فلسطين، ...)'),
                    validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(labelText: 'نوع العملية'),
                    items: _types.map((t) => DropdownMenuItem(value: t['value'], child: Text(t['label']!))).toList(),
                    onChanged: (v) => setDialogState(() => _selectedType = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: 'وصف إضافي (اختياري)'),
                    maxLines: 2,
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
                    sortOrder: method?.sortOrder ?? 0,
                  );

                  if (method == null) {
                    await db.insertPaymentMethod(newMethod);
                  } else {
                    await db.updatePaymentMethod(newMethod);
                  }
                  
                  if (mounted) {
                    Navigator.pop(context);
                    _refreshMethods();
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
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
        content: Text('هل أنت متأكد من حذف "${method.name}"؟ ستبقى البيانات القديمة محفوظة ولكن لن تظهر هذه الطريقة في الفواتير الجديدة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await context.read<DatabaseService>().deletePaymentMethod(method.id!);
              if (mounted) {
                Navigator.pop(context);
                _refreshMethods();
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
