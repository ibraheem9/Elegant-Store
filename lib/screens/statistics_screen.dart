import '../utils/timestamp_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../widgets/shimmer_loading.dart';

// ── Filter mode ────────────────────────────────────────────────────────────
enum _FilterMode { day, week, month, year, custom }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  // ── Filter ─────────────────────────────────────────────────────────────────
  _FilterMode _filterMode = _FilterMode.day;
  DateTime _selectedDate  = DateTime.now();   // single-day anchor
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // ── Cash box date (editable by user, defaults to today) ────────────────────
  DateTime _cashBoxDate = DateTime.now();

  // ── Manual inputs ──────────────────────────────────────────────────────────
  final _todayCashController = TextEditingController();

  // ── Auto-calculated from DB ───────────────────────────────────────────────
  // Sales
  double _appSales            = 0.0;  // SALE + PAID + pm.type='app'
  double _appSalesDeposit     = 0.0;  // DEPOSIT + PAID + pm.type='app'
  double _cashSalesInvoice    = 0.0;  // SALE + PAID + pm.type='cash'
  double _cashWithdrawalTotal = 0.0;  // all WITHDRAWAL invoices (for cash sales formula)
  double _cashSalesDeposit    = 0.0;  // DEPOSIT + PAID + pm.type='cash' (deducted)
  // Debts
  double _appDebt             = 0.0;  // SALE + UNPAID/DEFERRED
  double _cashDebt            = 0.0;  // WITHDRAWAL + UNPAID
  // Purchases
  double _cashPurchases       = 0.0;  // purchases CASH (excl. withdrawal-linked)
  double _appPurchases        = 0.0;  // purchases APP
  // Credits
  double _totalCredits        = 0.0;  // global sum of abs(balance) for balance < 0
  // Cash box
  double _yesterdayCash       = 0.0;
  bool   _isLoading           = false;
  DailyStatistics? _savedStats;
  Map<String, double> _monthlyData = {};

  // ── Helpers ────────────────────────────────────────────────────────────────
  /// True when the current filter is a single specific day (not a range).
  bool get _isSingleDay =>
      _filterMode == _FilterMode.day || _filterMode == _FilterMode.custom;

  /// The effective start date for DB queries.
  DateTime get _queryStart {
    switch (_filterMode) {
      case _FilterMode.day:
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      case _FilterMode.week:
        // Last 7 days ending on _selectedDate
        final d = _selectedDate;
        return DateTime(d.year, d.month, d.day).subtract(const Duration(days: 6));
      case _FilterMode.month:
        return DateTime(_selectedDate.year, _selectedDate.month, 1);
      case _FilterMode.year:
        return DateTime(_selectedDate.year, 1, 1);
      case _FilterMode.custom:
        return _rangeStart ?? _selectedDate;
    }
  }

  /// The effective end date for DB queries.
  DateTime get _queryEnd {
    switch (_filterMode) {
      case _FilterMode.day:
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
      case _FilterMode.week:
        // End = end of _selectedDate
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
      case _FilterMode.month:
        return DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);
      case _FilterMode.year:
        return DateTime(_selectedDate.year, 12, 31, 23, 59, 59);
      case _FilterMode.custom:
        return _rangeEnd != null
            ? DateTime(_rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day, 23, 59, 59)
            : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    }
  }

  String get _filterLabel {
    switch (_filterMode) {
      case _FilterMode.day:
        final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());
        return isToday ? 'اليوم' : DateFormat('dd/MM/yyyy').format(_selectedDate);
      case _FilterMode.week:
        return 'أسبوع: ${DateFormat('dd/MM').format(_queryStart)} - ${DateFormat('dd/MM').format(_queryEnd)}';
      case _FilterMode.month:
        return DateFormat('MMMM yyyy', 'ar').format(_selectedDate);
      case _FilterMode.year:
        return 'سنة ${_selectedDate.year}';
      case _FilterMode.custom:
        return DateFormat('dd/MM/yyyy').format(_selectedDate);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _todayCashController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _savedStats = null;
      _todayCashController.clear();
    });
    final db = context.read<DatabaseService>();
    final start = _queryStart;
    final end   = _queryEnd;

    final detailedStats = await db.getDetailedStatsByRange(start: start, end: end);
    final yesterdayCash = await db.getYesterdayCashInBox(date: start);
    final monthly       = await db.getMonthlySales(start.year, start.month);

    // For single-day mode, also load saved cash box stats
    DailyStatistics? savedStats;
    if (_isSingleDay) {
      savedStats = await db.getTodayStatistics(date: _selectedDate);
    }

    setState(() {
      _appSales            = detailedStats['app_sales']             ?? 0.0;
      _appSalesDeposit     = detailedStats['app_sales_deposit']     ?? 0.0;
      _cashSalesInvoice    = detailedStats['cash_sales_invoice']    ?? 0.0;
      _cashWithdrawalTotal = detailedStats['cash_withdrawal_total'] ?? 0.0;
      _cashSalesDeposit    = detailedStats['cash_sales_deposit']    ?? 0.0;
      _appDebt             = detailedStats['app_debt']              ?? 0.0;
      _cashDebt            = detailedStats['cash_debt']             ?? 0.0;
      _cashPurchases       = detailedStats['cash_purchases']        ?? 0.0;
      _appPurchases        = detailedStats['app_purchases']         ?? 0.0;
      _totalCredits        = detailedStats['total_credits']         ?? 0.0;
      _yesterdayCash       = yesterdayCash;
      _monthlyData         = monthly;
      if (savedStats != null) {
        _savedStats = savedStats;
        _todayCashController.text = savedStats.todayCashInBox.toStringAsFixed(2);
      }
      _isLoading = false;
    });
  }

  // ── Filter actions ─────────────────────────────────────────────────────────
  Future<void> _applyFilter(_FilterMode mode) async {
    if (mode == _FilterMode.custom) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _filterMode == _FilterMode.custom ? _selectedDate : DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('ar'),
      );
      if (picked == null) return;
      setState(() {
        _filterMode   = _FilterMode.custom;
        _selectedDate = picked;
        _rangeStart   = picked;
        _rangeEnd     = picked;
        _cashBoxDate  = picked;
      });
    } else {
      setState(() {
        _filterMode = mode;
        _rangeStart = null;
        _rangeEnd   = null;
      });
    }
    await _loadData();
  }

  Future<void> _pickSingleDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _filterMode   = _FilterMode.day;
        _rangeStart   = null;
        _rangeEnd     = null;
      });
      await _loadData();
    }
  }

  Future<void> _pickCashBoxDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cashBoxDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _cashBoxDate = picked);
    }
  }

  // ── Derived values (User Formulas) ────────────────────────────────────────
  bool get _cashEntered => _todayCashController.text.trim().isNotEmpty;

  /// x = all invoice that have type deposit and payment status paid and payment method app
  ///     - all invoice that have payment status unpaid or deferred and type sale
  double get _x => _appSalesDeposit - _appDebt;

  /// credit = all invoice that have payment status unpaid or deferred and type sale
  ///          - all invoice that have type deposit and payment status paid and payment method app
  /// (must be positive)
  double get _credit {
    final val = _appDebt - _appSalesDeposit;
    return val > 0 ? val : 0.0;
  }

  /// Total app sales = total invoice that have payment status paid and type sale and payment method app + x
  /// if x > 0: Total app sales = total invoice that have payment status paid and type sale and payment method app + x - credit
  double get _totalAppSales {
    if (_x <= 0) {
      return _appSales + _x;
    } else {
      return _appSales + _x - _credit;
    }
  }

  /// 1b. Total Deposit App = all invoice that have type deposit and payment status paid and payment method app
  double get _totalDepositApp => _appSalesDeposit;

  /// 1c. Total Deposit Cash = all invoice that have type deposit and payment status paid and payment method cash
  double get _totalDepositCash => _cashSalesDeposit;

  /// 2. total cash sales = total cash in box today
  ///                      + total invoices that have payment status paid and type sale and payment method cash
  ///                      + total cash dept
  ///                      + total purchase in cash
  ///                      – total invoice that have type deposit and payment status paid and payment method cash
  ///                      – total cash in box yesterday
  double get _totalCashSales {
    if (!_cashEntered) return 0.0;
    final todayCash = double.tryParse(_todayCashController.text) ?? 0.0;
    return todayCash
        + _cashSalesInvoice
        + _totalCashDebt
        + _totalCashPurchases
        - _cashSalesDeposit
        - _yesterdayCash;
  }

  /// 3. total sales = total app sales + total cash sales
  double get _totalSales => _totalAppSales + _totalCashSales;

  /// 4. Total app dept = all invoice that have payment status unpaid or deferred and type sale
  double get _totalAppDebt => _appDebt;

  /// 5. Total cash dept = all invoices that have type withdrawal and payment status unpaid
  double get _totalCashDebt => _cashDebt;

  /// 6. Total dept = total app dept + total cash dept
  double get _totalDebt => _totalAppDebt + _totalCashDebt;

  /// 7. total app purchase = total purchase paid by app
  double get _totalAppPurchases => _appPurchases;

  /// 8. total cash purchase = total purchase in cash
  double get _totalCashPurchases => _cashPurchases;

  /// 9. total purchase = total app purchase + cash purchase
  double get _totalPurchases => _totalAppPurchases + _totalCashPurchases;

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _saveStats() async {
    if (_cashPurchases == 0 && _appPurchases == 0) {
      final confirm = await _showPurchaseWarning();
      if (!confirm) return;
    }
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final stats = DailyStatistics(
      statisticDate:          DateFormat('yyyy-MM-dd').format(_cashBoxDate),
      yesterdayCashInBox:     _yesterdayCash,
      todayCashInBox:         double.tryParse(_todayCashController.text) ?? 0.0,
      totalCashDebtRepayment: _cashSalesDeposit,   // DEPOSIT+PAID+cash deducted from cash sales
      totalAppDebtRepayment:  _appDebt,
      totalCashPurchases:     _cashPurchases,       // real cash purchases only (excl. withdrawals)
      totalAppPurchases:      _appPurchases,
      totalSalesCash:         _totalCashSales,
      totalSalesCredit:       _appSales,
      createdAt:              TimestampFormatter.toUtcString(_cashBoxDate),
    );
    await db.insertDailyStatistics(stats);
    setState(() {
      _savedStats = stats;
      _isLoading  = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إحصائيات اليوم بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<bool> _showPurchaseWarning() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Text('تنبيه هام'),
        ]),
        content: const Text(
          'لم يتم إدخال مشتريات اليوم!\nيرجى التأكد من تسجيل كافة المشتريات قبل الحفظ.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء وتدقيق المشتريات'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة الحفظ على أي حال'),
          ),
        ],
      ),
    ) ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final isSmall = MediaQuery.of(context).size.width < 800;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: _isLoading
          ? ShimmerLoading(isDark: isDark, itemCount: 5)
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isSmall ? 16 : 32,
                isSmall ? 16 : 32,
                isSmall ? 16 : 32,
                MediaQuery.of(context).padding.bottom + 100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterBar(isDark),
                  const SizedBox(height: 10),
                  _buildFilterDateLabel(isDark),
                  const SizedBox(height: 20),
                  _buildInputSection(isDark, isSmall),
                  const SizedBox(height: 24),
                  _buildStatisticsGrid(isDark, isSmall),
                  const SizedBox(height: 32),
                  if (_isSingleDay) _buildSaveButton(),
                  if (!_isSingleDay)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.orange),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'لا يمكن تعديل الصندوق عند اختيار نطاق زمني. اختر يوماً محدداً لتعديل الصندوق.',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────
  Widget _buildFilterBar(bool isDark) {
    const options = [
      (_FilterMode.day,    'يوم'),
      (_FilterMode.week,   'أسبوع'),
      (_FilterMode.month,  'شهر'),
      (_FilterMode.year,   'سنة'),
      (_FilterMode.custom, 'تاريخ محدد'),
    ];
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFF0F172A);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: List.generate(options.length, (i) {
          final (mode, label) = options[i];
          final isActive = _filterMode == mode;
          final isFirst  = i == 0;
          final isLast   = i == options.length - 1;
          return Expanded(
            child: GestureDetector(
              onTap: () => _applyFilter(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF0F172A)
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  border: Border(
                    top:    BorderSide(color: borderColor),
                    bottom: BorderSide(color: borderColor),
                    left:   BorderSide(color: borderColor, width: isFirst ? 1 : 0.4),
                    right:  BorderSide(color: borderColor, width: isLast  ? 1 : 0.4),
                  ),
                  borderRadius: isFirst
                      ? const BorderRadius.only(
                          topRight:    Radius.circular(10),
                          bottomRight: Radius.circular(10))
                      : isLast
                          ? const BorderRadius.only(
                              topLeft:    Radius.circular(10),
                              bottomLeft: Radius.circular(10))
                          : BorderRadius.zero,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF334155)),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Filter date label (replaces old header) ─────────────────────────────────
  Widget _buildFilterDateLabel(bool isDark) {
    String dateText;
    switch (_filterMode) {
      case _FilterMode.day:
        dateText = DateFormat('dd-MM-yyyy EEEE', 'ar').format(_selectedDate);
        break;
      case _FilterMode.week:
        dateText = 'من ${DateFormat("dd/MM/yyyy").format(_queryStart)} إلى ${DateFormat("dd/MM/yyyy").format(_queryEnd)}';
        break;
      case _FilterMode.month:
        dateText = DateFormat('MMMM yyyy', 'ar').format(_selectedDate);
        break;
      case _FilterMode.year:
        dateText = 'سنة ${_selectedDate.year}';
        break;
      case _FilterMode.custom:
        dateText = DateFormat('dd-MM-yyyy EEEE', 'ar').format(_selectedDate);
        break;
    }
    return Row(
      children: [
        Icon(Icons.event_note_rounded,
            size: 15,
            color: isDark ? Colors.white54 : const Color(0xFF64748B)),
        const SizedBox(width: 6),

        Expanded(
          child: Text(
            dateText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),

      ],
    );
  }

  // ── Statistics Grid ────────────────────────────────────────────────────────
  Widget _buildStatisticsGrid(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('الإحصائيات المالية', Icons.analytics_rounded, Colors.blue, isDark),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isSmall ? 2.8 : 3.5,
          children: [
            _buildAutoDisplay('إجمالي مبيعات التطبيق', _totalAppSales, Icons.phonelink_ring_rounded, Colors.blue, isDark),
            _buildAutoDisplay('إجمالي مبيعات الكاش', _totalCashSales, Icons.local_atm_rounded, Colors.green, isDark),
            _buildAutoDisplay('إجمالي المبيعات', _totalSales, Icons.trending_up_rounded, Colors.teal, isDark),
            _buildAutoDisplay('إجمالي ديون التطبيق', _totalAppDebt, Icons.account_balance_rounded, Colors.purple, isDark),
            _buildAutoDisplay('إجمالي الديون النقدية', _totalCashDebt, Icons.money_off_rounded, Colors.red, isDark),
            _buildAutoDisplay('إجمالي الديون', _totalDebt, Icons.warning_rounded, Colors.orange, isDark),
            _buildAutoDisplay('إجمالي مشتريات التطبيق', _totalAppPurchases, Icons.mobile_friendly_rounded, Colors.indigo, isDark),
            _buildAutoDisplay('إجمالي مشتريات الكاش', _totalCashPurchases, Icons.shopping_bag_rounded, Colors.amber, isDark),
            _buildAutoDisplay('إجمالي المشتريات', _totalPurchases, Icons.shopping_cart_rounded, Colors.cyan, isDark),
            _buildAutoDisplay('إجمالي سداد التطبيق', _totalDepositApp, Icons.install_mobile_rounded, Colors.blueGrey, isDark),
            _buildAutoDisplay('إجمالي سداد الكاش', _totalDepositCash, Icons.payments_rounded, Colors.brown, isDark),
          ],
        ),
        const SizedBox(height: 16),
        _buildDebtStatusInfo(isDark),
      ],
    );
  }

  Widget _buildDebtStatusInfo(bool isDark) {
    String message;
    Color color;
    IconData icon;

    if (_x == 0) {
      message = 'جميع ديون التطبيق مسددة';
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else if (_x > 0) {
      message = 'يوجد رصيد دائن (رصيد إضافي)';
      color = Colors.blue;
      icon = Icons.info_outline;
    } else {
      message = 'لا تزال هناك ديون تطبيق غير مسددة';
      color = Colors.red;
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          if (_x != 0)
            Text(
              '${_x.abs().toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }

  // ── Manual input section ───────────────────────────────────────────────────
  Widget _buildInputSection(bool isDark, bool isSmall) {
    final canEdit = _isSingleDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('إدارة الصندوق', Icons.account_balance_rounded, Colors.green, isDark),
        const SizedBox(height: 16),
        _buildAutoDisplay(
          'صندوق الأمس',
          _yesterdayCash,
          Icons.history_rounded,
          Colors.blueGrey,
          isDark,
        ),
        const SizedBox(height: 16),
        Opacity(
          opacity: canEdit ? 1.0 : 0.5,
          child: IgnorePointer(
            ignoring: !canEdit,
            child: _buildManualInput(
              'صندوق اليوم',
              _todayCashController,
              Icons.account_balance_wallet_rounded,
              Colors.green,
              isDark,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickCashBoxDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, color: Colors.green, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('تاريخ الصندوق',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('dd-MM-yyyy EEEE', 'ar').format(_cashBoxDate),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_calendar_rounded, color: Colors.green, size: 18),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _saveStats,
        icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
        label: const Text(
          'حفظ إحصائيات اليوم النهائية',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // ── Reusable widgets ───────────────────────────────────────────────────────
  Widget _sectionTitle(String title, IconData icon, Color color, bool isDark) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white70 : const Color(0xFF334155),
      )),
    ]);
  }

  Widget _buildManualInput(
    String label,
    TextEditingController controller,
    IconData icon,
    Color color,
    bool isDark, {
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          prefixIcon: Icon(icon, color: color, size: 28),
          border: InputBorder.none,
          suffixText: '₪',
          suffixStyle: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildAutoDisplay(String label, double value, IconData icon, Color color, bool isDark) {
    final isNegative   = value < 0;
    final displayColor = isNegative ? Colors.redAccent : color;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: displayColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: displayColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: displayColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: displayColor, fontWeight: FontWeight.bold, fontSize: 12)),
            Text('${value.toStringAsFixed(2)} ₪',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                )),
          ],
        )),
        const Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 16),
      ]),
    );
  }
}
