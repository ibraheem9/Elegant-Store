import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'customers_screen.dart';

/// Displays a searchable, sortable table of all customers with their current balance.
class CustomerBalancesScreen extends StatefulWidget {
  const CustomerBalancesScreen({Key? key}) : super(key: key);

  @override
  State<CustomerBalancesScreen> createState() => _CustomerBalancesScreenState();
}

class _CustomerBalancesScreenState extends State<CustomerBalancesScreen> {
  List<User> _allCustomers = [];
  List<User> _filtered = [];
  bool _isLoading = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Sort: 'name_asc' | 'name_desc' | 'balance_asc' | 'balance_desc' | 'date_asc' | 'date_desc'
  String _sortMode = 'name_asc';

  // Pagination
  static const int _pageSize = 20;
  int _displayCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();

    List<User> customers;
    if (auth.isManager()) {
      final all = await db.getCustomers();
      customers = all.where((u) => u.role == 'CUSTOMER' || u.role == 'customer').toList();
    } else {
      customers = await db.getCustomers();
    }

    setState(() {
      _allCustomers = customers;
      _isLoading = false;
      _displayCount = _pageSize;
      _applyFilterAndSort();
    });
  }

  // ── Filtering & sorting ───────────────────────────────────────────────────

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      _displayCount = _pageSize;
      _applyFilterAndSort();
    });
  }

  String _normalizeArabic(String text) {
    return text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .toLowerCase();
  }

  void _applyFilterAndSort() {
    List<User> result = List.from(_allCustomers);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _normalizeArabic(_searchQuery);
      result = result.where((c) {
        final name = _normalizeArabic(c.name);
        final nick = _normalizeArabic(c.nickname ?? '');
        return name.contains(q) || nick.contains(q);
      }).toList();
    }

    // Sort
    switch (_sortMode) {
      case 'name_asc':
        result.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'name_desc':
        result.sort((a, b) => b.name.compareTo(a.name));
        break;
      case 'balance_asc':
        result.sort((a, b) => a.balance.compareTo(b.balance));
        break;
      case 'balance_desc':
        result.sort((a, b) => b.balance.compareTo(a.balance));
        break;
      case 'date_asc':
        result.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
        break;
      case 'date_desc':
        result.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
        break;
    }

    _filtered = result;
  }

  void _setSortMode(String mode) {
    setState(() {
      _sortMode = mode;
      _displayCount = _pageSize;
      _applyFilterAndSort();
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateToDetails(User customer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
    ).then((_) => _loadCustomers());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 650;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCustomers,
              child: Column(
                children: [
                  _buildTopBar(isDark, isMobile),
                  Expanded(child: _buildTable(isDark, isMobile)),
                ],
              ),
            ),
    );
  }

  // ── Top bar: search + sort ─────────────────────────────────────────────────

  Widget _buildTopBar(bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Sort button
          PopupMenuButton<String>(
            tooltip: 'ترتيب',
            onSelected: _setSortMode,
            itemBuilder: (_) => [
              _sortMenuItem('name_asc', 'أبجدي (أ → ي)', Icons.sort_by_alpha_rounded),
              _sortMenuItem('name_desc', 'أبجدي (ي → أ)', Icons.sort_by_alpha_rounded),
              const PopupMenuDivider(),
              _sortMenuItem('balance_asc', 'الرصيد (الأقل أولاً)', Icons.arrow_upward_rounded),
              _sortMenuItem('balance_desc', 'الرصيد (الأعلى أولاً)', Icons.arrow_downward_rounded),
              const PopupMenuDivider(),
              _sortMenuItem('date_asc', 'تاريخ الإضافة (الأقدم)', Icons.calendar_today_rounded),
              _sortMenuItem('date_desc', 'تاريخ الإضافة (الأحدث)', Icons.calendar_today_rounded),
            ],
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
                  const SizedBox(width: 6),
                  Text('ترتيب', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Refresh button
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCustomers,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(String value, String label, IconData icon) {
    final isActive = _sortMode == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isActive ? Colors.blue : null),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.blue : null)),
        ],
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTable(bool isDark, bool isMobile) {
    final displayed = _filtered.take(_displayCount).toList();
    final hasMore = _filtered.length > _displayCount;

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'لا توجد نتائج للبحث' : 'لا يوجد زبائن حالياً',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      children: [
        // Summary row
        _buildSummaryRow(isDark),
        const SizedBox(height: 12),
        // Table
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                // Table header
                _buildTableHeader(isDark),
                const Divider(height: 1),
                // Table rows
                ...displayed.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final customer = entry.value;
                  return Column(
                    children: [
                      _buildTableRow(customer, idx, isDark),
                      if (idx < displayed.length - 1)
                        Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        // Load more
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: TextButton.icon(
              onPressed: () => setState(() => _displayCount += _pageSize),
              icon: const Icon(Icons.expand_more_rounded, color: Colors.blue),
              label: Text(
                'تحميل المزيد (متبقي ${_filtered.length - _displayCount})',
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSummaryRow(bool isDark) {
    final totalCustomers = _filtered.length;
    final debtors = _filtered.where((c) => c.balance > 0).length;
    final creditors = _filtered.where((c) => c.balance < 0).length;
    final totalDebt = _filtered.fold<double>(0, (sum, c) => sum + (c.balance > 0 ? c.balance : 0));

    return Row(
      children: [
        _summaryChip(Icons.people_alt_rounded, '$totalCustomers زبون', Colors.blue, isDark),
        const SizedBox(width: 8),
        _summaryChip(Icons.trending_up_rounded, '$debtors مدين', Colors.orange, isDark),
        const SizedBox(width: 8),
        _summaryChip(Icons.trending_down_rounded, '$creditors دائن', Colors.green, isDark),
        const SizedBox(width: 8),
        Flexible(
          child: _summaryChip(
            Icons.account_balance_wallet_rounded,
            'إجمالي الديون: ${totalDebt.toStringAsFixed(2)} ₪',
            Colors.red,
            isDark,
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white70 : Colors.black54,
    );
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Row number
          SizedBox(width: 36, child: Text('#', style: textStyle, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          // Name column
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _setSortMode(_sortMode == 'name_asc' ? 'name_desc' : 'name_asc'),
              child: Row(
                children: [
                  Text('اسم الزبون', style: textStyle),
                  const SizedBox(width: 4),
                  Icon(
                    _sortMode == 'name_asc'
                        ? Icons.arrow_upward_rounded
                        : _sortMode == 'name_desc'
                            ? Icons.arrow_downward_rounded
                            : Icons.unfold_more_rounded,
                    size: 14,
                    color: (_sortMode == 'name_asc' || _sortMode == 'name_desc') ? Colors.blue : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Balance column
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _setSortMode(_sortMode == 'balance_desc' ? 'balance_asc' : 'balance_desc'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    _sortMode == 'balance_asc'
                        ? Icons.arrow_upward_rounded
                        : _sortMode == 'balance_desc'
                            ? Icons.arrow_downward_rounded
                            : Icons.unfold_more_rounded,
                    size: 14,
                    color: (_sortMode == 'balance_asc' || _sortMode == 'balance_desc') ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text('الرصيد', style: textStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(User customer, int index, bool isDark) {
    final balance = customer.balance;
    final isDebt = balance > 0;
    final isCredit = balance < 0;

    Color balanceColor;
    String balanceLabel;
    if (isDebt) {
      balanceColor = Colors.orange;
      balanceLabel = '${balance.toStringAsFixed(2)} ₪';
    } else if (isCredit) {
      balanceColor = Colors.green;
      balanceLabel = '${balance.abs().toStringAsFixed(2)} ₪-';
    } else {
      balanceColor = isDark ? Colors.white38 : Colors.grey;
      balanceLabel = '0.00 ₪';
    }

    return InkWell(
      onTap: () => _navigateToDetails(customer),
      borderRadius: BorderRadius.circular(0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Row number
            SizedBox(
              width: 36,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            // Name + badge
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // Avatar circle
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        customer.name.isNotEmpty ? customer.name[0] : '?',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customer.nickname != null && customer.nickname!.isNotEmpty)
                          Text(
                            customer.nickname!,
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (customer.isPermanentCustomer == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: const Text('دائم', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            // Balance
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    balanceLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: balanceColor,
                    ),
                  ),
                  if (isDebt)
                    const Text('مدين', style: TextStyle(fontSize: 10, color: Colors.orange))
                  else if (isCredit)
                    const Text('رصيد لدينا', style: TextStyle(fontSize: 10, color: Colors.green))
                  else
                    Text('مسوّى', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey)),
                ],
              ),
            ),
            // Arrow
            const SizedBox(width: 8),
            Icon(Icons.chevron_left_rounded, size: 18, color: isDark ? Colors.white24 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
