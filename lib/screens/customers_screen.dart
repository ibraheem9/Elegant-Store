import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({Key? key}) : super(key: key);

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<User> _customers = [];
  List<User> _filteredCustomers = [];
  bool _isLoading = false;
  bool _isTableView = false; 
  
  int _sortColumnIndex = 0;
  bool _isAscending = true;

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
      _filteredCustomers = List.from(customers);
      _isLoading = false;
      _applySort(); 
    });
  }

  void _applySort() {
    setState(() {
      if (_sortColumnIndex == 0) { 
        _filteredCustomers.sort((a, b) => _isAscending 
          ? a.name.compareTo(b.name) 
          : b.name.compareTo(a.name));
      } else if (_sortColumnIndex == 1) { 
        _filteredCustomers.sort((a, b) => _isAscending 
          ? a.balance.compareTo(b.balance) 
          : b.balance.compareTo(a.balance));
      }
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;
      _applySort();
    });
  }

  void _filterCustomers(String query) {
    final db = context.read<DatabaseService>();
    final searchNormalized = db.normalizeArabic(query);
    
    setState(() {
      _filteredCustomers = _customers
          .where((c) =>
            db.normalizeArabic(c.name).contains(searchNormalized) ||
            (c.nickname != null && db.normalizeArabic(c.nickname!).contains(searchNormalized)) ||
            (c.phone != null && c.phone!.contains(query)) ||
            (c.transferNames != null && db.normalizeArabic(c.transferNames!).contains(searchNormalized)))
          .toList();
      _applySort(); 
    });
  }

  Future<void> _deleteCustomer(User customer) async {
    final db = context.read<DatabaseService>();
    final hasInvoices = await db.hasInvoices(customer.id!);
    if (!mounted) return;

    if (hasInvoices) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('لا يمكن الحذف', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text('الزبون "${customer.name}" لديه فواتير مسجلة. لا يمكن حذفه للحفاظ على الحسابات.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الزبون "${customer.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await db.softDeleteUser(customer.id!);
      _loadCustomers();
    }
  }

  void _showAddOrEditCustomerDialog({User? customer}) {
    final nameController = TextEditingController(text: customer?.name ?? '');
    final nicknameController = TextEditingController(text: customer?.nickname ?? '');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final transferNamesController = TextEditingController(text: customer?.transferNames ?? '');
    final notesController = TextEditingController(text: customer?.notes ?? '');
    
    final limitController = TextEditingController(
      text: customer == null ? '100' : (customer.creditLimit == -1 ? '' : customer.creditLimit?.toString() ?? '100')
    );
    final balanceController = TextEditingController(text: customer?.balance.toString() ?? '0');
    bool isPermanent = customer == null ? true : (customer.isPermanentCustomer == 1);
    bool isUnlimited = customer?.creditLimit == -1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(customer == null ? 'إضافة زبون جديد' : 'تعديل بيانات الزبون', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDialogField('الاسم الكامل', nameController, Icons.person_outline, onChanged: (val) => setDialogState(() {})),
                  _buildDialogField('اللقب', nicknameController, Icons.badge_outlined),
                  _buildDialogField('رقم الهاتف', phoneController, Icons.phone_android),
                  _buildDialogField('أسماء التحويلات', transferNamesController, Icons.swap_horiz_rounded),
                  _buildDialogField('ملاحظات إضافية', notesController, Icons.note_alt_outlined, maxLines: 2, onChanged: (val) => setDialogState(() {})),
                  
                  const Divider(),
                  SwitchListTile(
                    title: const Text('زبون دائم', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: isPermanent,
                    onChanged: (val) => setDialogState(() => isPermanent = val),
                  ),
                  if (isPermanent) ...[
                    CheckboxListTile(
                      title: const Text('دين غير محدود (Verified)', style: TextStyle(fontSize: 14)),
                      value: isUnlimited,
                      activeColor: Colors.blue,
                      onChanged: (val) => setDialogState(() => isUnlimited = val ?? false),
                    ),
                    if (!isUnlimited)
                      _buildDialogField('سقف الدين (₪)', limitController, Icons.speed, isNumeric: true),
                  ],
                  if (customer != null) 
                    _buildDialogField('تصحيح الرصيد الحالي (₪)', balanceController, Icons.account_balance_wallet, isNumeric: true),
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
                double limit = isUnlimited ? -1 : (double.tryParse(limitController.text) ?? 100.0);

                final userData = User(
                  id: customer?.id,
                  username: customer?.username ?? 'cust_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text.trim(),
                  nickname: nicknameController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: 'customer',
                  isPermanentCustomer: isPermanent ? 1 : 0,
                  creditLimit: isPermanent ? limit : 0.0,
                  balance: customer != null ? (double.tryParse(balanceController.text) ?? customer.balance) : 0.0,
                  transferNames: transferNamesController.text.trim(),
                  notes: notesController.text.trim(),
                  createdAt: customer?.createdAt ?? DateTime.now().toIso8601String(),
                );

                if (customer == null) {
                  await db.insertUser(userData, '123');
                } else {
                  await db.updateUser(userData, customer);
                }
                
                if (mounted) {
                  Navigator.pop(context);
                  _loadCustomers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('حفظ البيانات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmall = size.width < 700;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                _buildHeader(isSmall, isDark),
                const SizedBox(height: 24),
                _buildSearchBar(isDark),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                  ? _buildEmptyState(isDark)
                  : _isTableView 
                    ? _buildCustomerTable(size, isDark)
                    : _buildCustomerGrid(size, isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditCustomerDialog(),
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
        label: const Text('إضافة زبون', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildHeader(bool isSmall, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إدارة الزبائن', style: TextStyle(fontSize: isSmall ? 24 : 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text('تتبع الديون، الملاحظات، وأسماء التحويلات', 
                style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B), fontSize: isSmall ? 12 : 15),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _buildViewToggle(isDark),
      ],
    );
  }

  Widget _buildViewToggle(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: Icon(Icons.grid_view_rounded, color: !_isTableView ? Colors.blue : Colors.grey, size: 20), onPressed: () => setState(() => _isTableView = false)),
          IconButton(icon: Icon(Icons.table_rows_rounded, color: _isTableView ? Colors.blue : Colors.grey, size: 20), onPressed: () => setState(() => _isTableView = true)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        onChanged: _filterCustomers,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم، اللقب، أو اسم التحويل...',
          hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[400]),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.blue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildCustomerGrid(Size size, bool isDark) {
    int crossAxisCount = (size.width > 1400) ? 4 : (size.width > 1000 ? 3 : (size.width > 650 ? 2 : 1));
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 175,
      ),
      itemCount: _filteredCustomers.length,
      itemBuilder: (context, index) => _buildCustomerCard(_filteredCustomers[index], isDark),
    );
  }

  Widget _buildCustomerCard(User customer, bool isDark) {
    final bool isVerified = customer.creditLimit == -1;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () => _navigateToCustomerDetails(customer),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: customer.isPermanentCustomer == 1 ? Colors.blue[50] : Colors.grey[50],
                    child: Text(customer.name[0], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(customer.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis)),
                            if (isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, color: Colors.blue, size: 16),
                            ],
                          ],
                        ),
                        if (customer.nickname != null && customer.nickname!.isNotEmpty)
                          Text(customer.nickname!, style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(customer.phone ?? 'بدون هاتف', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                  _buildBalanceInfo(customer),
                ],
              ),
              if (customer.transferNames != null && customer.transferNames!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_horiz, size: 12, color: Colors.blue),
                      const SizedBox(width: 4),
                      Flexible(child: Text('يُحوّل بـ: ${customer.transferNames}', style: const TextStyle(fontSize: 10, color: Colors.blue), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              _buildCardActions(customer, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceInfo(User customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${customer.balance.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: customer.balance < 0 ? Colors.redAccent : Colors.green)),
        Text(customer.balance < 0 ? 'دين' : 'رصيد', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCardActions(User customer, bool isDark) {
    if (!context.read<AuthService>().isManager()) return const SizedBox();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showAddOrEditCustomerDialog(customer: customer),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('تعديل', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(foregroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 8)),
        ),
        TextButton.icon(
          onPressed: () => _deleteCustomer(customer),
          icon: const Icon(Icons.delete_outline, size: 14),
          label: const Text('حذف', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
        ),
      ],
    );
  }

  Widget _buildCustomerTable(Size size, bool isDark) {
    bool isCompact = size.width < 1000;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical, // Added vertical scrolling
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          constraints: BoxConstraints(minWidth: size.width - 64),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          child: DataTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _isAscending,
            columnSpacing: isCompact ? 12 : 24,
            horizontalMargin: 16,
            headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF1E293B) : Colors.grey[50]),
            columns: [
              DataColumn(
                label: const Text('معلومات الزبون', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: _onSort,
              ),
              DataColumn(
                label: const Text('الحساب', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: _onSort,
              ),
              const DataColumn(label: Text('الإجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _filteredCustomers.map((c) => DataRow(cells: [
              DataCell(Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (c.creditLimit == -1) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)]
                    ]),
                    Text(c.nickname ?? c.phone ?? 'لا توجد بيانات إضافية', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              )),
              DataCell(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${c.balance} ₪', style: TextStyle(color: c.balance < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(c.creditLimit == -1 ? 'دين مفتوح' : 'سقف: ${c.creditLimit}₪', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              )),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.info_outline, color: Colors.blue, size: 18), onPressed: () => _navigateToCustomerDetails(c)),
                IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 18), onPressed: () => _showAddOrEditCustomerDialog(customer: c)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () => _deleteCustomer(c)),
              ])),
            ])).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(child: Text('لا يوجد زبائن حالياً', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)));
  }

  void _navigateToCustomerDetails(User customer) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer))).then((_) => _loadCustomers());
  }

  Widget _buildDialogField(String label, TextEditingController controller, IconData icon, {bool isNumeric = false, int maxLines = 1, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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
    final customers = await db.getCustomers();
    final fresh = customers.firstWhere((c) => c.id == _currentCustomer.id);
    final invoices = await db.getCustomerInvoices(fresh.id!);
    setState(() {
      _currentCustomer = fresh;
      _invoices = invoices;
      _isLoading = false;
    });
  }

  Future<void> _showBulkRepaymentDialog() async {
    final db = context.read<DatabaseService>();
    final methods = await db.getPaymentMethods(category: 'SALE');
    final unpaidInvoices = _invoices.where((inv) => inv.paymentStatus != 'PAID' && inv.paymentStatus != 'paid').toList();
    
    if (unpaidInvoices.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد ديون مستحقة للسداد')));
      return;
    }

    double totalDebt = unpaidInvoices.fold(0, (sum, item) => sum + item.remainingAmount);
    final amountController = TextEditingController(text: totalDebt.toString());
    final notesController = TextEditingController();
    PaymentMethod? selectedMethod = methods.isNotEmpty ? methods.first : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تسديد الديون المتراكمة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إجمالي الدين المطلوب سداده: ${totalDebt.toStringAsFixed(2)} ₪', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'المبلغ المدفوع الآن', prefixText: '₪ '),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PaymentMethod>(
                value: selectedMethod,
                items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedMethod = v),
                decoration: const InputDecoration(labelText: 'وسيلة الدفع'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'ملاحظات السداد'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                double amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0 || selectedMethod == null) return;

                await db.processBulkPayment(
                  userId: _currentCustomer.id!,
                  amountPaid: amount,
                  paymentMethodId: selectedMethod!.id!,
                  notes: notesController.text,
                );

                Navigator.pop(context);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت عملية السداد وتحديث الفواتير بنجاح'), backgroundColor: Colors.green));
              },
              child: const Text('تأكيد السداد'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            Text(_currentCustomer.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            if (_currentCustomer.creditLimit == -1) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: Colors.blue, size: 24),
            ],
          ],
        ),
        actions: [
          if (_currentCustomer.balance < 0)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: ElevatedButton.icon(
                onPressed: _showBulkRepaymentDialog,
                icon: const Icon(Icons.payments_outlined, color: Colors.white),
                label: const Text('تسديد الديون', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
        ],
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoGrid(isDark),
            const SizedBox(height: 40),
            Text('سجل الفواتير والديون', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 16),
            _buildInvoicesList(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoGrid(bool isDark) {
    // حساب إجمالي الدين المطلوب سداده (مجموع المبالغ المتبقية من الفواتير غير المدفوعة)
    double totalDebtRepayment = _invoices
        .where((inv) => inv.paymentStatus != 'PAID' && inv.paymentStatus != 'paid')
        .fold(0, (sum, item) => sum + item.remainingAmount);

    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: [
        _buildDetailCard('الرصيد الحالي', '${_currentCustomer.balance.toStringAsFixed(2)} ₪', _currentCustomer.balance < 0 ? Colors.red : Colors.green, isDark, width: 250),
        
        // بطاقة إجمالي الدين المطلوب سداده (جديد)
        if (totalDebtRepayment > 0)
          _buildDetailCard('إجمالي الدين الكلي', '${totalDebtRepayment.toStringAsFixed(2)} ₪', Colors.redAccent, isDark, width: 250),
        
        _buildDetailCard('سقف الدين', _currentCustomer.creditLimit == -1 ? 'غير محدود' : '${_currentCustomer.creditLimit} ₪', Colors.orange, isDark, width: 250),
        if (_currentCustomer.nickname != null && _currentCustomer.nickname!.isNotEmpty) 
          _buildDetailCard('اللقب', _currentCustomer.nickname!, Colors.blue, isDark, width: 250),
        if (_currentCustomer.transferNames != null && _currentCustomer.transferNames!.isNotEmpty) 
          _buildDetailCard('أسماء التحويل', _currentCustomer.transferNames!, Colors.purple, isDark, width: 250),
        if (_currentCustomer.notes != null && _currentCustomer.notes!.isNotEmpty) 
          _buildDetailCard('ملاحظات', _currentCustomer.notes!, Colors.blueGrey, isDark, width: 520),
      ],
    );
  }

  Widget _buildDetailCard(String label, String value, Color color, bool isDark, {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildInvoicesList(bool isDark) {
    if (_invoices.isEmpty) return Center(child: Text('لا توجد فواتير مسجلة', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)));
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final inv = _invoices[index];
        bool isPaid = inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid';
        bool isPartial = inv.paymentStatus == 'PARTIAL';
        
        Color statusColor = isPaid ? Colors.green : (isPartial ? Colors.orange : Colors.red);
        String statusLabel = isPaid ? 'مدفوع' : (isPartial ? 'مدفوع جزئياً' : 'دين قائمة');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            title: Row(
              children: [
                Text('${inv.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
                if (isPartial) ...[
                  const SizedBox(width: 12),
                  Text('(المدفوع: ${inv.paidAmount} ₪)', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                ]
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التاريخ: ${inv.invoiceDate}', style: const TextStyle(color: Colors.grey)),
                if (inv.notes != null) Text('ملاحظات: ${inv.notes}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }
}
