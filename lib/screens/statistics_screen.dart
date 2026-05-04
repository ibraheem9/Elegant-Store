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

  // ── Auto-calculated ────────────────────────────────────────────────────────
  double _appSales            = 0.0;
  double _appDebt             = 0.0;
  double _cashWithdrawals     = 0.0;
  double _cashPurchases       = 0.0;
  double _appPurchases        = 0.0;
  double _yesterdayCash       = 0.0;
  double _cashDebtRepayment   = 0.0;
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
        if (_rangeStart != null && _rangeEnd != null) {
          return '${DateFormat('dd/MM').format(_rangeStart!)} - ${DateFormat('dd/MM').format(_rangeEnd!)}';
        }
        return 'تاريخ محدد';
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
      final anchor = _filterMode == _FilterMode.custom && _rangeStart != null
          ? _rangeStart!
          : _selectedDate;
      savedStats = await db.getTodayStatistics(date: anchor);
    }

    setState(() {
      _appSales          = detailedStats['app_sales']           ?? 0.0;
      _appDebt           = detailedStats['app_debt']            ?? 0.0;
      _cashWithdrawals   = detailedStats['cash_withdrawals']    ?? 0.0;
      _cashPurchases     = detailedStats['cash_purchases']      ?? 0.0;
      _appPurchases      = detailedStats['app_purchases']       ?? 0.0;
      _cashDebtRepayment = detailedStats['cash_debt_repayment'] ?? 0.0;
      _yesterdayCash     = yesterdayCash;
      _monthlyData       = monthly;
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
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('ar'),
      );
      if (range == null) return;
      setState(() {
        _filterMode  = _FilterMode.custom;
        _rangeStart  = range.start;
        _rangeEnd    = range.end;
        _selectedDate = range.start;
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

  // ── Derived values ─────────────────────────────────────────────────────────
  bool get _cashEntered => _todayCashController.text.trim().isNotEmpty;

  double get _cashSales {
    if (!_cashEntered) return 0.0;
    final today = double.tryParse(_todayCashController.text) ?? 0.0;
    return today + _cashWithdrawals + _cashPurchases - _yesterdayCash - _cashDebtRepayment;
  }

  double get _totalPurchases => _cashPurchases + _appPurchases;
  double get _totalSales     => _appSales + _cashSales;

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
      totalCashDebtRepayment: 0.0,
      totalAppDebtRepayment:  _appDebt,
      totalCashPurchases:     _cashPurchases + _cashWithdrawals,
      totalAppPurchases:      _appPurchases,
      totalSalesCash:         _cashSales,
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
                  _buildAutoSection(isDark, isSmall),
                  const SizedBox(height: 32),
                  _buildSummarySection(isDark, isSmall),
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
                  if (_savedStats != null) ...[
                    const SizedBox(height: 48),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildResultsSection(isDark, isSmall),
                  ],
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
        if (_rangeStart != null && _rangeEnd != null) {
          dateText = 'من ${DateFormat("dd/MM/yyyy").format(_rangeStart!)} إلى ${DateFormat("dd/MM/yyyy").format(_rangeEnd!)}';
        } else {
          dateText = DateFormat('dd-MM-yyyy').format(_selectedDate);
        }
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

  // ── Manual input section ───────────────────────────────────────────────────
  Widget _buildInputSection(bool isDark, bool isSmall) {
    final canEdit = _isSingleDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('إجمالي الصندوق', Icons.account_balance_rounded, Colors.green, isDark),
        const SizedBox(height: 16),
        _buildAutoDisplay(
          'إجمالي الصندوق أمس (تلقائي)',
          _yesterdayCash,
          Icons.history_rounded,
          Colors.blueGrey,
          isDark,
        ),
        const SizedBox(height: 16),
        // صندوق اليوم — يدوي (disabled in range mode)
        Opacity(
          opacity: canEdit ? 1.0 : 0.5,
          child: IgnorePointer(
            ignoring: !canEdit,
            child: _buildManualInput(
              'إجمالي الصندوق اليوم',
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
          // ── Cash box date field ──
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
                        Text('تاريخ الصندوق',
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

  // ── Auto-calculated section ────────────────────────────────────────────────
  Widget _buildAutoSection(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('بيانات تلقائية من النظام', Icons.auto_graph_rounded, Colors.blue, isDark),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isSmall ? 2.8 : 3.8,
          children: [
            _buildAutoDisplay('إجمالي المبيعات من التطبيق',    _appSales,          Icons.phonelink_ring_rounded,  Colors.blue,    isDark),
            _buildAutoDisplay('إجمالي المبيعات النقدية',       _cashSales,         Icons.local_atm_rounded,       Colors.green,   isDark),
            _buildAutoDisplay('إجمالي المبيعات',               _totalSales,        Icons.trending_up_rounded,     Colors.teal,    isDark),
            _buildAutoDisplay('إجمالي الديون من التطبيق',      _appDebt,           Icons.account_balance_rounded, Colors.purple,  isDark),
            _buildAutoDisplay('إجمالي الديون النقدية',         _cashWithdrawals,   Icons.money_off_rounded,       Colors.red,     isDark),
            _buildAutoDisplay('إجمالي الديون',                 _appDebt + _cashWithdrawals, Icons.warning_rounded, Colors.orange, isDark),
            _buildAutoDisplay('إجمالي المشتريات من التطبيق',   _appPurchases,      Icons.mobile_friendly_rounded, Colors.indigo,  isDark),
            _buildAutoDisplay('إجمالي المشتريات النقدية',      _cashPurchases,     Icons.shopping_bag_rounded,    Colors.amber,   isDark),
            _buildAutoDisplay('إجمالي المشتريات',              _totalPurchases,    Icons.shopping_cart_rounded,   Colors.cyan,    isDark),
          ],
        ),
      ],
    );
  }

  // ── Summary section ────────────────────────────────────────────────────────
  Widget _buildSummarySection(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('ملخص العمليات', Icons.summarize_rounded, Colors.teal, isDark),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isSmall ? 2.8 : 3.5,
          children: [
            _buildDerivedCard('إجمالي المبيعات',      _totalSales,     Colors.blue,   isDark),
            _buildDerivedCard('إجمالي الديون',        _appDebt + _cashWithdrawals, Colors.red, isDark),
            _buildDerivedCard('إجمالي المشتريات',     _totalPurchases, Colors.orange, isDark),
          ],
        ),
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

  // ── Chart (kept but not called in build) ──────────────────────────────────
  Widget _buildChartSection(bool isDark, bool isSmall) {
    if (_monthlyData.isEmpty) return const SizedBox.shrink();
    final sortedKeys = _monthlyData.keys.toList()..sort();
    final last7 = sortedKeys.length > 7 ? sortedKeys.sublist(sortedKeys.length - 7) : sortedKeys;
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < last7.length; i++) {
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(
          toY: _monthlyData[last7[i]]!,
          color: Colors.blue,
          width: 16,
          borderRadius: BorderRadius.circular(4),
        )],
      ));
    }
    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('نظرة عامة على المبيعات (آخر 7 أيام)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A))),
          const SizedBox(height: 32),
          Expanded(
            child: BarChart(BarChartData(
              barGroups: barGroups,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) {
                    final idx = val.toInt();
                    if (idx >= last7.length) return const Text('');
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(last7[idx].split('-').last, style: const TextStyle(fontSize: 10)),
                    );
                  },
                )),
              ),
            )),
          ),
        ],
      ),
    );
  }

  // ── Saved results section ──────────────────────────────────────────────────
  Widget _buildResultsSection(bool isDark, bool isSmall) {
    final s = _savedStats!;
    final cashSalesStored    = s.todayCashInBox - s.yesterdayCashInBox;
    final totalSalesStored   = s.totalSalesCredit + cashSalesStored;
    final totalPurchasesStored = s.totalCashPurchases + s.totalAppPurchases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('التقرير المالي الختامي المحفوظ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1E293B))),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 3,
          children: [
            _buildResultCard('إجمالي البيع الكلي',    totalSalesStored,      Colors.blue,   isDark),
            _buildResultCard('إجمالي البيع نقدي',      cashSalesStored,       Colors.green,  isDark),
            _buildResultCard('إجمالي المبيعات تطبيق', s.totalSalesCredit,    Colors.purple, isDark),
            _buildResultCard('إجمالي المشتريات',      totalPurchasesStored,  Colors.orange, isDark),
          ],
        ),
      ],
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

  Widget _buildDerivedCard(String title, double value, Color color, bool isDark, {String? subtitle}) {
    final isNegative   = value < 0;
    final displayColor = isNegative ? Colors.redAccent : color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: displayColor.withOpacity(0.4), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: displayColor, fontWeight: FontWeight.bold, fontSize: 13)),
          if (subtitle != null)
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(2)} ₪',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: displayColor)),
        ],
      ),
    );
  }

  Widget _buildResultCard(String title, double value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(2)} ₪',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
