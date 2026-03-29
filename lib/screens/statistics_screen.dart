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
  final _yesterdayCashController = TextEditingController();
  final _todayCashController = TextEditingController();
  final _cashDebtRepaymentController = TextEditingController();

  // Auto-calculated fields
  double _appDebtRepayment = 0.0;
  double _cashPurchases = 0.0;
  double _appPurchases = 0.0;
  
  bool _isLoading = false;
  DailyStatistics? _savedStats;
  Map<String, double> _monthlyData = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    // 1. Get detailed auto-calculated stats
    final detailedStats = await db.getDetailedTodayStats();

    // 2. Check if stats already saved for today
    final savedStats = await db.getTodayStatistics();

    // 3. Load monthly data for chart
    final now = DateTime.now();
    final monthly = await db.getMonthlySales(now.year, now.month);

    setState(() {
      _appDebtRepayment = detailedStats['app_debt_repayment'] ?? 0.0;
      _cashPurchases = detailedStats['cash_purchases'] ?? 0.0;
      _appPurchases = detailedStats['app_purchases'] ?? 0.0;
      _monthlyData = monthly;

      if (savedStats != null) {
        _savedStats = savedStats;
        _yesterdayCashController.text = savedStats.yesterdayCashInBox.toString();
        _todayCashController.text = savedStats.todayCashInBox.toString();
        _cashDebtRepaymentController.text = savedStats.totalCashDebtRepayment.toString();
      }
      _isLoading = false;
    });
  }

  Future<void> _saveStats() async {
    // Validation for Purchases
    if (_cashPurchases == 0 && _appPurchases == 0) {
      bool confirm = await _showPurchaseWarning();
      if (!confirm) return;
    }

    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final now = DateTime.now();
    final todayStr = DateFormat('dd-MM-yyyy').format(now);

    final stats = DailyStatistics(
      statisticDate: todayStr,
      yesterdayCashInBox: double.tryParse(_yesterdayCashController.text) ?? 0.0,
      todayCashInBox: double.tryParse(_todayCashController.text) ?? 0.0,
      totalCashDebtRepayment: double.tryParse(_cashDebtRepaymentController.text) ?? 0.0,
      totalAppDebtRepayment: _appDebtRepayment,
      totalCashPurchases: _cashPurchases,
      totalAppPurchases: _appPurchases,
      createdAt: now.toIso8601String(),
    );

    await db.insertDailyStatistics(stats);
    setState(() {
      _savedStats = stats;
      _isLoading = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إحصائيات اليوم بنجاح'), backgroundColor: Colors.green));
    }
  }

  Future<bool> _showPurchaseWarning() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('تنبيه هام'),
          ],
        ),
        content: const Text(
          'تنبيه: لم يتم إدخال مشتريات اليوم!\nيرجى التأكد من تسجيل كافة المشتريات قبل حفظ إحصائيات آخر اليوم.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء وتدقيق المشتريات')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة الحفظ على أي حال')),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isSmall ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            if (_isLoading)
               const Center(child: CircularProgressIndicator())
            else ...[
              _buildMainGrid(isSmall),
              const SizedBox(height: 40),
              _buildSaveButton(),
              const SizedBox(height: 48),
              _buildChartSection(isSmall),
              if (_savedStats != null) ...[
                const SizedBox(height: 48),
                const Divider(),
                const SizedBox(height: 24),
                _buildResultsSection(isSmall),
              ]
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('إحصائيات ونهاية اليوم', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        const SizedBox(height: 4),
        Text('مراجعة وتأكيد المبالغ المالية لليوم: ${DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now())}', style: const TextStyle(color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildMainGrid(bool isSmall) {
    return GridView.count(
      crossAxisCount: isSmall ? 1 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 24,
      mainAxisSpacing: 24,
      childAspectRatio: 3.5,
      children: [
        _buildManualInput('صندوق الأمس (كاش)', _yesterdayCashController, Icons.history_rounded, Colors.blue),
        _buildManualInput('صندوق اليوم (كاش)', _todayCashController, Icons.account_balance_wallet_rounded, Colors.green),
        _buildManualInput('سداد ديون - كاش', _cashDebtRepaymentController, Icons.payments_rounded, Colors.orange),
        _buildAutoDisplay('سداد ديون - تطبيق (تلقائي)', _appDebtRepayment, Icons.phonelink_ring_rounded, Colors.purple),
        _buildAutoDisplay('مشتريات اليوم - كاش (من الشاشة)', _cashPurchases, Icons.shopping_bag_rounded, Colors.redAccent),
        _buildAutoDisplay('مشتريات اليوم - تطبيق (من الشاشة)', _appPurchases, Icons.mobile_friendly_rounded, Colors.indigo),
      ],
    );
  }

  Widget _buildManualInput(String label, TextEditingController controller, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          prefixIcon: Icon(icon, color: color),
          border: InputBorder.none,
          suffixText: '₪',
        ),
      ),
    );
  }

  Widget _buildAutoDisplay(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                Text('${value.toStringAsFixed(2)} ₪', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 16),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _saveStats,
        icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
        label: const Text('حفظ إحصائيات اليوم النهائية', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
    );
  }

  Widget _buildChartSection(bool isSmall) {
    if (_monthlyData.isEmpty) return const SizedBox.shrink();

    List<BarChartGroupData> barGroups = [];
    int i = 0;
    // Get last 7 days from monthly data
    final sortedKeys = _monthlyData.keys.toList()..sort();
    final last7Days = sortedKeys.length > 7 ? sortedKeys.sublist(sortedKeys.length - 7) : sortedKeys;

    for (var key in last7Days) {
      barGroups.add(BarChartGroupData(
        x: i++,
        barRods: [
          BarChartRodData(toY: _monthlyData[key]!, color: Colors.blue, width: 16, borderRadius: BorderRadius.circular(4))
        ],
      ));
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('نظرة عامة على المبيعات (آخر 7 أيام)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Expanded(
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
                    if (val.toInt() >= last7Days.length) return const Text('');
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(last7Days[val.toInt()].split('-').last, style: const TextStyle(fontSize: 10)),
                    );
                  })),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection(bool isSmall) {
    // Blueprint Formula: (Today Cash + Purchases Cash) - (Yesterday Cash + Debt Repayment Cash)
    final dailyProfit = (_savedStats!.todayCashInBox + _savedStats!.totalCashPurchases) -
                        (_savedStats!.yesterdayCashInBox + _savedStats!.totalCashDebtRepayment);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('التقرير المالي الختامي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: isSmall ? 1 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 3,
          children: [
            _buildResultCard('دخل اليوم الصافي (كاش)', dailyProfit, Colors.blue),
            _buildResultCard('إجمالي المشتريات', _savedStats!.totalCashPurchases + _savedStats!.totalAppPurchases, Colors.orange),
            _buildResultCard('سداد الديون الكلي', _savedStats!.totalCashDebtRepayment + _savedStats!.totalAppDebtRepayment, Colors.green),
            _buildResultCard('إجمالي حركة الصندوق', _savedStats!.todayCashInBox, Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildResultCard(String title, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3), width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
