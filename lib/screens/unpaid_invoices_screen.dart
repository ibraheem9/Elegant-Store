import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';
// UnpaidRow is defined in models.dart

/// Date-range filter options shown in the dropdown.
enum _DateFilter { all, today, week, month, year, custom }

extension _DateFilterLabel on _DateFilter {
  String get label {
    switch (this) {
      case _DateFilter.all:    return 'كل الفترات';
      case _DateFilter.today:  return 'اليوم';
      case _DateFilter.week:   return 'هذا الأسبوع';
      case _DateFilter.month:  return 'هذا الشهر';
      case _DateFilter.year:   return 'هذه السنة';
      case _DateFilter.custom: return 'تاريخ محدد';
    }
  }
}

class UnpaidInvoicesScreen extends StatefulWidget {
  const UnpaidInvoicesScreen({Key? key}) : super(key: key);

  @override
  State<UnpaidInvoicesScreen> createState() => _UnpaidInvoicesScreenState();
}

class _UnpaidInvoicesScreenState extends State<UnpaidInvoicesScreen> {
  // ── State ────────────────────────────────────────────────────────────────────
  List<UnpaidRow> _allRows    = [];
  List<UnpaidRow> _filtered   = [];
  bool             _loading    = true;

  final TextEditingController _searchCtrl = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.all;
  DateTime?   _customDate;

