import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  // ── Manual inputs ──────────────────────────────────────────────────────────
  final _todayCashController = TextEditingController();

  // ── Auto-calculated ────────────────────────────────────────────────────────
  double _appSales        = 0.0; // فواتير مدفوعة بنكياً (SALE)
  double _appDebt         = 0.0; // مدفوعات بنكية - غير مدفوعة بنكي
  double _cashWithdrawals = 0.0; // إجمالي السحب الكاش (= ديون الكاش)
  double _cashPurchases   = 0.0; // مشتريات كاش
  double _appPurchases    = 0.0; // مشتريات تطبيق
  double _yesterdayCash   = 0.0; // صندوق الأمس (تلقائي من DB)

  bool _isLoading = false;
  DailyStatistics? _savedStats;
  Map<String, double> _monthlyData = {};

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
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    final detailedStats  = await db.getDetailedTodayStats();
    final savedStats     = await db.getTodayStatistics();
    final yesterdayCash  = await db.getYesterdayCashInBox();
    final now            = DateTime.now();
    final monthly        = await db.getMonthlySales(now.year, now.month);

    setState(() {
      _appSales        = detailedStats['app_sales']        ?? 0.0;
      _appDebt         = detailedStats['app_debt']         ?? 0.0;
      _cashWithdrawals = detailedStats['cash_withdrawals'] ?? 0.0;
      _cashPurchases   = detailedStats['cash_purchases']   ?? 0.0;
      _appPurchases    = detailedStats['app_purchases']    ?? 0.0;
      _yesterdayCash   = yesterdayCash;
      _monthlyData     = monthly;

      if (savedStats != null) {
        _savedStats = savedStats;
        _todayCashController.text = savedStats.todayCashInBox.toStringAsFixed(2);
      }
      _isLoading = false;
    });
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  /// إجمالي البيع كاش = صندوق اليوم - صندوق الأمس
  double get _cashSales {
    final today = double.tryParse(_todayCashController.text) ?? 0.0;
    return today - _yesterdayCash;
  }

  /// إجمالي المشتريات = كاش + تطبيق
  double get _totalPurchases => _cashPurchases + _appPurchases;

  /// إجمالي البيع الكلي = مبيعات تطبيق + بيع كاش
  double get _totalSales => _appSales + _cashSales;

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _saveStats() async {
    if (_cashPurchases == 0 && _appPurchases == 0) {
      final confirm = await _showPurchaseWarning();
      if (!confirm) return;
    }

    setState(() => _isLoading = true);
    final db  = context.read<DatabaseService>();
    final now = DateTime.now();

    final stats = DailyStatistics(
      statisticDate:           DateFormat('yyyy-MM-dd').format(now),
      yesterdayCashInBox:      _yesterdayCash,
      todayCashInBox:          double.tryParse(_todayCashController.text) ?? 0.0,
      totalCashDebtRepayment:  0.0, // سداد ديون كاش ملغي
      totalAppDebtRepayment:   _appDebt,
      totalCashPurchases:      _cashPurchases + _cashWithdrawals,
      totalAppPurchases:       _appPurchases,
      totalSalesCash:          _cashSales,
      totalSalesCredit:        _appSales,
      createdAt:               now.toIso8601String(),
    );

    await db.insertDailyStatistics(stats);
    setState(() {
      _savedStats  = stats;
      _isLoading   = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إحصائيات اليوم بنجاح'), backgroundColor: Colors.green),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء وتدقيق المشتريات')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة الحفظ على أي حال')),
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
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmall ? 16 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isDark),
                  const SizedBox(height: 32),
                  _buildInputSection(isDark, isSmall),
                  const SizedBox(height: 24),
                  _buildAutoSection(isDark, isSmall),
                  const SizedBox(height: 32),
                  _buildSummarySection(isDark, isSmall),
                  const SizedBox(height: 32),
                  _buildSaveButton(),
                  const SizedBox(height: 48),
                  _buildChartSection(isDark, isSmall),
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

  Widget _buildHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('إحصائيات ونهاية اليوم',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A))),
        const SizedBox(height: 4),
        Text(
          'مراجعة وتأكيد المبالغ المالية ليوم: ${DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now())}',
          style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF64748B)),
        ),
      ],
    );
  }

  // ── Manual input section ───────────────────────────────────────────────────
  Widget _buildInputSection(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('إدخال يدوي', Icons.edit_note_rounded, Colors.green, isDark),
        const SizedBox(height: 12),
        Row(
          children: [
            // صندوق الأمس — تلقائي من DB
            Expanded(
              child: _buildAutoDisplay(
                'إجمالي الصندوق أمس (تلقائي)',
                _yesterdayCash,
                Icons.history_rounded,
                Colors.blueGrey,
                isDark,
              ),
            ),
            const SizedBox(width: 16),
            // صندوق اليوم — يدوي قابل للتعديل
            Expanded(
              child: _buildManualInput(
                'إجمالي الصندوق اليوم',
                _todayCashController,
                Icons.account_balance_wallet_rounded,
                Colors.green,
                isDark,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Auto-calculated section ────────────────────────────────────────────────
  Widget _buildAutoSection(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('بيانات تلقائية', Icons.auto_graph_rounded, Colors.blue, isDark),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 3.8,
          children: [
            _buildAutoDisplay('إجمالي المبيعات على التطبيق',   _appSales,        Icons.phonelink_ring_rounded,        Colors.blue,    isDark),
            _buildAutoDisplay('إجمالي الدين على التطبيق',      _appDebt,         Icons.account_balance_rounded,       Colors.purple,  isDark),
            _buildAutoDisplay('إجمالي الديون الكاش (سحب)',     _cashWithdrawals, Icons.money_off_rounded,             Colors.red,     isDark),
            _buildAutoDisplay('إجمالي المشتريات تطبيق',        _appPurchases,    Icons.mobile_friendly_rounded,       Colors.indigo,  isDark),
            _buildAutoDisplay('إجمالي المشتريات كاش',          _cashPurchases,   Icons.shopping_bag_rounded,          Colors.orange,  isDark),
          ],
        ),
      ],
    );
  }

  // ── Summary / derived section ──────────────────────────────────────────────
  Widget _buildSummarySection(bool isDark, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('ملخص اليوم', Icons.summarize_rounded, Colors.teal, isDark),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.8,
          children: [
            _buildDerivedCard('إجمالي البيع كاش',    _cashSales,      Colors.green,  isDark,
                subtitle: 'صندوق اليوم - صندوق الأمس'),
            _buildDerivedCard('إجمالي المشتريات',    _totalPurchases, Colors.orange, isDark,
                subtitle: 'كاش + تطبيق'),
            _buildDerivedCard('إجمالي البيع الكلي',  _totalSales,     Colors.blue,   isDark,
                subtitle: 'تطبيق + كاش'),
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
        label: const Text('حفظ إحصائيات اليوم النهائية',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // ── Chart ──────────────────────────────────────────────────────────────────
  Widget _buildChartSection(bool isDark, bool isSmall) {
    if (_monthlyData.isEmpty) return const SizedBox.shrink();

    final sortedKeys = _monthlyData.keys.toList()..sort();
    final last7 = sortedKeys.length > 7 ? sortedKeys.sublist(sortedKeys.length - 7) : sortedKeys;

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < last7.length; i++) {
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: _monthlyData[last7[i]]!, color: Colors.blue, width: 16, borderRadius: BorderRadius.circular(4))],
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
    final cashSalesStored = s.todayCashInBox - s.yesterdayCashInBox;
    final totalSalesStored = s.totalSalesCredit + cashSalesStored;
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
            _buildResultCard('إجمالي البيع الكلي',    totalSalesStored,     Colors.blue,   isDark),
            _buildResultCard('إجمالي البيع كاش',      cashSalesStored,      Colors.green,  isDark),
            _buildResultCard('إجمالي المبيعات تطبيق', s.totalSalesCredit,   Colors.purple, isDark),
            _buildResultCard('إجمالي المشتريات',      totalPurchasesStored, Colors.orange, isDark),
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
        fontSize: 16, fontWeight: FontWeight.bold,
        color: isDark ? Colors.white70 : const Color(0xFF334155),
      )),
    ]);
  }

  Widget _buildManualInput(String label, TextEditingController controller,
      IconData icon, Color color, bool isDark, {ValueChanged<String>? onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          prefixIcon: Icon(icon, color: color),
          border: InputBorder.none,
          suffixText: '₪',
          suffixStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAutoDisplay(String label, double value, IconData icon, Color color, bool isDark) {
    final isNegative = value < 0;
    final displayColor = isNegative ? Colors.redAccent : color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: displayColor.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: displayColor, size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: displayColor, fontWeight: FontWeight.bold, fontSize: 11)),
            Text('${value.toStringAsFixed(2)} ₪',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A))),
          ],
        )),
        const Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 14),
      ]),
    );
  }

  Widget _buildDerivedCard(String title, double value, Color color, bool isDark, {String? subtitle}) {
    final isNegative = value < 0;
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
