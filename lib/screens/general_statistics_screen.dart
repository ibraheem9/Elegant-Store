import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../utils/timestamp_formatter.dart';
import '../widgets/shimmer_loading.dart';

class GeneralStatisticsScreen extends StatefulWidget {
  const GeneralStatisticsScreen({Key? key}) : super(key: key);

  @override
  State<GeneralStatisticsScreen> createState() => _GeneralStatisticsScreenState();
}

class _GeneralStatisticsScreenState extends State<GeneralStatisticsScreen> {
  DateTimeRange? _selectedRange;
  bool _isLoading = true;
  
  // Data points
  double _totalSales = 0.0;
  double _totalSalesApp = 0.0;
  double _totalSalesCash = 0.0;
  double _totalSalesCredit = 0.0;
  double _totalDebts = 0.0;
  double _totalCredits = 0.0;
  double _totalPurchases = 0.0;
  double _totalPurchasesCash = 0.0;
  double _totalPurchasesApp = 0.0;
  double _expectedCashInBox = 0.0;
  double _cashRepayments = 0.0;
  double _appRepayments = 0.0;

  @override
  void initState() {
    super.initState();
    // Default to "This Month"
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    
    try {
      Map<String, double> stats;
      if (_selectedRange == null) {
        // All Time logic - using a very old start date
        stats = await db.getDetailedStatsByRange(
          start: DateTime(2020),
          end: DateTime.now().add(const Duration(days: 1)),
        );
      } else {
        stats = await db.getDetailedStatsByRange(
          start: _selectedRange!.start,
          end: _selectedRange!.end,
        );
      }

      final globalStats = await db.getGlobalStats();

      setState(() {
        _totalSalesApp = stats['app_sales'] ?? 0.0;
        _totalSalesCash = stats['cash_sales_invoice'] ?? 0.0;
        _totalSalesCredit = stats['app_debt'] ?? 0.0;
        _totalSales = _totalSalesApp + _totalSalesCash + _totalSalesCredit;
        
        // These are global (all time)
        _totalDebts = (globalStats['total_debts'] as num?)?.toDouble() ?? 0.0;
        _totalCredits = (globalStats['total_balances'] as num?)?.toDouble() ?? 0.0;

        _totalPurchasesCash = stats['cash_purchases'] ?? 0.0;
        _totalPurchasesApp = stats['app_purchases'] ?? 0.0;
        _totalPurchases = _totalPurchasesCash + _totalPurchasesApp;

        _cashRepayments = stats['cash_sales_deposit'] ?? 0.0;
        _appRepayments = stats['app_sales_deposit'] ?? 0.0;

        // Expected Cash In Box for the range:
        // Cash In = Cash Sales + Cash Repayments
        // Cash Out = Cash Purchases
        // Net = (Cash In - Cash Out)
        // Note: For "All Time", this would be the actual expected box.
        _expectedCashInBox = _totalSalesCash + _cashRepayments - _totalPurchasesCash;

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading stats: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _selectedRange = DateTimeRange(
          start: picked.start,
          end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
        );
      });
      _loadData();
    }
  }

  void _setPredefinedRange(String type) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (type) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'yesterday':
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
        end = DateTime(now.year, now.month, now.day).subtract(const Duration(seconds: 1));
        break;
      case 'week':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'all':
        _selectedRange = null;
        _loadData();
        return;
      default:
        return;
    }

    setState(() {
      _selectedRange = DateTimeRange(start: start, end: end);
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmall = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: _isLoading
          ? ShimmerLoading(isDark: isDark, itemCount: 6)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateFilter(isDark, isSmall),
                  const SizedBox(height: 24),
                  _buildStatsGrid(isDark, isSmall),
                  const SizedBox(height: 24),
                  _buildRepaymentSection(isDark, isSmall),
                  const SizedBox(height: 100), // Space for bottom nav
                ],
              ),
            ),
    );
  }

  Widget _buildDateFilter(bool isDark, bool isSmall) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_rounded, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedRange == null
                      ? 'كل الأوقات'
                      : '${intl.DateFormat('dd/MM/yyyy').format(_selectedRange!.start)} - ${intl.DateFormat('dd/MM/yyyy').format(_selectedRange!.end)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: _selectRange,
                child: const Text('تغيير'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('اليوم', 'today'),
                _filterChip('الأمس', 'yesterday'),
                _filterChip('آخر 7 أيام', 'week'),
                _filterChip('هذا الشهر', 'month'),
                _filterChip('الكل', 'all'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String type) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: false,
        onSelected: (_) => _setPredefinedRange(type),
        backgroundColor: Colors.transparent,
        selectedColor: Colors.blue.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.blue.withOpacity(0.5)),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark, bool isSmall) {
    return GridView.count(
      crossAxisCount: isSmall ? 1 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: isSmall ? 2.5 : 3.0,
      children: [
        _statCard('إجمالي المبيعات', _totalSales, Icons.trending_up_rounded, Colors.blue, isDark),
        _statCard('مبيعات التطبيق', _totalSalesApp, Icons.phonelink_ring_rounded, Colors.indigo, isDark),
        _statCard('مبيعات الكاش', _totalSalesCash, Icons.payments_rounded, Colors.green, isDark),
        _statCard('مبيعات الدين', _totalSalesCredit, Icons.money_off_rounded, Colors.orange, isDark),
        _statCard('إجمالي الديون القائمة', _totalDebts, Icons.account_balance_wallet_rounded, Colors.red, isDark, subtitle: 'كل الأوقات'),
        _statCard('إجمالي الأرصدة (الدائنة)', _totalCredits, Icons.account_balance_rounded, Colors.teal, isDark, subtitle: 'كل الأوقات'),
        _statCard('إجمالي المشتريات', _totalPurchases, Icons.shopping_cart_rounded, Colors.purple, isDark),
        _statCard('الصندوق المتوقع (كاش)', _expectedCashInBox, Icons.savings_rounded, Colors.amber, isDark, isHighlight: true),
      ],
    );
  }

  Widget _buildRepaymentSection(bool isDark, bool isSmall) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سداد الديون في هذه الفترة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          _repaymentRow('سداد كاش', _cashRepayments, Colors.green),
          const Divider(height: 24),
          _repaymentRow('سداد تطبيق', _appRepayments, Colors.blue),
        ],
      ),
    );
  }

  Widget _repaymentRow(String label, double value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.arrow_downward_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(
          '${value.toStringAsFixed(2)} ₪',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _statCard(String title, double value, IconData icon, Color color, bool isDark, {String? subtitle, bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlight 
            ? color.withOpacity(0.15)
            : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight ? color : (isDark ? Colors.white10 : Colors.black12),
          width: isHighlight ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${value.toStringAsFixed(2)} ₪',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