  // Pagination
  static const int _pageSize = 20;
  int _displayCount = _pageSize;
  final ScrollController _scrollCtrl = ScrollController();

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_applyFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = context.read<DatabaseService>();
    final List<UnpaidRow> rows = await db.getUnpaidInvoicesWithBalance();
    if (!mounted) return;
    setState(() {
      _allRows  = rows;
      _loading  = false;
    });
    _applyFilters();
  }

  // ── Filtering ─────────────────────────────────────────────────────────────────
  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();

    // Date window
    DateTime? windowStart;
    DateTime? windowEnd;
    final now = DateTime.now();

    switch (_dateFilter) {
      case _DateFilter.today:
        windowStart = DateTime(now.year, now.month, now.day);
        windowEnd   = windowStart.add(const Duration(days: 1));
        break;
      case _DateFilter.week:
        final weekday = now.weekday % 7; // Sunday = 0
        windowStart = DateTime(now.year, now.month, now.day - weekday);
        windowEnd   = windowStart.add(const Duration(days: 7));
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
          windowStart = DateTime(_customDate!.year, _customDate!.month, _customDate!.day);
          windowEnd   = windowStart!.add(const Duration(days: 1));
        }
        break;
      case _DateFilter.all:
        break;
    }

    List<UnpaidRow> result = _allRows.where((row) {
      // Date filter (based on invoice created_at)
      if (windowStart != null) {
        DateTime? dt;
        try { dt = DateTime.parse(row.invoice.createdAt); } catch (_) {}
        if (dt == null) return false;
        if (dt.isBefore(windowStart)) return false;
        if (windowEnd != null && !dt.isBefore(windowEnd)) return false;
      }
      // Text search
      if (q.isNotEmpty) {
        final inv = row.invoice;
        final haystack = [
          row.customerName,
          row.customerNickname,
          inv.amount.toString(),
          inv.invoiceDate,
          inv.notes ?? '',
          inv.methodName ?? '',
          _statusLabel(inv.paymentStatus),
          _typeLabel(inv.type),
          row.balance.toString(),
        ].join(' ').toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();

    // Sort: highest balance first, then by date desc
    result.sort((UnpaidRow a, UnpaidRow b) {
      final cmp = b.balance.compareTo(a.balance);
      if (cmp != 0) return cmp;
      return b.invoice.createdAt.compareTo(a.invoice.createdAt);
    });

    setState(() {
      _filtered     = result;
      _displayCount = _pageSize;
    });
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (_displayCount < _filtered.length) {
        setState(() => _displayCount = (_displayCount + _pageSize).clamp(0, _filtered.length));
      }
    }
  }

  // ── Date filter picker ────────────────────────────────────────────────────────
  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _customDate  = picked;
        _dateFilter  = _DateFilter.custom;
      });
      _applyFilters();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  String _statusLabel(String s) {
    switch (s.toUpperCase()) {
      case 'UNPAID':    return 'غير مدفوع';
      case 'DEFERRED':  return 'مؤجل';
      case 'PARTIAL':   return 'جزئي';
      default:          return s;
    }
  }

  String _typeLabel(String t) {
    switch (t.toUpperCase()) {
      case 'SALE':       return 'دين';
      case 'DEPOSIT':    return 'سداد';
      case 'WITHDRAWAL': return 'سحب';
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
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  // ── Summary totals ────────────────────────────────────────────────────────────
  double get _totalUnpaidAmount =>
      _filtered.fold<double>(0.0, (s, r) => s + r.invoice.amount);

  double get _totalBalance =>
      _filtered.fold<double>(0.0, (s, r) => s + (r.balance > 0 ? r.balance : 0));

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

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
                    ? _buildEmpty(isDark)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                          itemCount: _displayCount.clamp(0, _filtered.length) +
                              (_displayCount < _filtered.length ? 1 : 0),
                          itemBuilder: (BuildContext context, int i) {
                            if (i == _displayCount.clamp(0, _filtered.length)) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _buildCard(_filtered[i], cardBg, isDark);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Top bar: search + date filter ────────────────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final fillColor   = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون، المبلغ، الملاحظات...',
                  hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, size: 18, color: isDark ? Colors.white38 : Colors.grey),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () { _searchCtrl.clear(); _applyFilters(); },
                        )
                      : null,
                  filled: true,
                  fillColor: fillColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blue)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Date filter dropdown
          _buildDateDropdown(isDark),
        ],
      ),
    );
  }

  Widget _buildDateDropdown(bool isDark) {
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final fillColor   = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor   = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: _dateFilter != _DateFilter.all ? Colors.blue : borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_DateFilter>(
          value: _dateFilter,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: textColor),
          isDense: true,
          style: TextStyle(fontSize: 12, color: textColor, fontFamily: 'Cairo'),
          items: _DateFilter.values.map((f) {
            return DropdownMenuItem(
              value: f,
              child: Text(f.label, style: TextStyle(fontSize: 12, color: textColor)),
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
    final count = _filtered.length;
    return Container(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _summaryChip(
            icon: Icons.receipt_long_rounded,
            label: 'فاتورة',
            value: '$count',
            color: Colors.blue,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _summaryChip(
            icon: Icons.attach_money_rounded,
            label: 'إجمالي الفواتير',
            value: '${_totalUnpaidAmount.toStringAsFixed(2)} ₪',
            color: Colors.red,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _summaryChip(
            icon: Icons.account_balance_wallet_rounded,
            label: 'إجمالي الديون',
            value: '${_totalBalance.toStringAsFixed(2)} ₪',
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
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label, style: TextStyle(fontSize: 10, color: color), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Invoice card ──────────────────────────────────────────────────────────────
  Widget _buildCard(UnpaidRow row, Color cardBg, bool isDark) {
    final inv          = row.invoice;
    final statusColor  = _statusColor(inv.paymentStatus);
    final balanceColor = row.balance > 0 ? Colors.red : row.balance < 0 ? Colors.green : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: customer name + status badge ──────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.customerName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge(_statusLabel(inv.paymentStatus), statusColor),
                const SizedBox(width: 6),
                _badge(_typeLabel(inv.type), Colors.blueGrey),
              ],
            ),
            if (row.customerNickname != null && row.customerNickname!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                row.customerNickname!,
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            // ── Row 2: amount + balance ──────────────────────────────────────
            Row(
              children: [
                // Invoice amount
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
                // Customer balance
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
            // ── Row 3: date + payment method ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _infoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'تاريخ الفاتورة',
                    value: inv.invoiceDate.isNotEmpty ? inv.invoiceDate : _formatDate(inv.createdAt),
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
            // ── Row 4: notes (if any) ────────────────────────────────────────
            if (inv.notes != null && inv.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.notes_outlined, size: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      inv.notes!,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
            // ── Row 5: created_at timestamp ──────────────────────────────────
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.access_time, size: 11, color: isDark ? Colors.white24 : Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(
                  _formatDate(inv.createdAt),
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white24 : Colors.grey.shade400),
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
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
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
            Icon(icon, size: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? (isDark ? Colors.white : Colors.black87),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 72, color: Colors.green.shade400),
          const SizedBox(height: 16),
          Text(
            'لا توجد فواتير غير مدفوعة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            _searchCtrl.text.isNotEmpty || _dateFilter != _DateFilter.all
                ? 'لا توجد نتائج تطابق البحث أو الفلتر المحدد'
                : 'جميع الفواتير مدفوعة',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

