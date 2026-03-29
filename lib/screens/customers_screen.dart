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
          .where((c) =>
            c.name.toLowerCase().contains(query.toLowerCase()) ||
            (c.phone != null && c.phone!.contains(query)) ||
            (c.notes != null && c.notes!.toLowerCase().contains(query.toLowerCase())))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmall = size.width < 700;
    final bool isLarge = size.width > 1200;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(isSmall ? 16 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isSmall),
                const SizedBox(height: 24),
                _buildSearchBar(),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                  ? _buildEmptyState()
                  : _buildCustomerGrid(isSmall, isLarge),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerDialog,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
        label: const Text('إضافة زبون', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildHeader(bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('إدارة الزبائن', style: TextStyle(fontSize: isSmall ? 24 : 32, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
        const SizedBox(height: 4),
        Text('تتبع الديون، الرصيد المودع، وبيانات التواصل', style: TextStyle(color: const Color(0xFF64748B), fontSize: isSmall ? 13 : 15)),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: TextField(
        onChanged: _filterCustomers,
        decoration: const InputDecoration(
          hintText: 'بحث بالاسم أو الهاتف...',
          prefixIcon: Icon(Icons.search_rounded, color: Colors.blue),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildCustomerGrid(bool isSmall, bool isLarge) {
    int crossAxisCount = isSmall ? 1 : (isLarge ? 3 : 2);

    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 32, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 120,
      ),
      itemCount: _filteredCustomers.length,
      itemBuilder: (context, index) {
        final customer = _filteredCustomers[index];
        return _buildCustomerCard(customer);
      },
    );
  }

  Widget _buildCustomerCard(User customer) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () => _navigateToCustomerDetails(customer),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: customer.isPermanentCustomer == 1 ? Colors.blue[50] : Colors.grey[50],
                child: Text(customer.name[0], style: TextStyle(color: customer.isPermanentCustomer == 1 ? Colors.blue : Colors.grey, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text(customer.phone ?? 'لا يوجد هاتف', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              FutureBuilder<double>(
                future: context.read<DatabaseService>().getCustomerDebt(customer.id!),
                builder: (context, snapshot) {
                  final debt = snapshot.data ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${debt.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: debt > 0 ? Colors.redAccent : Colors.green)),
                      Text(debt > 0 ? 'دين' : 'خالص', style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('لا يوجد نتائج تطابق بحثك', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _navigateToCustomerDetails(User customer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CustomerDetailsScreen(customer: customer)),
    ).then((_) => _loadCustomers());
  }

  void _showAddCustomerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final limitController = TextEditingController();
    bool isPermanent = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('إضافة زبون جديد', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogField('الاسم الكامل', nameController, Icons.person_outline),
                  _buildDialogField('رقم الهاتف', phoneController, Icons.phone_android),
                  SwitchListTile(
                    title: const Text('زبون دائم', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: isPermanent,
                    onChanged: (val) => setState(() => isPermanent = val),
                  ),
                  if (isPermanent) _buildDialogField('سقف الدين (₪)', limitController, Icons.speed, isNumeric: true),
                ],
              ),
            ),
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
                  phone: phoneController.text,
                  role: 'customer',
                  isPermanentCustomer: isPermanent ? 1 : 0,
                  creditLimit: isPermanent ? double.tryParse(limitController.text) : null,
                  createdAt: DateTime.now().toIso8601String(),
                );
                await db.insertUser(newUser, '123');
                Navigator.pop(context);
                _loadCustomers();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogField(String label, TextEditingController controller, IconData icon, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: Colors.blue),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class CustomerDetailsScreen extends StatefulWidget {
  final User customer;
  const CustomerDetailsScreen({Key? key, required this.customer}) : super(key: key);

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  List<Invoice> _invoices = [];
  bool _isLoading = true;
  double _totalDebt = 0;
  late User _currentCustomer;

  @override
  void initState() {
    super.initState();
    _currentCustomer = widget.customer;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    // Refresh customer from DB to get latest balance
    final customers = await db.getCustomers();
    final fresh = customers.firstWhere((c) => c.id == _currentCustomer.id);

    final invoices = await db.getCustomerInvoices(fresh.id!);
    final debt = await db.getCustomerDebt(fresh.id!);

    setState(() {
      _currentCustomer = fresh;
      _invoices = invoices;
      _totalDebt = debt;
      _isLoading = false;
    });
  }

  void _showDepositDialog() {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيداع رصيد (Deposit)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (₪)', prefixIcon: Icon(Icons.add_card, color: Colors.green))),
            const SizedBox(height: 16),
            TextField(controller: notesController, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.note_alt_outlined))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (amountController.text.isEmpty) return;
              final db = context.read<DatabaseService>();
              await db.addCredit(_currentCustomer.id!, double.parse(amountController.text), notesController.text);
              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الرصيد بنجاح'), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('تأكيد الإيداع', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAdvanceDebtDialog() {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل دين يدوي (Advance Debt)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (₪)', prefixIcon: Icon(Icons.money_off, color: Colors.red))),
            const SizedBox(height: 16),
            TextField(controller: notesController, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.note_alt_outlined))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (amountController.text.isEmpty) return;
              final db = context.read<DatabaseService>();

              // Create a special "Advance Debt" invoice
              final now = DateTime.now();
              final invoice = Invoice(
                userId: _currentCustomer.id!,
                invoiceDate: '${now.day}-${now.month}-${now.year} يدوي',
                amount: double.parse(amountController.text),
                notes: '[دين يدوي] ${notesController.text}',
                paymentStatus: 'pending',
                createdAt: now.toIso8601String(),
              );
              await db.insertInvoice(invoice);

              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الدين بنجاح'), backgroundColor: Colors.redAccent));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('تأكيد الدين', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isSmall = width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_currentCustomer.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(isSmall ? 16 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryGrid(isSmall),
                const SizedBox(height: 24),
                _buildActionButtons(),
                const SizedBox(height: 40),
                const Text('سجل العمليات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                const SizedBox(height: 16),
                _buildInvoicesList(),
              ],
            ),
          ),
    );
  }

  Widget _buildSummaryGrid(bool isSmall) {
    return GridView.count(
      crossAxisCount: isSmall ? 1 : 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      childAspectRatio: 2.5,
      children: [
        _buildSummaryCard('إجمالي الدين', '${_totalDebt.toStringAsFixed(2)} ₪', Colors.redAccent, Icons.money_off_rounded),
        _buildSummaryCard('الرصيد المتاح', '${_currentCustomer.balance} ₪', Colors.green, Icons.wallet_rounded),
        if (_currentCustomer.creditLimit != null)
          _buildSummaryCard('سقف الدين', '${_currentCustomer.creditLimit} ₪', Colors.orange, Icons.speed_rounded),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showDepositDialog,
            icon: const Icon(Icons.add_card, color: Colors.white),
            label: const Text('إيداع رصيد جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showAdvanceDebtDialog,
            icon: const Icon(Icons.money_off, color: Colors.white),
            label: const Text('تسجيل دين يدوي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoicesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final inv = _invoices[index];
        bool isPaid = inv.paymentStatus == 'paid';
        bool isManualDebt = inv.notes?.contains('[دين يدوي]') ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(
              isPaid ? Icons.check_circle_rounded : (isManualDebt ? Icons.warning_rounded : Icons.schedule_rounded),
              color: isPaid ? Colors.green : (isManualDebt ? Colors.red : Colors.orange)
            ),
            title: Text('${inv.amount.toStringAsFixed(2)} ₪', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            subtitle: Text('التاريخ: ${inv.invoiceDate}\nملاحظات: ${inv.notes ?? "لا يوجد"}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            trailing: !isPaid ? TextButton(
              onPressed: () async {
                // Quick payment logic
                final db = context.read<DatabaseService>();
                final updated = Invoice(
                  id: inv.id,
                  userId: inv.userId,
                  invoiceDate: inv.invoiceDate,
                  amount: inv.amount,
                  notes: inv.notes,
                  paymentStatus: 'paid',
                  paymentMethodId: 1, // Default to cash for quick settling
                  createdAt: inv.createdAt
                );
                await db.updateInvoice(updated);
                _loadData();
              },
              child: const Text('تسديد الآن', style: TextStyle(fontWeight: FontWeight.bold))
            ) : const Icon(Icons.done_all, color: Colors.blue, size: 20),
          ),
        );
      },
    );
  }
}
