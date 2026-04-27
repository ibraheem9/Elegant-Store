import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../core/constants/app_colors.dart';
import 'add_edit_customer_form.dart';
import '../widgets/shimmer_loading.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper: always display amounts with exactly 2 decimal places.
// ─────────────────────────────────────────────────────────────────────────────
String _fmt(double? value) => (value ?? 0.0).toStringAsFixed(2);

/// Returns the balance text color using the unified AppColors system.
/// balance > 0 → debtor (red) | balance < 0 → has credit (green) | 0 → grey
Color _balanceColor(double balance) => AppColors.balanceTextColor(balance);

// ─────────────────────────────────────────────────────────────────────────────
// CustomersScreen
// ─────────────────────────────────────────────────────────────────────────────
class CustomersScreen extends StatefulWidget {
  final bool showBackButton;
  const CustomersScreen({Key? key, this.showBackButton = false}) : super(key: key);

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<User> _customers = [];
  List<User> _filteredCustomers = [];
  bool _isLoading = false;
  bool _isTableView = false;

  String _sortBy = 'name';
  bool _isAscending = true;

  static const int _pageSize = 20;
  int _displayCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final all = await db.getCustomers();
    final customers = all
        .where((u) => u.role == 'CUSTOMER' || u.role == 'customer')
        .toList();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _filteredCustomers = List.from(customers);
      _isLoading = false;
      _displayCount = _pageSize;
      _applySort();
    });
  }

  void _applySort() {
    _filteredCustomers.sort((a, b) {
      int r = 0;
      switch (_sortBy) {
        case 'name':      r = a.name.compareTo(b.name); break;
        case 'balance':   r = a.balance.compareTo(b.balance); break;
        case 'createdAt': r = a.createdAt.compareTo(b.createdAt); break;
        case 'permanent': r = a.isPermanentCustomer.compareTo(b.isPermanentCustomer); break;
      }
      return _isAscending ? r : -r;
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
    final q = db.normalizeArabic(query);
    setState(() {
      _filteredCustomers = _customers.where((c) =>
        db.normalizeArabic(c.name).contains(q) ||
        (c.nickname != null && db.normalizeArabic(c.nickname!).contains(q)) ||
        (c.phone != null && c.phone!.contains(query)) ||
        (c.transferNames != null && db.normalizeArabic(c.transferNames!).contains(q)),
      ).toList();
      _applySort();
      _displayCount = _pageSize;
    });
  }

  Future<void> _deleteCustomer(User customer) async {
    final db = context.read<DatabaseService>();
    final linkedCount = await db.countCustomerLinkedRecords(customer.id!);
    if (!mounted) return;

    if (linkedCount > 0) {
      // Customer has linked records — offer two options: delete alone (blocked) or delete with all invoices
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('حذف الزبون', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          content: Text(
            'الزبون "${customer.name}" مرتبط بـ $linkedCount سجل مالي.\n\n'
            'اختر طريقة الحذف:',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(context, 'with_invoices'),
              child: const Text('حذف مع كافة الفواتير', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (choice == 'with_invoices') {
        final confirm2 = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.delete_forever, color: Colors.red, size: 24),
              SizedBox(width: 10),
              Text('تأكيد نهائي', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ]),
            content: Text(
              'سيتم حذف الزبون "${customer.name}" وجميع فواتيره ($linkedCount سجل).\nهذا الإجراء لا يمكن التراجع عنه. هل أنت متأكد؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('نعم، احذف كل شيء', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm2 == true) {
          await db.softDeleteCustomerWithInvoices(customer.id!);
          final _actUser = context.read<AuthService>().currentUser;
          db.logActivity(
            targetId: customer.id!,
            targetType: 'CUSTOMER',
            action: 'DELETE',
            summary: 'حذف الزبون مع جميع فواتيره: ${customer.name}',
            performedById: _actUser?.id,
            performedByName: _actUser?.name,
            storeManagerId: _actUser?.parentId ?? _actUser?.id,
          ).catchError((e) => debugPrint('logActivity failed: $e'));
          _loadCustomers();
        }
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الزبون "${customer.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await db.softDeleteUser(customer.id!);
      final _actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: customer.id!,
        targetType: 'CUSTOMER',
        action: 'DELETE',
        summary: 'حذف الزبون: ${customer.name}',
        performedById: _actUser?.id,
        performedByName: _actUser?.name,
        storeManagerId: _actUser?.parentId ?? _actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      _loadCustomers();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
            padding: EdgeInsets.fromLTRB(isSmall ? 12 : 24, isSmall ? 12 : 20, isSmall ? 12 : 24, 8),
            child: _buildHeaderRow(isDark, isSmall),
          ),
          Expanded(
            child: _isLoading
                ? ShimmerLoading(isDark: isDark, itemCount: 6)
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
        onPressed: () async {
          final saved = await showAddEditCustomerForm(context);
          if (saved) _loadCustomers();
        },
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18),
        label: const Text('إضافة زبون',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  // ── Header row: [back?] [search──────] [sort▾] [toggle] ──────────────────

  Widget _buildHeaderRow(bool isDark, bool isSmall) {
    final boxDecoration = BoxDecoration(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
    );

    return Row(
      children: [
        if (widget.showBackButton) ...[
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : const Color(0xFF0F172A), size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
        ],
        // Search bar
        Expanded(
          child: Container(
            height: 42,
            decoration: boxDecoration,
            child: TextField(
              onChanged: _filterCustomers,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: isSmall ? 'بحث...' : 'بحث بالاسم أو اللقب أو الهاتف...',
                hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[400], fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.blue, size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sort dropdown
        Container(
          height: 42,
          decoration: boxDecoration,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: Colors.blue, size: 20),
            tooltip: 'ترتيب',
            onSelected: _onSort,
            itemBuilder: (_) => [
              _sortItem('name', 'الاسم'),
              _sortItem('balance', 'الرصيد'),
              _sortItem('createdAt', 'تاريخ الإضافة'),
              _sortItem('permanent', 'نوع الزبون'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Single toggle button
        GestureDetector(
          onTap: () => setState(() => _isTableView = !_isTableView),
          child: Container(
            height: 42,
            width: 42,
            decoration: boxDecoration,
            child: Icon(
              _isTableView ? Icons.grid_view_rounded : Icons.table_rows_rounded,
              color: Colors.blue,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    final selected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.blue : null)),
        const Spacer(),
        if (selected)
          Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14, color: Colors.blue),
      ]),
    );
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildCustomerGrid(Size size, bool isDark) {
    int cols = size.width > 1400 ? 4 : (size.width > 1000 ? 3 : (size.width > 650 ? 2 : 1));
    final displayed = _filteredCustomers.take(_displayCount).toList();
    final hasMore = _filteredCustomers.length > _displayCount;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildCustomerCard(displayed[i], isDark),
              childCount: displayed.length,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 110,
            ),
          ),
        ),
        if (hasMore)
          SliverToBoxAdapter(child: _buildLoadMore()),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  /// Slim card: name + badge, nickname, credit — no avatar, no phone, no delete.
  Widget _buildCustomerCard(User customer, bool isDark) {
    final isVerified = customer.creditLimit == -1;
    final isManager = context.read<AuthService>().isManager();
    final balance = customer.balance;
    // Unified color system:
    //   balance > 0 → debtor (red tint)
    //   balance < 0 → has credit with us (green tint)
    //   balance = 0 → settled (neutral grey)
    final cardBg     = AppColors.customerCardBackground(balance, isDark: isDark);
    final cardBorder = AppColors.customerCardBorder(balance, isDark: isDark);
    final borderWidth = balance == 0.0 ? 1.0 : 1.5;

    return GestureDetector(
      onTap: () => _navigateToDetails(customer),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder, width: borderWidth),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Left: name + nickname
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(customer.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, color: Colors.blue, size: 14),
                      ],
                      // Balance status badge
                      if (balance == 0.0) ...[  // settled
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.zeroBadge.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, color: AppColors.zeroBadge, size: 10),
                              const SizedBox(width: 2),
                              Text('مسدد', style: TextStyle(fontSize: 9, color: AppColors.zeroBadge, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ] else if (balance > 0) ...[  // debtor
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.debtorBadge.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.debtorBadge, size: 10),
                              const SizedBox(width: 2),
                              Text('مدين', style: TextStyle(fontSize: 9, color: AppColors.debtorBadge, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ] else ...[  // has credit
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.creditBadge.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_wallet_rounded, color: AppColors.creditBadge, size: 10),
                              const SizedBox(width: 2),
                              Text('رصيد', style: TextStyle(fontSize: 9, color: AppColors.creditBadge, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (customer.nickname != null && customer.nickname!.isNotEmpty)
                    Text(customer.nickname!,
                        style: const TextStyle(
                            color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: balance + edit button
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_fmt(customer.balance)} ₪',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: _balanceColor(customer.balance))),
                Text(
                  customer.balance > 0
                      ? 'دين'
                      : (customer.balance < 0 ? 'رصيد' : 'متعادل'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isManager)
                  GestureDetector(
                    onTap: () async {
                      final saved = await showAddEditCustomerForm(context, customer: customer);
                      if (saved) _loadCustomers();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('تعديل',
                          style: TextStyle(
                              fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildCustomerTable(Size size, bool isDark) {
    final displayed = _filteredCustomers.take(_displayCount).toList();
    final hasMore = _filteredCustomers.length > _displayCount;
    final isManager = context.read<AuthService>().isManager();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(minWidth: size.width - 48),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              ),
              child: DataTable(
                sortColumnIndex: _sortBy == 'name' ? 0 : (_sortBy == 'balance' ? 1 : null),
                sortAscending: _isAscending,
                columnSpacing: 16,
                horizontalMargin: 14,
                dataRowMaxHeight: 60,
                dataRowMinHeight: 48,
                headingRowHeight: 44,
                headingRowColor: MaterialStateProperty.all(
                    isDark ? const Color(0xFF1E293B) : Colors.grey[50]),
                columns: [
                  DataColumn(
                    label: const Text('الزبون',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onSort: (_, __) => _onSort('name'),
                  ),
                  DataColumn(
                    label: const Text('الرصيد',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onSort: (_, __) => _onSort('balance'),
                  ),
                  if (isManager)
                    const DataColumn(
                        label: Text('إجراء',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                ],
                rows: displayed.map((c) {
                  final isVerified = c.creditLimit == -1;
                  return DataRow(
                    color: MaterialStateProperty.all(
                      AppColors.customerCardBackground(c.balance, isDark: isDark)
                          .withOpacity(c.balance == 0.0 ? 0 : 0.35),
                    ),
                    cells: [
                      // Name cell — tap to go to details
                      DataCell(
                        GestureDetector(
                          onTap: () => _navigateToDetails(c),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Flexible(
                                  child: Text(c.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 13),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, color: Colors.blue, size: 13),
                                ],
                              ]),
                              if (c.nickname != null && c.nickname!.isNotEmpty)
                                Text(c.nickname!,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                      // Balance cell
                      DataCell(Text(
                        '${_fmt(c.balance)} ₪',
                        style: TextStyle(
                            color: _balanceColor(c.balance),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      )),
                      // Actions cell
                      if (isManager)
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                            tooltip: 'تعديل',
                            onPressed: () async {
                              final saved =
                                  await showAddEditCustomerForm(context, customer: c);
                              if (saved) _loadCustomers();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            tooltip: 'حذف',
                            onPressed: () => _deleteCustomer(c),
                          ),
                        ])),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (hasMore) _buildLoadMore(),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildLoadMore() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _displayCount += _pageSize),
            icon: const Icon(Icons.expand_more_rounded, color: Colors.blue),
            label: Text(
              'تحميل المزيد (متبقي ${_filteredCustomers.length - _displayCount})',
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );

  Widget _buildEmptyState(bool isDark) => Center(
        child: Text('لا يوجد زبائن حالياً',
            style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)),
      );

  void _navigateToDetails(User customer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
    ).then((_) => _loadCustomers());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomerDetailsScreen
// ─────────────────────────────────────────────────────────────────────────────
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

  static const int _invoicePageSize = 20;
  int _invoiceDisplayCount = _invoicePageSize;

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
    final fresh = customers.firstWhere((c) => c.id == _currentCustomer.id,
        orElse: () => _currentCustomer);
    final invoices = await db.getCustomerInvoices(fresh.id!);
    if (!mounted) return;
    setState(() {
      _currentCustomer = fresh;
      _invoices = invoices;
      _calculatedBalance = fresh.balance;
      _isLoading = false;
    });
  }

  // ── Delete customer ───────────────────────────────────────────────────────

  Future<void> _deleteCustomer() async {
    final db = context.read<DatabaseService>();
    final linkedCount = await db.countCustomerLinkedRecords(_currentCustomer.id!);
    if (!mounted) return;

    if (linkedCount > 0) {
      // Customer has linked records — offer option to delete with all invoices
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('حذف الزبون', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          content: Text(
            'الزبون "${_currentCustomer.name}" مرتبط بـ $linkedCount سجل مالي.\n\n'
            'اختر طريقة الحذف:',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(context, 'with_invoices'),
              child: const Text('حذف مع كافة الفواتير', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (choice == 'with_invoices') {
        final confirm2 = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.delete_forever, color: Colors.red, size: 24),
              SizedBox(width: 10),
              Text('تأكيد نهائي', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ]),
            content: Text(
              'سيتم حذف الزبون "${_currentCustomer.name}" وجميع فواتيره ($linkedCount سجل).\nهذا الإجراء لا يمكن التراجع عنه. هل أنت متأكد؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('نعم، احذف كل شيء', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm2 == true) {
          await db.softDeleteCustomerWithInvoices(_currentCustomer.id!);
          final _actUser = context.read<AuthService>().currentUser;
          db.logActivity(
            targetId: _currentCustomer.id!,
            targetType: 'CUSTOMER',
            action: 'DELETE',
            summary: 'حذف الزبون مع جميع فواتيره: ${_currentCustomer.name}',
            performedById: _actUser?.id,
            performedByName: _actUser?.name,
            storeManagerId: _actUser?.parentId ?? _actUser?.id,
          ).catchError((e) => debugPrint('logActivity failed: $e'));
          if (mounted) Navigator.of(context).pop();
        }
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الزبون "${_currentCustomer.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await db.softDeleteUser(_currentCustomer.id!);
      final _actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: _currentCustomer.id!,
        targetType: 'CUSTOMER',
        action: 'DELETE',
        summary: 'حذف الزبون: ${_currentCustomer.name}',
        performedById: _actUser?.id,
        performedByName: _actUser?.name,
        storeManagerId: _actUser?.parentId ?? _actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Repayment dialog ──────────────────────────────────────────────────────

  Future<void> _showRepaymentDialog() async {
    final db = context.read<DatabaseService>();
    final methods = await db.getPaymentMethods(category: 'SALE');
    double calculatedDebt = _calculatedBalance > 0 ? _calculatedBalance : 0;
    final amountController =
        TextEditingController(text: calculatedDebt > 0 ? _fmt(calculatedDebt) : '');
    final notesController = TextEditingController();
    PaymentMethod? selectedMethod = methods.isNotEmpty ? methods.first : null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('تسجيل دفعة سداد',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (calculatedDebt > 0)
                Text('إجمالي الدين: ${_fmt(calculatedDebt)} ₪',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: 'المبلغ المدفوع',
                  prefixText: '₪ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PaymentMethod>(
                value: selectedMethod,
                items: methods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedMethod = v),
                decoration: InputDecoration(
                  labelText: 'وسيلة الدفع',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0 || selectedMethod == null) return;
                await db.addCredit(
                  userId: _currentCustomer.id!,
                  amount: amount,
                  paymentMethodId: selectedMethod!.id!,
                  notes: 'سداد ديون: ${notesController.text}',
                );
                Navigator.pop(ctx);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(
                      content: Text('تم تسجيل دفعة السداد بنجاح'),
                      backgroundColor: Colors.green));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('تأكيد السداد',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Invoice actions ───────────────────────────────────────────────────────

  Future<void> _deleteInvoice(Invoice inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 10),
          Text('تأكيد الحذف', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('هل أنت متأكد من حذف هذه الفاتورة؟'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المبلغ: ${_fmt(inv.amount)} ₪',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              Text('التاريخ: ${inv.invoiceDate}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('سيتم تصحيح رصيد الزبون تلقائياً.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded, color: Colors.white, size: 18),
            label: const Text('حذف',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = context.read<DatabaseService>();
    await db.softDeleteInvoice(inv); // recalculateUserBalance is called inside
    final _actUser = context.read<AuthService>().currentUser;
    db.logActivity(
      targetId: inv.id!,
      targetType: 'INVOICE',
      action: 'DELETE',
      summary: 'حذف فاتورة للزبون ${_currentCustomer.name} بمبلغ ${inv.amount.toStringAsFixed(2)} ₪',
      performedById: _actUser?.id,
      performedByName: _actUser?.name,
      storeManagerId: _actUser?.parentId ?? _actUser?.id,
    ).catchError((e) => debugPrint('logActivity failed: $e'));
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(
          content: Text('تم حذف الفاتورة بنجاح'), backgroundColor: Colors.red));
    }
  }

  Future<void> _editInvoice(Invoice inv) async {
    final amountController = TextEditingController(text: _fmt(inv.amount));
    final notesController = TextEditingController(text: inv.notes ?? '');
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.edit_rounded, color: Colors.blue, size: 24),
          SizedBox(width: 10),
          Text('تعديل الفاتورة', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                prefixText: '₪ ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'سبب التعديل *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
            label: const Text('حفظ',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newAmount = double.tryParse(amountController.text.trim());
    if (newAmount == null || newAmount <= 0) return;
    final reason = reasonController.text.trim().isEmpty
        ? 'تعديل يدوي'
        : reasonController.text.trim();
    final now = DateTime.now().toIso8601String();
    final newInv = Invoice(
      id: inv.id,
      uuid: inv.uuid,
      storeManagerId: inv.storeManagerId,
      userId: inv.userId,
      invoiceDate: inv.invoiceDate,
      amount: newAmount,
      paidAmount: inv.paidAmount,
      paymentMethodId: inv.paymentMethodId,
      paymentStatus: inv.paymentStatus,
      type: inv.type,
      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      version: inv.version,
      createdAt: inv.createdAt,
      updatedAt: now,
      isSynced: 0,
    );
    final db = context.read<DatabaseService>();
    final _actUser = context.read<AuthService>().currentUser;
    await db.updateInvoiceWithLog(
      oldInv: inv,
      newInv: newInv,
      reason: reason,
      performedById: _actUser?.id,
      performedByName: _actUser?.name,
      storeManagerId: _actUser?.parentId ?? _actUser?.id,
    );
    await db.recalculateUserBalance(inv.userId);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(
          content: Text('تم تعديل الفاتورة بنجاح'), backgroundColor: Colors.blue));
    }
  }

  Future<void> _showEditHistory(Invoice inv) async {
    final db = context.read<DatabaseService>();
    final history = await db.getEditHistory(inv.id!, 'INVOICE');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.history_rounded, color: Colors.purple, size: 24),
          SizedBox(width: 10),
          Text('سجل التعديلات', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 360,
          child: history.isEmpty
              ? const Text('لا توجد تعديلات مسجلة.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = history[i];
                    // Resolve field label from raw DB key
                    final rawField = h['field_name'] as String?;
                    final fieldLabel = rawField == 'amount'
                        ? 'المبلغ'
                        : rawField == 'payment_status'
                            ? 'حالة الدفع'
                            : rawField == 'notes'
                                ? 'الملاحظات'
                                : rawField == 'payment_method_id'
                                    ? 'طريقة الدفع'
                                    : rawField;
                    final action = h['action'] as String? ?? 'UPDATE';
                    final summary = h['summary'] as String?;
                    final oldVal = h['old_value'] as String?;
                    final newVal = h['new_value'] as String?;
                    final creatorName = h['edited_by_name'] as String?;
                    final hasFieldChange = fieldLabel != null && oldVal != null && newVal != null;
                    // Badge color by action type
                    final badgeColor = action == 'CREATE'
                        ? Colors.green
                        : action == 'DELETE'
                            ? Colors.red
                            : Colors.orange;
                    // Format date
                    String dateStr = h['created_at']?.toString() ?? '';
                    try {
                      final dt = DateTime.parse(dateStr).toLocal();
                      dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {
                      if (dateStr.length > 16) dateStr = dateStr.substring(0, 16);
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Action badge + field label
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  action == 'CREATE' ? 'إضافة' : action == 'DELETE' ? 'حذف' : 'تعديل',
                                  style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (hasFieldChange) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.edit_note_rounded, size: 16, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text(fieldLabel!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ]),
                            // Creator name for CREATE/DELETE actions
                            if (creatorName != null && creatorName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(
                                  action == 'CREATE' ? Icons.person_add_rounded : Icons.person_rounded,
                                  size: 13,
                                  color: badgeColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  action == 'CREATE'
                                      ? 'أُنشئت بواسطة: $creatorName'
                                      : action == 'DELETE'
                                          ? 'حُذفت بواسطة: $creatorName'
                                          : 'عُدّلت بواسطة: $creatorName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: badgeColor,
                                  ),
                                ),
                              ]),
                            ],
                            // Summary line (if available)
                            if (summary != null && summary.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(summary, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                            ],
                            // Old → New values (only when a specific field changed)
                            if (hasFieldChange) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Flexible(child: Text('من: $oldVal', style: const TextStyle(color: Colors.red, fontSize: 12))),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                                const SizedBox(width: 8),
                                Flexible(child: Text('إلى: $newVal', style: const TextStyle(color: Colors.green, fontSize: 12))),
                              ]),
                            ],
                            if (h['edit_reason'] != null && h['edit_reason'].toString().isNotEmpty)
                              Text('السبب: ${h['edit_reason']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                            const SizedBox(height: 2),
                            Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ]),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  bool _wasEdited(Invoice inv) {
    if (inv.createdAt.isEmpty || inv.updatedAt.isEmpty) return false;
    return inv.createdAt.substring(0, 19) != inv.updatedAt.substring(0, 19);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;
    final isManager = context.read<AuthService>().isManager();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        // Tapping the customer name shows a dropdown: Edit / Delete
        title: isManager
            ? PopupMenuButton<String>(
                offset: const Offset(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (value) async {
                  if (value == 'edit') {
                    final saved = await showAddEditCustomerForm(context, customer: _currentCustomer);
                    if (saved) _loadData();
                  } else if (value == 'delete') {
                    await _deleteCustomer();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: const [
                      Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                      SizedBox(width: 10),
                      Text('تعديل بيانات الزبون'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: const [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 10),
                      Text('حذف الزبون', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(
                      _currentCustomer.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: isMobile ? 16 : 20),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_currentCustomer.creditLimit == -1) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, color: Colors.blue, size: 20),
                  ],
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down_rounded,
                      color: isDark ? Colors.white54 : Colors.black38, size: 20),
                ]),
              )
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    _currentCustomer.name,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: isMobile ? 16 : 20),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_currentCustomer.creditLimit == -1) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, color: Colors.blue, size: 20),
                ],
              ]),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _showRepaymentDialog,
              icon: const Icon(Icons.add_card_rounded, color: Colors.white, size: 18),
              label: Text(isMobile ? 'سداد' : 'تسديد الديون',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0),
            ),
          ),
        ],
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: _isLoading
          ? ShimmerLoading(isDark: isDark, itemCount: 5)
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 16 : 32, isMobile ? 16 : 32, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildInfoGrid(isDark, size),
                const SizedBox(height: 32),
                Text('سجل الفواتير والديون',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 12),
                _buildInvoicesList(isDark, isMobile),
              ]),
            ),
    );
  }

  /// Shows a dropdown menu anchored to the customer name in the AppBar.
  void _showNameDropdown(BuildContext context, bool isDark) async {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + renderBox.size.height,
        offset.dx + renderBox.size.width,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: const [
            Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
            SizedBox(width: 10),
            Text('تعديل بيانات الزبون'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: const [
            Icon(Icons.delete_outline, color: Colors.red, size: 18),
            SizedBox(width: 10),
            Text('حذف الزبون', style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );

    if (!mounted) return;
    if (selected == 'edit') {
      final saved = await showAddEditCustomerForm(context, customer: _currentCustomer);
      if (saved) _loadData();
    } else if (selected == 'delete') {
      await _deleteCustomer();
    }
  }

  // ── Info grid ─────────────────────────────────────────────────────────────

  Widget _buildInfoGrid(bool isDark, Size size) {
    final bool isDebt = _calculatedBalance > 0;
    final bool isCredit = _calculatedBalance < 0;
    final bool isMobile = size.width < 700;
    final double cardWidth = isMobile ? (size.width - 48) : 250;

    return Wrap(spacing: 16, runSpacing: 16, children: [
      _buildDetailCard(
        isDebt ? 'إجمالي الدين الكلي' : 'إجمالي الرصيد الدائن',
        '${_fmt(_calculatedBalance)} ₪',
        _balanceColor(_calculatedBalance),
        isDark,
        width: cardWidth,
        subtitle: isDebt
            ? 'مستحق الدفع'
            : (isCredit ? 'رصيد لك لدينا' : 'الحساب متعادل'),
      ),
      _buildDetailCard(
        'سقف الدين',
        _currentCustomer.creditLimit == -1
            ? 'غير محدود'
            : '${_fmt(_currentCustomer.creditLimit)} ₪',
        Colors.orange,
        isDark,
        width: cardWidth,
      ),
      if (_currentCustomer.nickname != null && _currentCustomer.nickname!.isNotEmpty)
        _buildDetailCard('اللقب', _currentCustomer.nickname!, Colors.blue, isDark,
            width: cardWidth),
      if (_currentCustomer.transferNames != null &&
          _currentCustomer.transferNames!.isNotEmpty)
        _buildDetailCard(
            'أسماء التحويل', _currentCustomer.transferNames!, Colors.purple, isDark,
            width: cardWidth),
      if (_currentCustomer.notes != null && _currentCustomer.notes!.isNotEmpty)
        _buildDetailCard('ملاحظات', _currentCustomer.notes!, Colors.blueGrey, isDark,
            width: isMobile ? cardWidth : (cardWidth * 2 + 16)),
    ]);
  }

  Widget _buildDetailCard(String label, String value, Color color, bool isDark,
      {required double width, String? subtitle}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey, fontSize: 13)),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ]),
    );
  }

  // ── Invoices list ─────────────────────────────────────────────────────────

  Widget _buildInvoicesList(bool isDark, bool isMobile) {
    if (_invoices.isEmpty) {
      return Center(
          child: Text('لا توجد فواتير مسجلة',
              style: TextStyle(color: isDark ? Colors.white30 : Colors.grey)));
    }

    final sorted = List<Invoice>.from(_invoices)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final displayed = sorted.take(_invoiceDisplayCount).toList();
    final hasMore = sorted.length > _invoiceDisplayCount;

    return Column(children: [
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: displayed.length,
        itemBuilder: (_, index) {
          final inv = displayed[index];
          final edited = _wasEdited(inv);
          final isDeposit    = inv.type == 'DEPOSIT';
          final isWithdrawal = inv.type == 'WITHDRAWAL';

          // Unified color system for invoice cards in customer detail
          final Color invCardBg;
          final Color invCardBorder;
          final Color invAccent;
          final IconData invIcon;
          final String invLabel;

          if (isDeposit) {
            invCardBg     = AppColors.invoiceDepositBackground;
            invCardBorder = AppColors.invoiceDepositBorder;
            invAccent     = AppColors.invoiceDeposit;
            invIcon       = Icons.payments_rounded;
            invLabel      = 'دفعة سداد ديون';
          } else if (isWithdrawal) {
            invCardBg     = const Color(0xFFFFF7ED);
            invCardBorder = const Color(0xFFFED7AA);
            invAccent     = const Color(0xFFEA580C);
            invIcon       = Icons.account_balance_wallet_rounded;
            invLabel      = 'سحب نقدي';
          } else {
            invCardBg     = AppColors.invoiceStatusBackground(inv.paymentStatus);
            invCardBorder = AppColors.invoiceStatusBorder(inv.paymentStatus);
            invAccent     = AppColors.invoiceStatusColor(inv.paymentStatus);
            invIcon       = Icons.receipt_long_rounded;
            invLabel      = '';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: invCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: invCardBorder, width: 1.5),
            ),
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(isMobile ? 14 : 18, isMobile ? 12 : 16, isMobile ? 14 : 18, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Icon badge
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: invAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(invIcon, color: invAccent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  // Details
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (invLabel.isNotEmpty)
                        Text(invLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: invAccent)),
                      // Amount
                      Text('${_fmt(inv.amount)} ₪',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: isMobile ? 16 : 20, color: invAccent)),
                      const SizedBox(height: 2),
                      // Payment method / status
                      if (inv.methodName != null)
                        Text('وسيلة الدفع: ${inv.methodName}',
                            style: TextStyle(color: invAccent.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 11)),
                      // Date
                      Text('التاريخ: ${inv.invoiceDate}',
                          style: TextStyle(color: invAccent.withOpacity(0.6), fontSize: 11)),
                      if (inv.notes != null)
                        Text('ملاحظات: ${inv.notes}',
                            style: TextStyle(fontSize: 11, color: invAccent.withOpacity(0.7), fontStyle: FontStyle.italic)),
                    ]),
                  ),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: invAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isDeposit ? 'سداد' : isWithdrawal ? 'سحب' : _translateStatus(inv.paymentStatus),
                      style: TextStyle(fontSize: 10, color: invAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
              // Bottom accent bar
              Container(
                height: 3,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: invAccent,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
              ),
              _buildInvoiceActions(inv, edited),
            ]),
          );
        },
      ),
      if (hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _invoiceDisplayCount += _invoicePageSize),
            icon: const Icon(Icons.expand_more_rounded, color: Colors.blue),
            label: Text(
              'تحميل المزيد (متبقي ${sorted.length - _invoiceDisplayCount})',
              style: const TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ),
    ]);
  }

  /// Translates payment_status enum to Arabic label.
  String _translateStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':     return 'مدفوع';
      case 'UNPAID':   return 'غير مدفوع';
      case 'DEFERRED': return 'دين';
      default:         return status ?? '-';
    }
  }

  Widget _buildInvoiceActions(Invoice inv, bool edited) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (edited)
          TextButton.icon(
            onPressed: () => _showEditHistory(inv),
            icon: const Icon(Icons.history_rounded, size: 15, color: Colors.purple),
            label: const Text('سجل التعديل',
                style: TextStyle(fontSize: 11, color: Colors.purple)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        if (edited) const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _editInvoice(inv),
          icon: const Icon(Icons.edit_rounded, size: 15, color: Colors.blue),
          label: const Text('تعديل',
              style: TextStyle(fontSize: 11, color: Colors.blue)),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _deleteInvoice(inv),
          icon: const Icon(Icons.delete_rounded, size: 15, color: Colors.red),
          label: const Text('حذف',
              style: TextStyle(fontSize: 11, color: Colors.red)),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ]),
    );
  }
}
