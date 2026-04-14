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
  
  String _sortBy = "name"; // name, balance, createdAt, permanent
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
    final auth = context.read<AuthService>();

    List<User> customers;
    if (auth.isManager()) {
      // If manager, we might want to see accountants as well in some view,
      // but for "Customers" screen, we filter by role CUSTOMER.
      final all = await db.getCustomers();
      customers = all.where((u) => u.role == 'CUSTOMER' || u.role == 'customer').toList();
    } else {
      customers = await db.getCustomers();
    }

    setState(() {
      _customers = customers;
      _filteredCustomers = List.from(customers);
      _isLoading = false;
      _applySort(); 
    });
  }

  void _applySort() {
    setState(() {
      _filteredCustomers.sort((a, b) {
        int result = 0;
        if (_sortBy == 'name') {
          result = a.name.compareTo(b.name);
        } else if (_sortBy == 'balance') {
          result = a.balance.compareTo(b.balance);
        } else if (_sortBy == 'createdAt') {
          result = a.createdAt.compareTo(b.createdAt);
        } else if (_sortBy == 'permanent') {
          result = a.isPermanentCustomer.compareTo(b.isPermanentCustomer);
        }
        return _isAscending ? result : -result;
      });
    });
  }

  void _onSort(String criteria) {
    setState(() {
      if (_sortBy == criteria) {
        _isAscending = !_isAscending;
      } else {
        _sortBy = criteria;
        _isAscending = true;
      }
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
                final auth = context.read<AuthService>();
                double limit = isUnlimited ? -1 : (double.tryParse(limitController.text) ?? 100.0);

                final userData = User(
                  id: customer?.id,
                  uuid: customer?.uuid ?? '',
                  parentId: customer?.parentId ?? auth.currentUser?.getStoreManagerIdLocal(),
                  username: customer?.username ?? 'cust_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text.trim(),
                  nickname: nicknameController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: 'CUSTOMER',
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
    final auth = context.read<AuthService>();

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
                _buildSearchBar(isDark, isSmall),
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
        heroTag: 'add_cust',
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

  Widget _buildSearchBar(bool isDark, bool isSmall) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: _filterCustomers,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: isSmall ? 'بحث...' : 'بحث بالاسم، اللقب، أو اسم التحويل...',
                hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[400]),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.blue),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _buildSortMenu(isDark),
      ],
    );
  }

  Widget _buildSortMenu(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.sort_rounded, color: Colors.blue),
        tooltip: 'ترتيب حسب',
        onSelected: _onSort,
        itemBuilder: (context) => [
          _buildSortItem('name', 'اسم المشتري'),
          _buildSortItem('balance', 'الدين / الرصيد'),
          _buildSortItem('createdAt', 'وقت الانشاء'),
          _buildSortItem('permanent', 'دائم / غير دائم'),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildSortItem(String value, String label) {
    bool isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blue : null)),
          const Spacer(),
          if (isSelected) Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildCustomerGrid(Size size, bool isDark) {
    int crossAxisCount = (size.width > 1400) ? 4 : (size.width > 1000 ? 3 : (size.width > 650 ? 2 : 1));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
    bool isDebt = customer.balance > 0;
    bool isCredit = customer.balance < 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${customer.balance.toStringAsFixed(2)} ₪', 
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, 
          color: isDebt ? Colors.redAccent : (isCredit ? Colors.green : Colors.grey))),
        Text(isDebt ? 'دين' : (isCredit ? 'رصيد' : 'متعادل'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
      scrollDirection: Axis.vertical, 
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
            sortColumnIndex: _getSortColumnIndex(),
            sortAscending: _isAscending,
            columnSpacing: isCompact ? 12 : 24,
            horizontalMargin: 16,
            dataRowMaxHeight: 80, 
            dataRowMinHeight: 60,
            headingRowColor: MaterialStateProperty.all(isDark ? const Color(0xFF1E293B) : Colors.grey[50]),
            columns: [
              DataColumn(
                label: const Text('معلومات الزبون', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (_, __) => _onSort('name'),
              ),
              DataColumn(
                label: const Text('الحساب', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (_, __) => _onSort('balance'),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                        if (c.creditLimit == -1) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)]
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(c.nickname ?? c.phone ?? 'لا توجد بيانات إضافية', 
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )),
              DataCell(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${c.balance.toStringAsFixed(2)} ₪', 
                    style: TextStyle(color: c.balance > 0 ? Colors.red : (c.balance < 0 ? Colors.green : Colors.grey), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(c.isPermanentCustomer == 1 ? (c.creditLimit == -1 ? 'دين مفتوح' : 'دائم (سقف: ${c.creditLimit}₪)') : 'زبون غير دائم', 
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  int? _getSortColumnIndex() {
    if (_sortBy == 'name') return 0;
    if (_sortBy == 'balance') return 1;
    return null;
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(child: Text('لا يوجد زبائن حالياً', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)));
  }

  void _navigateToCustomerDetails(User customer) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer))).then((_) => _loadCustomers());
  }

  Widget _buildDialogField(String label, TextEditingController controller, IconData icon, {bool isNumeric = false, int maxLines = 1, Function(String)? onChanged, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        obscureText: obscure,
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
  double _calculatedBalance = 0.0;

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
      _calculatedBalance = fresh.balance; // Unified Balance
      _isLoading = false;
    });
  }

  Future<void> _showRepaymentDialog() async {
    final db = context.read<DatabaseService>();
    final methods = await db.getPaymentMethods(category: 'SALE');
    
    double calculatedDebt = _calculatedBalance > 0 ? _calculatedBalance : 0;

    final amountController = TextEditingController(text: calculatedDebt > 0 ? calculatedDebt.toStringAsFixed(2) : '');
    final notesController = TextEditingController();
    PaymentMethod? selectedMethod = methods.isNotEmpty ? methods.first : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('تسجيل دفعة سداد', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (calculatedDebt > 0)
                  Text('إجمالي الدين المستحق: ${calculatedDebt.toStringAsFixed(2)} ₪', 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المدفوع', 
                    prefixText: '₪ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentMethod>(
                  value: selectedMethod,
                  items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                  onChanged: (v) => setDialogState(() => selectedMethod = v),
                  decoration: InputDecoration(
                    labelText: 'وسيلة الدفع',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات السداد',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                double amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0 || selectedMethod == null) return;

                await db.addCredit(
                  userId: _currentCustomer.id!,
                  amount: amount,
                  paymentMethodId: selectedMethod!.id!,
                  notes: 'سداد ديون: ${notesController.text}',
                );

                Navigator.pop(context);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل دفعة السداد بنجاح'), backgroundColor: Colors.green));
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('تأكيد السداد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(_currentCustomer.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, fontSize: isMobile ? 16 : 20), overflow: TextOverflow.ellipsis)),
                  if (_currentCustomer.creditLimit == -1) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.verified, color: Colors.blue, size: 22),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _showRepaymentDialog,
              icon: const Icon(Icons.add_card_rounded, color: Colors.white, size: 18),
              label: Text(isMobile ? 'سداد' : 'تسديد الديون', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0
              ),
            ),
          ),
        ],
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoGrid(isDark, size),
            const SizedBox(height: 40),
            Text('سجل الفواتير والديون', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 16),
            _buildInvoicesList(isDark, isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoGrid(bool isDark, Size size) {
    final bool isDebt = _calculatedBalance > 0;
    final bool isCredit = _calculatedBalance < 0;

    final bool isMobile = size.width < 700;
    final double cardWidth = isMobile ? (size.width - 48) : 250;

    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: [
        _buildDetailCard(
          isDebt ? 'إجمالي الدين الكلي' : 'إجمالي الرصيد الدائن', 
          '${_calculatedBalance.toStringAsFixed(2)} ₪',
          isDebt ? Colors.red : (isCredit ? Colors.green : Colors.grey), 
          isDark, 
          width: cardWidth,
          subtitle: isDebt ? 'مستحق الدفع' : (isCredit ? 'رصيد لك لدينا' : 'الحساب متعادل')
        ),
        
        _buildDetailCard('سقف الدين', _currentCustomer.creditLimit == -1 ? 'غير محدود' : '${_currentCustomer.creditLimit} ₪', Colors.orange, isDark, width: cardWidth),
        
        if (_currentCustomer.nickname != null && _currentCustomer.nickname!.isNotEmpty) 
          _buildDetailCard('اللقب', _currentCustomer.nickname!, Colors.blue, isDark, width: cardWidth),
        if (_currentCustomer.transferNames != null && _currentCustomer.transferNames!.isNotEmpty) 
          _buildDetailCard('أسماء التحويل', _currentCustomer.transferNames!, Colors.purple, isDark, width: cardWidth),
        if (_currentCustomer.notes != null && _currentCustomer.notes!.isNotEmpty) 
          _buildDetailCard('ملاحظات', _currentCustomer.notes!, Colors.blueGrey, isDark, width: isMobile ? cardWidth : (cardWidth * 2 + 20)),
      ],
    );
  }

  Widget _buildDetailCard(String label, String value, Color color, bool isDark, {required double width, String? subtitle}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: color.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }

  Widget _buildInvoicesList(bool isDark, bool isMobile) {
    if (_invoices.isEmpty) return Center(child: Text('لا توجد فواتير مسجلة', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)));
    
    final sortedInvoices = List<Invoice>.from(_invoices)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedInvoices.length,
      itemBuilder: (context, index) {
        final inv = sortedInvoices[index];
        bool isPaid = inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid';
        bool isPartial = inv.paymentStatus == 'PARTIAL';
        bool isDeposit = inv.type == 'DEPOSIT';
        
        if (isDeposit) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            decoration: BoxDecoration(
              color: Colors.green[600]!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green[600]!.withOpacity(0.3), width: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.green[600], borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.payments_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('دفعة سداد ديون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green[800])),
                      if (inv.methodName != null) 
                        Text('عبر: ${inv.methodName}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('التاريخ: ${inv.invoiceDate}', style: TextStyle(color: Colors.green[800]!.withOpacity(0.7), fontSize: 11)),
                      if (inv.notes != null) Text(inv.notes!, style: TextStyle(fontSize: 12, color: Colors.green[900])),
                    ],
                  ),
                ),
                Text('${inv.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: isMobile ? 18 : 24, color: Colors.green[800])),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20, vertical: 10),
                title: Row(
                  children: [
                    Text('${inv.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
                    if (isPartial) ...[
                      const SizedBox(width: 12),
                      Text('(المدفوع: ${inv.paidAmount} ₪)', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    ]
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPaid && inv.methodName != null) 
                       Text('وسيلة الدفع: ${inv.methodName}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('التاريخ: ${inv.invoiceDate}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    if (inv.notes != null) Text('ملاحظات: ${inv.notes}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isPaid ? Colors.blue : Colors.orange,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
