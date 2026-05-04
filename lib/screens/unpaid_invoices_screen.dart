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
  List<UnpaidRow> _allRows  = [];
  List<UnpaidRow> _filtered = [];
  bool _loading = true;

  // ── Search & filter ───────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.all;
  DateTime?   _customDate;

  // ── Pagination ────────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
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

    DateTime? windowStart;
    DateTime? windowEnd;
    final now = DateTime.now();

    switch (_dateFilter) {
      case _DateFilter.today:
        windowStart = DateTime(now.year, now.month, now.day);
        windowEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _DateFilter.week:
        windowStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        windowEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _DateFilter.month:
        windowStart = DateTime(now.year, now.month, 1);
        windowEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _DateFilter.year:
        windowStart = DateTime(now.year, 1, 1);
        windowEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _DateFilter.custom:
        if (_customDate != null) {
          windowStart = DateTime(_customDate!.year, _customDate!.month, _customDate!.day);
          windowEnd   = DateTime(_customDate!.year, _customDate!.month, _customDate!.day, 23, 59, 59);
        }
        break;
      case _DateFilter.all:
        break;
    }

    final result = _allRows.where((row) {
      if (windowStart != null && windowEnd != null) {
        DateTime? dt;
        final inv = row.invoice;
        if (inv.invoiceDate.isNotEmpty) {
          try { dt = TimestampFormatter.toLocalDateTime(inv.invoiceDate); } catch (_) {}
        }
        if (dt == null) {
          try { dt = TimestampFormatter.toLocalDateTime(inv.createdAt); } catch (_) {}
        }
        if (dt == null) return false;
        final recordDate = DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
        if (recordDate.isBefore(windowStart!) || recordDate.isAfter(windowEnd!)) return false;
      }

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

    result.sort((a, b) {
      final cmp = b.balance.compareTo(a.balance);
      if (cmp != 0) return cmp;
      return b.invoice.createdAt.compareTo(a.invoice.createdAt);
    });

    setState(() {
      _filtered     = result;
      _visibleCount = _pageSize;
    });
  }

  // ── Pagination ────────────────────────────────────────────────────────────────
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    if (_visibleCount >= _filtered.length) return;
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

  String _formatDate(String raw) => TimestampFormatter.formatDateOnly(raw);

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

    final visibleItems = _filtered.take(_visibleCount).toList();
    final hasMore      = _visibleCount < _filtered.length;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildTopBar(isDark),
          _buildSummaryBar(isDark),
          // ── Pagination indicator ──────────────────────────────────────────────
          if (!_loading && _filtered.isNotEmpty)
            _buildPaginationIndicator(isDark),
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
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                          itemCount: visibleItems.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == visibleItems.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Column(
                                  children: [
                                    const CircularProgressIndicator(strokeWidth: 2),
                                    const SizedBox(height: 8),
                                    Text(
                                      'جاري تحميل المزيد...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.white54 : Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return _buildCard(visibleItems[index], index + 1, cardBg, isDark);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Pagination indicator ──────────────────────────────────────────────────────
  Widget _buildPaginationIndicator(bool isDark) {
    final showing = _visibleCount.clamp(0, _filtered.length);
    final total   = _filtered.length;
    final hasMore = showing < total;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'عرض $showing من $total فاتورة',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasMore)
            GestureDetector(
              onTap: _loadNextPage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'تحميل المزيد',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.blue),
                  ],
                ),
              ),
            )
          else
            Text(
              'تم عرض الكل ✓',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green.shade600,
                fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون، المبلغ، الملاحظات...',
                  hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: fillColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
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
          const SizedBox(width: 10),
          _buildDateDropdown(isDark, borderColor, fillColor),
        ],
      ),
    );
  }

  Widget _buildDateDropdown(bool isDark, Color borderColor, Color fillColor) {
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;
    final isActive  = _dateFilter != _DateFilter.all;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: isActive ? Colors.blue : borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_DateFilter>(
          value: _dateFilter,
          icon: Icon(Icons.keyboard_arrow_down, size: 20, color: textColor),
          isDense: true,
          style: TextStyle(fontSize: 14, color: textColor, fontFamily: 'Cairo'),
          items: _DateFilter.values.map((f) {
            return DropdownMenuItem(
              value: f,
              child: Text(f.label, style: TextStyle(fontSize: 14, color: textColor)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _summaryChip(
            icon: Icons.receipt_long_rounded,
            label: 'فاتورة',
            value: '${_filtered.length}',
            color: Colors.blue,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _summaryChip(
            icon: Icons.attach_money_rounded,
            label: 'إجمالي الفواتير',
            value: '${_totalInvoiceAmount.toStringAsFixed(2)} ₪',
            color: Colors.red,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
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
                  child: Text(label,
                      style: TextStyle(fontSize: 12, color: color),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                  fontSize: 14,
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
  Widget _buildCard(UnpaidRow row, int index, Color cardBg, bool isDark) {
    final inv          = row.invoice;
    final statusColor  = _statusColor(inv.paymentStatus);
    final balanceColor = row.balance > 0
        ? Colors.red.shade700
        : row.balance < 0
            ? Colors.green.shade700
            : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Customer name + badge ─────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.customerName,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge(_statusLabel(inv.paymentStatus), statusColor),
              ],
            ),
            if (row.customerNickname != null && row.customerNickname!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                row.customerNickname!,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
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
                const SizedBox(width: 10),
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
            const SizedBox(height: 10),
            // ── Invoice date + payment method ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'تاريخ الفاتورة',
                    value: inv.invoiceDate.isNotEmpty
                        ? inv.invoiceDate.toLocalShort()
                        : inv.createdAt.toLocalShort(),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.notes_outlined,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      inv.notes!,
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
            // ── Created-at timestamp ──────────────────────────────────────────
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.access_time,
                    size: 13,
                    color: isDark ? Colors.white24 : Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  inv.createdAt.toLocalShort(),
                  style: TextStyle(
                      fontSize: 12,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.bold)),
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
                size: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade500),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87)),
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
            size: 80,
            color: isFiltered ? Colors.grey : Colors.green.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'لا توجد نتائج' : 'لا توجد فواتير غير مدفوعة',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'لا توجد فواتير تطابق البحث أو الفلتر المحدد'
                : 'جميع الفواتير مدفوعة ✓',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
