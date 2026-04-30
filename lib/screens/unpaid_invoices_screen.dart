import '../utils/timestamp_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';

// ── Date-range filter ─────────────────────────────────────────────────────────
enum _DateFilter { all, today, week, month, year, custom }

extension _DateFilterLabel on _DateFilter {
  String get label {
    switch (this) {
      case _DateFilter.all:    return 'كل الفترات';
      case _DateFilter.today:  return 'اليوم';
      case _DateFilter.week:   return 'آخر 7 أيام';
      case _DateFilter.month:  return 'هذا الشهر';
      case _DateFilter.year:   return 'هذه السنة';
      case _DateFilter.custom: return 'تاريخ محدد';
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class UnpaidInvoicesScreen extends StatefulWidget {
  const UnpaidInvoicesScreen({Key? key}) : super(key: key);

  @override
  State<UnpaidInvoicesScreen> createState() => _UnpaidInvoicesScreenState();
}

class _UnpaidInvoicesScreenState extends State<UnpaidInvoicesScreen> {
  // ── Data ──────────────────────────────────────────────────────────────────────
  /// All UNPAID/DEFERRED rows fetched from DB (never mutated after load).
  List<UnpaidRow> _allRows  = [];
  /// Subset after applying search + date filter.
  List<UnpaidRow> _filtered = [];
  bool _loading = true;

  // ── Search & filter ───────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.all;
  DateTime?   _customDate;

  // ── Pagination ────────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
  /// Number of items currently visible in the list.
  int _visibleCount = _pageSize;
  final ScrollController _scrollCtrl = ScrollController();

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load from DB ──────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = context.read<DatabaseService>();
    // DB query already returns ONLY UNPAID / DEFERRED invoices.
    final rows = await db.getUnpaidInvoicesWithBalance();
    if (!mounted) return;
    setState(() {
      _allRows = rows;
      _loading = false;
    });
    _applyFilters();
  }

  // ── Filtering ─────────────────────────────────────────────────────────────────
  void _onSearchChanged() => _applyFilters();

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();

    // Build date window
    DateTime? windowStart;
    DateTime? windowEnd;
    final now = DateTime.now();

    switch (_dateFilter) {
      case _DateFilter.today:
        windowStart = DateTime(now.year, now.month, now.day);
        windowEnd   = windowStart.add(const Duration(days: 1));
        break;
      case _DateFilter.week:
        // Last 7 days (today + 6 previous days)
        windowStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        windowEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _DateFilter.month:
        windowStart = DateTime(now.year, now.month, 1);
        windowEnd   = DateTime(now.year, now.month + 1, 1);
        break;
      case _DateFilter.year:
        windowStart = DateTime(now.year, 1, 1);
        windowEnd   = DateTime(now.year + 1, 1, 1);
        break;
      case _DateFilter.custom:
        if (_customDate != null) {
          windowStart = DateTime(
              _customDate!.year, _customDate!.month, _customDate!.day);
          windowEnd = windowStart!.add(const Duration(days: 1));
        }
        break;
      case _DateFilter.all:
        break;
    }

    final result = _allRows.where((row) {
      // ── Date filter ────────────────────────────────────────────────────────
      if (windowStart != null) {
        DateTime? dt;
        try {
          dt = DateTime.parse(row.invoice.createdAt).toLocal();
        } catch (_) {}
        if (dt == null) return false;
        if (dt.isBefore(windowStart)) return false;
        if (windowEnd != null && !dt.isBefore(windowEnd)) return false;
      }

      // ── Text search ────────────────────────────────────────────────────────
      if (query.isNotEmpty) {
        final inv = row.invoice;
        final haystack = [
          row.customerName,
          row.customerNickname ?? '',
          inv.amount.toStringAsFixed(2),
          inv.invoiceDate,
          inv.notes ?? '',
          inv.methodName ?? '',
          _statusLabel(inv.paymentStatus),
          _typeLabel(inv.type),
          row.balance.toStringAsFixed(2),
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }

      return true;
    }).toList();

    // Sort: highest positive balance first, then newest first
    result.sort((a, b) {
      final cmp = b.balance.compareTo(a.balance);
      if (cmp != 0) return cmp;
      return b.invoice.createdAt.compareTo(a.invoice.createdAt);
    });

    setState(() {
      _filtered     = result;
      _visibleCount = _pageSize; // reset pagination on every filter change
    });
  }

  // ── Pagination ────────────────────────────────────────────────────────────────
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // Load next page when user is within 300px of the bottom
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    if (_visibleCount >= _filtered.length) return; // already showing all
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(0, _filtered.length);
    });
  }

  // ── Date picker ───────────────────────────────────────────────────────────────
  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _customDate = picked;
        _dateFilter = _DateFilter.custom;
      });
      _applyFilters();
    }
  }

  // ── Label helpers ─────────────────────────────────────────────────────────────
  String _statusLabel(String s) {
    switch (s.toUpperCase()) {
      case 'UNPAID':   return 'غير مدفوع';
      case 'DEFERRED': return 'مؤجل';
      case 'PARTIAL':  return 'جزئي';
      default:         return s;
    }
  }

  String _typeLabel(String t) {
    switch (t.toUpperCase()) {
      case 'SALE':       return 'دين';
      case 'WITHDRAWAL': return 'سحب';
      case 'DEPOSIT':    return 'سداد';
      default:           return t;
    }
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'UNPAID':   return Colors.red;
      case 'DEFERRED': return Colors.orange;
      case 'PARTIAL':  return Colors.amber;
      default:         return Colors.grey;
    }
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  // ── Summary totals ────────────────────────────────────────────────────────────
  double get _totalInvoiceAmount =>
      _filtered.fold<double>(0.0, (acc, r) => acc + r.invoice.amount);

  double get _totalPositiveBalance =>
      _filtered.fold<double>(0.0, (acc, r) => acc + (r.balance > 0 ? r.balance : 0.0));

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg  = isDark ? const Color(0xFF1E293B) : Colors.white;

    // Slice of _filtered that is currently visible
    final visibleItems = _filtered.take(_visibleCount).toList();
    final hasMore      = _visibleCount < _filtered.length;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildTopBar(isDark),
          _buildSummaryBar(isDark),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _buildEmptyState(isDark)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                          // +1 for the "load more" indicator at the bottom
                          itemCount: visibleItems.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Last item = loading indicator when more pages exist
                            if (index == visibleItems.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return _buildCard(visibleItems[index], cardBg, isDark);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final fillColor   = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          // ── Search field ────────────────────────────────────────────────────
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون، المبلغ، الملاحظات...',
                  hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: fillColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blue)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Date filter dropdown ────────────────────────────────────────────
          _buildDateDropdown(isDark, borderColor, fillColor),
        ],
      ),
    );
  }

  Widget _buildDateDropdown(
      bool isDark, Color borderColor, Color fillColor) {
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;
    final isActive  = _dateFilter != _DateFilter.all;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: isActive ? Colors.blue : borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_DateFilter>(
          value: _dateFilter,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: textColor),
          isDense: true,
          style: TextStyle(
              fontSize: 12, color: textColor, fontFamily: 'Cairo'),
          items: _DateFilter.values.map((f) {
            return DropdownMenuItem(
              value: f,
              child: Text(f.label,
                  style: TextStyle(fontSize: 12, color: textColor)),
            );
          }).toList(),
          onChanged: (val) async {
            if (val == null) return;
            if (val == _DateFilter.custom) {
              await _pickCustomDate();
            } else {
              setState(() {
                _dateFilter = val;
                _customDate = null;
              });
              _applyFilters();
            }
          },
        ),
      ),
    );
  }

  // ── Summary bar ───────────────────────────────────────────────────────────────
  Widget _buildSummaryBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _summaryChip(
            icon: Icons.receipt_long_rounded,
            label: 'فاتورة',
            value: '${_filtered.length}',
            color: Colors.blue,
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          _summaryChip(
            icon: Icons.attach_money_rounded,
            label: 'إجمالي الفواتير',
            value: '${_totalInvoiceAmount.toStringAsFixed(2)} ₪',
            color: Colors.red,
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          _summaryChip(
            icon: Icons.account_balance_wallet_rounded,
            label: 'إجمالي الديون',
            value: '${_totalPositiveBalance.toStringAsFixed(2)} ₪',
            color: Colors.orange,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(label,
                      style: TextStyle(fontSize: 10, color: color),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Invoice card ──────────────────────────────────────────────────────────────
  Widget _buildCard(UnpaidRow row, Color cardBg, bool isDark) {
    final inv         = row.invoice;
    final statusColor = _statusColor(inv.paymentStatus);
    final balanceColor = row.balance > 0
        ? Colors.red.shade700
        : row.balance < 0
            ? Colors.green.shade700
            : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Customer name + badges ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.customerName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge(_statusLabel(inv.paymentStatus), statusColor),
                const SizedBox(width: 6),
                _badge(_typeLabel(inv.type), Colors.blueGrey),
              ],
            ),
            if (row.customerNickname != null &&
                row.customerNickname!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                row.customerNickname!,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            // ── Amount + balance ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    icon: Icons.receipt_outlined,
                    label: 'مبلغ الفاتورة',
                    value: '${inv.amount.toStringAsFixed(2)} ₪',
                    valueColor: Colors.red.shade700,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _infoTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'رصيد الزبون',
                    value: '${row.balance.toStringAsFixed(2)} ₪',
                    valueColor: balanceColor,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Invoice date + payment method ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'تاريخ الفاتورة',
                    value: inv.invoiceDate.isNotEmpty
                        ? inv.invoiceDate
                        : inv.createdAt.toLocalShort(),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _infoTile(
                    icon: Icons.payment_outlined,
                    label: 'طريقة الدفع',
                    value: inv.methodName ?? '—',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            // ── Notes ─────────────────────────────────────────────────────────
            if (inv.notes != null && inv.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.notes_outlined,
                      size: 13,
                      color: isDark ? Colors.white38 : Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      inv.notes!,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white54
                              : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
            // ── Created-at timestamp ──────────────────────────────────────────
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.access_time,
                    size: 11,
                    color: isDark ? Colors.white24 : Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(
                  inv.createdAt.toLocalShort(),
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white24 : Colors.grey.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: 11,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
            const SizedBox(width: 3),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ??
                  (isDark ? Colors.white : Colors.black87)),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    final isFiltered =
        _searchCtrl.text.isNotEmpty || _dateFilter != _DateFilter.all;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered
                ? Icons.search_off_rounded
                : Icons.check_circle_outline_rounded,
            size: 72,
            color: isFiltered ? Colors.grey : Colors.green.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered
                ? 'لا توجد نتائج'
                : 'لا توجد فواتير غير مدفوعة',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'لا توجد فواتير تطابق البحث أو الفلتر المحدد'
                : 'جميع الفواتير مدفوعة ✓',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
