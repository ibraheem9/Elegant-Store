import '../utils/timestamp_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'customers_screen.dart';
import '../widgets/shimmer_loading.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  // ── Date filter ────────────────────────────────────────────────────────────
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate   = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  String _activeFilter = 'today'; // today, week, month, custom

  // ── Data ───────────────────────────────────────────────────────────────────
  List<Invoice> _unpaidInvoices = [];
  List<Invoice> _paidInvoices   = [];
  List<PaymentMethod> _saleMethods = [];
  Map<int, double> _methodTotals  = {};
  bool _isLoading = false;

  // ── Search / sort ──────────────────────────────────────────────────────────
  String _searchQuery = '';
  String _sortBy      = 'date'; // name | date | amount | method
  bool _isAscending   = false;
  int? _selectedMethodId; // null = all

  // ── Pagination ─────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
  int _paidDisplayCount   = _pageSize;
  int _unpaidDisplayCount = _pageSize;

  // ── Transfer (DEPOSIT) section ─────────────────────────────────────────────
  List<Invoice> _transferInvoices = [];

  @override
  void initState() {
    super.initState();
    _setFilter('today');
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  void _setFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _activeFilter = filter;
      if (filter == 'today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'week') {
        // Last 7 days (today + 6 previous days)
        _startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _loadData();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _paidDisplayCount   = _pageSize;
      _unpaidDisplayCount = _pageSize;
    });
    try {
      final db = context.read<DatabaseService>();
      final rawMethods = await db.getPaymentMethods(category: 'SALE');
      final seenIds = <int?>{};
      final methods = rawMethods.where((m) => seenIds.add(m.id)).toList();

      final allInvoices = await db.getInvoices(start: _startDate, end: _endDate);

      // App-method totals (paid invoices only)
      final Map<int, double> totals = {};
      for (final m in methods) {
        if (m.type == 'app') {
          totals[m.id!] = allInvoices
              .where((inv) =>
                  inv.paymentMethodId == m.id &&
                  (inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid'))
              .fold(0.0, (s, inv) => s + inv.amount);
        }
      }

      setState(() {
        _saleMethods    = methods;
        _methodTotals   = totals;

        // Unpaid: non-permanent customers, exclude WITHDRAWAL
        _unpaidInvoices = allInvoices
            .where((inv) =>
                (inv.paymentStatus == 'UNPAID' || inv.paymentStatus == 'pending') &&
                inv.customerIsPermanent == 0 &&
                inv.type != 'WITHDRAWAL')
            .toList();

        // Paid via app method only (all invoice types, exclude WITHDRAWAL)
        final appMethodIds = methods
            .where((m) => m.type == 'app')
            .map((m) => m.id)
            .toSet();
        _paidInvoices = allInvoices
            .where((inv) =>
                (inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid') &&
                inv.type != 'WITHDRAWAL' &&
                appMethodIds.contains(inv.paymentMethodId))
            .toList();
        _transferInvoices = []; // Transfers section removed

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('PaymentsScreen._loadData error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── List processing ────────────────────────────────────────────────────────

  List<Invoice> _processList(List<Invoice> list) {
    List<Invoice> filtered = list;

    if (_selectedMethodId != null) {
      filtered = filtered
          .where((inv) => inv.paymentMethodId == _selectedMethodId)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((inv) =>
              (inv.customerName?.toLowerCase().contains(q) ?? false) ||
              inv.amount.toString().contains(q))
          .toList();
    }

    filtered.sort((a, b) {
      int result = 0;
      switch (_sortBy) {
        case 'name':   result = (a.customerName ?? '').compareTo(b.customerName ?? ''); break;
        case 'date':   result = a.createdAt.compareTo(b.createdAt); break;
        case 'amount': result = a.amount.compareTo(b.amount); break;
        case 'method': result = (a.methodName ?? '').compareTo(b.methodName ?? ''); break;
      }
      return _isAscending ? result : -result;
    });

    return filtered;
  }

  // ── Confirm payment ────────────────────────────────────────────────────────

  Future<void> _confirmPayment(Invoice inv, PaymentMethod selectedMethod) async {
    final db   = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    final ts      = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final editLog = '\n[تمت التسوية: $ts بواسطة ${user?.name ?? 'نظام'}]';
    String notes  = inv.notes ?? '';
    if (notes.contains('[تمت التسوية:')) {
      notes = notes.split('[تمت التسوية:').first.trim();
    }

    final newStatus     = (selectedMethod.type == 'deferred' || selectedMethod.type == 'unpaid') ? 'UNPAID' : 'PAID';
    final newPaidAmount = newStatus == 'PAID' ? inv.amount : 0.0;

    await db.updateInvoice(Invoice(
      id: inv.id, uuid: inv.uuid, storeManagerId: inv.storeManagerId,
      userId: inv.userId, invoiceDate: inv.invoiceDate, amount: inv.amount,
      paidAmount: newPaidAmount, notes: notes + editLog,
      paymentStatus: newStatus, paymentMethodId: selectedMethod.id,
      type: inv.type, version: inv.version, isSynced: 0,
      createdAt: inv.createdAt, updatedAt: TimestampFormatter.nowUtc(),
    ));

    db.logActivity(
      targetId: inv.id!, targetType: 'INVOICE', action: 'UPDATE',
      fieldName: 'تسوية دفع', oldValue: inv.methodName ?? 'غير محدد',
      newValue: selectedMethod.name,
      summary: 'تسوية فاتورة بمبلغ ${inv.amount.toStringAsFixed(2)} ₪ عبر ${selectedMethod.name}',
      performedById: user?.id, performedByName: user?.name,
      storeManagerId: user?.parentId ?? user?.id,
    ).catchError((e) => debugPrint('logActivity failed: $e'));

    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
        const SnackBar(content: Text('تم تسوية الفاتورة بنجاح'), backgroundColor: Colors.green),
      );
    }
  }

  // ── Navigate to customer ───────────────────────────────────────────────────

  Future<void> _navigateToCustomer(int customerId) async {
    final db        = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    try {
      final customer = customers.firstWhere((c) => c.id == customerId);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
        ).then((_) => _loadData());
      }
    } catch (_) {}
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildControlBar(isDark, isMobile),
          Expanded(
            child: _isLoading
                ? ShimmerLoading(isDark: isDark, itemCount: 6)
                : _buildBody(isDark, isMobile),
          ),
        ],
      ),
    );
  }

  // ── Control bar: search + date filter dropdown + sort ──────────────────────

  Widget _buildControlBar(bool isDark, bool isMobile) {
    final border = Border.all(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
    );
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        isMobile ? 12 : 16,
        isMobile ? 12 : 24,
        isMobile ? 8 : 12,
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: radius, border: border),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الزبون أو المبلغ...',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.blue, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Date filter dropdown
          _buildDateFilterDropdown(isDark, bg, border, radius),
          const SizedBox(width: 8),

          // Sort button
          _buildSortButton(isDark, bg, border, radius),
        ],
      ),
    );
  }

  Widget _buildDateFilterDropdown(bool isDark, Color bg, Border border, BorderRadius radius) {
    String label;
    switch (_activeFilter) {
      case 'today':  label = 'اليوم'; break;
      case 'week':   label = 'أسبوع'; break;
      case 'month':  label = 'شهر'; break;
      default:
        label = '${DateFormat('d/M').format(_startDate)}–${DateFormat('d/M').format(_endDate)}';
    }

    return PopupMenuButton<String>(
      tooltip: 'فلترة حسب التاريخ',
      onSelected: (val) async {
        if (val == 'custom') {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime(2101),
            initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
          );
          if (picked != null) {
            setState(() {
              _activeFilter = 'custom';
              _startDate    = picked.start;
              _endDate      = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
            });
            _loadData();
          }
        } else {
          _setFilter(val);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'today',  child: Text('اليوم')),
        const PopupMenuItem(value: 'week',   child: Text('أسبوع')),
        const PopupMenuItem(value: 'month',  child: Text('شهر')),
        const PopupMenuItem(value: 'custom', child: Text('تاريخ محدد')),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg, borderRadius: radius, border: border),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: Colors.blue),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildSortButton(bool isDark, Color bg, Border border, BorderRadius radius) {
    return PopupMenuButton<String>(
      tooltip: 'ترتيب حسب',
      onSelected: (val) {
        setState(() {
          if (_sortBy == val) {
            _isAscending = !_isAscending;
          } else {
            _sortBy      = val;
            _isAscending = true;
          }
        });
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'name',   child: Text('اسم المشتري')),
        const PopupMenuItem(value: 'date',   child: Text('التاريخ')),
        const PopupMenuItem(value: 'amount', child: Text('المبلغ')),
        const PopupMenuItem(value: 'method', child: Text('طريقة الدفع')),
      ],
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(color: bg, borderRadius: radius, border: border),
        child: const Icon(Icons.sort_rounded, color: Colors.blue, size: 18),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(bool isDark, bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        0,
        isMobile ? 12 : 24,
        MediaQuery.of(context).padding.bottom + 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── App payment methods section ──────────────────────────────────
          _buildSectionHeader(
            isDark,
            icon: Icons.account_balance_wallet_rounded,
            title: 'وسائل الدفع الإلكترونية',
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildAppMethodsSection(isDark, isMobile),
          const SizedBox(height: 20),

          // Transfers section removed — all app-paid invoices shown above
        ],
      ),
    );
  }

  Widget _buildSectionHeader(bool isDark, {required IconData icon, required String title, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // ── App methods: slim chips + list ─────────────────────────────────────────

  Widget _buildAppMethodsSection(bool isDark, bool isMobile) {
    final appMethods = _saleMethods.where((m) => m.type == 'app').toList();

    if (appMethods.isEmpty) {
      return _buildEmptyHint(isDark, 'لا توجد وسائل دفع إلكترونية');
    }

    final paidList = _processList(_paidInvoices);

    return Column(
      children: [
        // Slim method chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildMethodChip(isDark, null, 'الكل', _methodTotals.values.fold(0.0, (a, b) => a + b)),
              ...appMethods.map((m) => _buildMethodChip(isDark, m.id, m.name, _methodTotals[m.id] ?? 0.0)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Invoice list filtered by selected method
        if (paidList.isEmpty)
          _buildEmptyHint(isDark, 'لا توجد مدفوعات في هذه الفترة')
        else
          ...paidList.take(_paidDisplayCount).toList().asMap().entries.map((e) => _buildSlimCard(e.value, isDark, false, isMobile, e.key + 1)),
        if (paidList.length > _paidDisplayCount)
          _buildLoadMoreButton(() => setState(() => _paidDisplayCount += _pageSize),
              paidList.length - _paidDisplayCount),
      ],
    );
  }

  Widget _buildMethodChip(bool isDark, int? methodId, String name, double total) {
    final isSelected = _selectedMethodId == methodId;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMethodId = isSelected ? null : methodId;
        _paidDisplayCount = _pageSize;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blue : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
            Text(
              '${total.toStringAsFixed(0)} ₪',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Transfers list ─────────────────────────────────────────────────────────

  Widget _buildTransfersList(bool isDark, bool isMobile) {
    final list = _transferInvoices
        .where((inv) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return (inv.customerName?.toLowerCase().contains(q) ?? false) ||
              inv.amount.toString().contains(q);
        })
        .toList()
      ..sort((a, b) => _isAscending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return _buildEmptyHint(isDark, 'لا توجد حوالات في هذه الفترة');
    }

    return Column(
      children: list
          .take(_unpaidDisplayCount)
          .toList()
          .asMap().entries.map((e) => _buildSlimCard(e.value, isDark, true, isMobile, e.key + 1))
          .toList()
        ..addAll([
          if (list.length > _unpaidDisplayCount)
            _buildLoadMoreButton(
              () => setState(() => _unpaidDisplayCount += _pageSize),
              list.length - _unpaidDisplayCount,
            ),
        ]),
    );
  }

  // ── Slim card ──────────────────────────────────────────────────────────────

  Widget _buildSlimCard(Invoice inv, bool isDark, bool isTransfer, bool isMobile, [int? index]) {
    final typeColor = isTransfer
        ? Colors.teal
        : (inv.type == 'DEPOSIT' ? Colors.green : Colors.blue);

    return GestureDetector(
      onTap: () => _showDetailsPopup(inv, isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF2F7),
          ),
        ),
        child: Row(
          children: [
            // Left: number badge + color dot
            if (index != null) ...[  
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: typeColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            // Middle: name + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inv.customerName ?? 'زبون عابر',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inv.invoiceDate.toLocalShort(),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // Right: amount + method badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${inv.amount.toStringAsFixed(2)} ₪',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: typeColor,
                  ),
                ),
                if (inv.methodName != null)
                  Text(
                    inv.methodName!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ── Details popup ──────────────────────────────────────────────────────────

  void _showDetailsPopup(Invoice inv, bool isDark) {
    PaymentMethod? selectedMethod;
    try {
      if (inv.paymentMethodId != null) {
        selectedMethod = _saleMethods.firstWhere((m) => m.id == inv.paymentMethodId);
      }
    } catch (_) {}

    final isUnpaid = inv.paymentStatus == 'UNPAID' || inv.paymentStatus == 'pending';
    final typeColor = inv.type == 'DEPOSIT'
        ? Colors.teal
        : (inv.type == 'WITHDRAWAL' ? Colors.orange : Colors.blue);
    final typeLabel = inv.type == 'DEPOSIT'
        ? 'حوالة'
        : (inv.type == 'WITHDRAWAL' ? 'سحب نقدي' : 'بيع');
    final statusColor = isUnpaid ? Colors.orange : Colors.green;
    final statusLabel = isUnpaid ? 'معلق' : 'مدفوع';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        PaymentMethod? localMethod = selectedMethod;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 24,
                top: 24,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          inv.customerName ?? 'زبون عابر',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _navigateToCustomer(inv.userId);
                        },
                        child: const Icon(Icons.open_in_new_rounded, size: 18, color: Colors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Info grid
                  _detailRow(isDark, 'المبلغ', '${inv.amount.toStringAsFixed(2)} ₪', valueColor: typeColor),
                  _detailRow(isDark, 'التاريخ', inv.invoiceDate.toLocalShort()),
                  _detailRow(isDark, 'النوع', typeLabel, valueColor: typeColor),
                  _detailRow(isDark, 'الحالة', statusLabel, valueColor: statusColor),
                  if (inv.methodName != null)
                    _detailRow(isDark, 'طريقة الدفع', inv.methodName!),
                  if (inv.notes != null && inv.notes!.isNotEmpty)
                    _detailRow(isDark, 'ملاحظات', inv.notes!),

                  // Settlement section (unpaid only)
                  if (isUnpaid) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'تسوية الفاتورة',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<PaymentMethod>(
                      value: localMethod,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      decoration: InputDecoration(
                        labelText: 'وسيلة الدفع',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: _saleMethods
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (val) => setModalState(() => localMethod = val),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (localMethod != null) {
                            Navigator.pop(ctx);
                            _confirmPayment(inv, localMethod!);
                          } else {
                            ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
                              const SnackBar(content: Text('يرجى اختيار وسيلة الدفع')),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text('تسوية الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(bool isDark, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildEmptyHint(bool isDark, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton(VoidCallback onTap, int remaining) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.expand_more_rounded, color: Colors.blue, size: 18),
        label: Text(
          'تحميل المزيد ($remaining)',
          style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
