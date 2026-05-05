import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import '../utils/timestamp_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Date filter enum
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class UnpaidInvoicesScreen extends StatefulWidget {
  const UnpaidInvoicesScreen({Key? key}) : super(key: key);

  @override
  State<UnpaidInvoicesScreen> createState() => _UnpaidInvoicesScreenState();
}

class _UnpaidInvoicesScreenState extends State<UnpaidInvoicesScreen> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<UnpaidRow> _allRows   = [];
  List<UnpaidRow> _filtered  = [];
  bool            _loading   = true;

  // ── Search & filter ───────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.all;
  DateTime?   _customDate;

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final rows = await context.read<DatabaseService>().getUnpaidInvoicesWithBalance();
    if (!mounted) return;
    setState(() {
      _allRows  = rows;
      _loading  = false;
    });
    _applyFilters();
  }

  // ── Filtering ─────────────────────────────────────────────────────────────
  void _onSearchChanged() => _applyFilters();

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final window = _buildDateWindow();

    final result = _allRows.where((row) {
      if (!_matchesDateWindow(row, window)) return false;
      if (query.isNotEmpty && !_matchesQuery(row, query)) return false;
      return true;
    }).toList()
      ..sort(_compareRows);

    setState(() {
      _filtered     = result;
      _visibleCount = _pageSize;
    });
  }

  /// Returns [start, end] date window for the active filter, or null for "all".
  ({DateTime start, DateTime end})? _buildDateWindow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eod   = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_dateFilter) {
      case _DateFilter.today:
        return (start: today, end: eod);
      case _DateFilter.week:
        return (start: today.subtract(const Duration(days: 6)), end: eod);
      case _DateFilter.month:
        return (start: DateTime(now.year, now.month, 1), end: eod);
      case _DateFilter.year:
        return (start: DateTime(now.year, 1, 1), end: eod);
      case _DateFilter.custom:
        if (_customDate != null) {
          final d = _customDate!;
          return (
            start: DateTime(d.year, d.month, d.day),
            end:   DateTime(d.year, d.month, d.day, 23, 59, 59),
          );
        }
        return null;
      case _DateFilter.all:
        return null;
    }
  }

  bool _matchesDateWindow(
    UnpaidRow row,
    ({DateTime start, DateTime end})? window,
  ) {
    if (window == null) return true;
    final inv = row.invoice;
    final raw = inv.invoiceDate.isNotEmpty ? inv.invoiceDate : inv.createdAt;
    final dt  = TimestampFormatter.toLocalDateTime(raw);
    return !dt.isBefore(window.start) && !dt.isAfter(window.end);
  }

  bool _matchesQuery(UnpaidRow row, String query) {
    final inv = row.invoice;
    final haystack = [
      row.customerName,
      row.customerNickname ?? '',
      inv.amount.toStringAsFixed(2),
      inv.invoiceDate,
      inv.createdAt,
      inv.notes ?? '',
      inv.methodName ?? '',
      _statusLabel(inv.paymentStatus),
      row.balance.toStringAsFixed(2),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  int _compareRows(UnpaidRow a, UnpaidRow b) {
    final cmp = b.balance.compareTo(a.balance);
    if (cmp != 0) return cmp;
    return b.invoice.createdAt.compareTo(a.invoice.createdAt);
  }

  // ── Pagination ────────────────────────────────────────────────────────────
  void _loadNextPage() {
    if (_visibleCount >= _filtered.length) return;
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(0, _filtered.length);
    });
  }

  // ── Date picker ───────────────────────────────────────────────────────────
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

  // ── Computed properties ───────────────────────────────────────────────────
  double get _totalInvoiceAmount =>
      _filtered.fold(0.0, (acc, r) => acc + r.invoice.amount);

  double get _totalDebt =>
      _filtered.fold(0.0, (acc, r) => acc + (r.balance > 0 ? r.balance : 0.0));

  String get _activeDateLabel {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');

    switch (_dateFilter) {
      case _DateFilter.all:
        return 'كل الفترات';
      case _DateFilter.today:
        return 'اليوم – ${pad(now.day)}-${pad(now.month)}-${now.year}';
      case _DateFilter.week:
        final start = now.subtract(const Duration(days: 6));
        return '${pad(start.day)}-${pad(start.month)}-${start.year} → ${pad(now.day)}-${pad(now.month)}-${now.year}';
      case _DateFilter.month:
        return 'شهر ${pad(now.month)}-${now.year}';
      case _DateFilter.year:
        return 'سنة ${now.year}';
      case _DateFilter.custom:
        if (_customDate != null) {
          final d = _customDate!;
          return '${pad(d.day)}-${pad(d.month)}-${d.year}';
        }
        return 'تاريخ محدد';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _statusLabel(String s) {
    switch (s.toUpperCase()) {
      case 'UNPAID':   return 'غير مدفوع';
      case 'DEFERRED': return 'مؤجل';
      case 'PARTIAL':  return 'جزئي';
      default:         return s;
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

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            searchCtrl: _searchCtrl,
            dateFilter: _dateFilter,
            isDark: isDark,
            onFilterChanged: (filter) async {
              if (filter == _DateFilter.custom) {
                await _pickCustomDate();
              } else {
                setState(() {
                  _dateFilter = filter;
                  _customDate = null;
                });
                _applyFilters();
              }
            },
          ),
          _SummaryBar(
            count:        _filtered.length,
            totalAmount:  _totalInvoiceAmount,
            totalDebt:    _totalDebt,
            isDark:       isDark,
          ),
          if (!_loading && _filtered.isNotEmpty)
            _FilterLabel(
              label:    _activeDateLabel,
              count:    _filtered.length,
              hasMore:  _visibleCount < _filtered.length,
              onLoadMore: _loadNextPage,
              isDark:   isDark,
            ),
          Expanded(
            child: _buildBody(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_filtered.isEmpty) {
      return _EmptyState(
        isFiltered: _searchCtrl.text.isNotEmpty || _dateFilter != _DateFilter.all,
        isDark: isDark,
      );
    }

    final visibleItems = _filtered.take(_visibleCount).toList();
    final hasMore      = _visibleCount < _filtered.length;
    final cardBg       = isDark ? const Color(0xFF1E293B) : Colors.white;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
        itemCount: visibleItems.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == visibleItems.length) {
            return _LoadMoreButton(
              remaining: _filtered.length - visibleItems.length,
              onTap: _loadNextPage,
            );
          }
          return _InvoiceCard(
            row:      visibleItems[index],
            index:    index + 1,
            cardBg:   cardBg,
            isDark:   isDark,
            statusLabel: _statusLabel,
            statusColor: _statusColor,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (stateless, extracted for performance & readability)
// ─────────────────────────────────────────────────────────────────────────────

/// Top search bar + date filter dropdown.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchCtrl,
    required this.dateFilter,
    required this.isDark,
    required this.onFilterChanged,
  });

  final TextEditingController searchCtrl;
  final _DateFilter dateFilter;
  final bool isDark;
  final ValueChanged<_DateFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final border    = isDark ? Colors.white12 : Colors.grey.shade300;
    final fillColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: searchCtrl,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون، المبلغ، الملاحظات...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  prefixIcon: Icon(Icons.search,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.grey),
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: searchCtrl.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: fillColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(
                color: dateFilter != _DateFilter.all ? Colors.blue : border,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_DateFilter>(
                value: dateFilter,
                icon: Icon(Icons.keyboard_arrow_down,
                    size: 20, color: textColor),
                isDense: true,
                style: TextStyle(
                    fontSize: 14, color: textColor, fontFamily: 'Cairo'),
                items: _DateFilter.values
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.label,
                              style: TextStyle(
                                  fontSize: 14, color: textColor)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) onFilterChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three summary chips: count, total amount, total debt.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.count,
    required this.totalAmount,
    required this.totalDebt,
    required this.isDark,
  });

  final int    count;
  final double totalAmount;
  final double totalDebt;
  final bool   isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _Chip(
            icon:  Icons.receipt_long_rounded,
            label: 'فاتورة',
            value: '$count',
            color: Colors.blue,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _Chip(
            icon:  Icons.attach_money_rounded,
            label: 'إجمالي الفواتير',
            value: '${totalAmount.toStringAsFixed(2)} ₪',
            color: Colors.red,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _Chip(
            icon:  Icons.account_balance_wallet_rounded,
            label: 'إجمالي الديون',
            value: '${totalDebt.toStringAsFixed(2)} ₪',
            color: Colors.orange,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final bool     isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter label bar showing active date range and optional load-more button.
class _FilterLabel extends StatelessWidget {
  const _FilterLabel({
    required this.label,
    required this.count,
    required this.hasMore,
    required this.onLoadMore,
    required this.isDark,
  });

  final String   label;
  final int      count;
  final bool     hasMore;
  final VoidCallback onLoadMore;
  final bool     isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded,
              size: 14,
              color: isDark ? Colors.white54 : Colors.grey.shade500),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$label  ($count)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.grey.shade700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasMore)
            GestureDetector(
              onTap: onLoadMore,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('تحميل المزيد',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600)),
                    SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down,
                        size: 15, color: Colors.blue),
                  ],
                ),
              ),
            )
          else
            Text(
              'تم عرض الكل ✓',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}

/// Large load-more button shown at the bottom of the list.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.remaining, required this.onTap});

  final int        remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.expand_more_rounded, size: 20),
          label: Text(
            'تحميل المزيد ($remaining)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}

/// Empty state widget.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFiltered, required this.isDark});

  final bool isFiltered;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered
                ? Icons.search_off_rounded
                : Icons.check_circle_outline_rounded,
            size: 64,
            color: isFiltered
                ? (isDark ? Colors.white24 : Colors.grey.shade300)
                : Colors.green.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered
                ? 'لا توجد نتائج مطابقة'
                : 'لا توجد فواتير غير مدفوعة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 6),
            Text(
              'جرّب تغيير الفلتر أو مسح البحث',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice card
// ─────────────────────────────────────────────────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.row,
    required this.index,
    required this.cardBg,
    required this.isDark,
    required this.statusLabel,
    required this.statusColor,
  });

  final UnpaidRow  row;
  final int        index;
  final Color      cardBg;
  final bool       isDark;
  final String Function(String) statusLabel;
  final Color  Function(String) statusColor;

  @override
  Widget build(BuildContext context) {
    final inv    = row.invoice;
    final sColor = statusColor(inv.paymentStatus);
    final bColor = row.balance > 0
        ? Colors.red.shade700
        : row.balance < 0
            ? Colors.green.shade700
            : Colors.grey;

    final invoiceDateStr = inv.invoiceDate.isNotEmpty
        ? inv.invoiceDate.toLocalShort()
        : inv.createdAt.toLocalShort();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shadowColor: isDark ? Colors.black38 : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sColor.withOpacity(0.3)),
      ),
      color: cardBg,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Colored left accent bar ──────────────────────────────────
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: sColor,
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(12),
                  bottomLeft:  Radius.circular(12),
                ),
              ),
            ),
            // ── Card content ─────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: index + name + status badge
                    Row(
                      children: [
                        _IndexBadge(index: index, isDark: isDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.customerName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (row.customerNickname != null &&
                                  row.customerNickname!.isNotEmpty)
                                Text(
                                  row.customerNickname!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(
                          label: statusLabel(inv.paymentStatus),
                          color: sColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Row 2: invoice amount + customer balance
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            icon:       Icons.receipt_outlined,
                            label:      'مبلغ الفاتورة',
                            value:      '${inv.amount.toStringAsFixed(2)} ₪',
                            valueColor: Colors.red.shade700,
                            isDark:     isDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoTile(
                            icon:       Icons.account_balance_wallet_outlined,
                            label:      'رصيد الزبون',
                            value:      '${row.balance.toStringAsFixed(2)} ₪',
                            valueColor: bColor,
                            isDark:     isDark,
                          ),
                        ),
                      ],
                    ),
                    // Notes
                    if (inv.notes != null && inv.notes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.notes_outlined,
                              size: 13,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              inv.notes!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Bottom row: invoice date (left) + created-at (right)
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 11,
                            color: isDark ? Colors.white38 : Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          invoiceDateStr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.access_time,
                            size: 11,
                            color: isDark ? Colors.white24 : Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text(
                          inv.createdAt.toLocalShort(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white24 : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small numbered index badge.
class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.isDark});

  final int  index;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white60 : Colors.grey.shade600,
        ),
      ),
    );
  }
}

/// Colored status badge.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Two-column info tile: icon + label + value.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  final IconData icon;
  final String   label;
  final String   value;
  final bool     isDark;
  final Color?   valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ??
                (isDark ? Colors.white : Colors.black87),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Invoice date + payment method row with accent background.
class _DateMethodRow extends StatelessWidget {
  const _DateMethodRow({
    required this.invoiceDateStr,
    required this.methodName,
    required this.accentColor,
    required this.isDark,
  });

  final String  invoiceDateStr;
  final String? methodName;
  final Color   accentColor;
  final bool    isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined,
              size: 15, color: accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تاريخ الفاتورة',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                  ),
                ),
                Text(
                  invoiceDateStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (methodName != null && methodName!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'طريقة الدفع',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                  ),
                ),
                Text(
                  methodName!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
