import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _topBuyers = [];
  Map<String, double> _paymentMethodDistribution = {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    final globalStats = await db.getGlobalStats();

    // Custom query for Top Buyers (Simplified)
    final database = await db.database;
    final topBuyersResult = await database.rawQuery('''
      SELECT u.name, SUM(i.amount) as total_spent
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      WHERE i.deleted_at IS NULL
      GROUP BY u.id
      ORDER BY total_spent DESC
      LIMIT 5
    ''');

    // Custom query for Payment Method Distribution
    final methodDistResult = await database.rawQuery('''
      SELECT pm.name, SUM(i.amount) as total
      FROM invoices i
      JOIN payment_methods pm ON i.payment_method_id = pm.id
      WHERE i.deleted_at IS NULL
      GROUP BY pm.id
    ''');

    Map<String, double> dist = {};
    for (var row in methodDistResult) {
      dist[row['name'] as String] = (row['total'] as num).toDouble();
    }

    setState(() {
      _stats = globalStats;
      _topBuyers = topBuyersResult;
      _paymentMethodDistribution = dist;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('التقارير والذكاء التجاري', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 32),
                _buildKPIsGrid(isSmall),
                const SizedBox(height: 40),
                if (!isSmall)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildPaymentMethodChart()),
                      const SizedBox(width: 32),
                      Expanded(flex: 3, child: _buildTopBuyersTable()),
                    ],
                  )
                else ...[
                  _buildPaymentMethodChart(),
                  const SizedBox(height: 32),
                  _buildTopBuyersTable(),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildKPIsGrid(bool isSmall) {
    return GridView.count(
      crossAxisCount: isSmall ? 1 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      childAspectRatio: 2,
      children: [
        _buildKPICard('إجمالي الديون القائمة', '${_stats['total_debts']?.toStringAsFixed(2)} ₪', Colors.red, Icons.money_off),
        _buildKPICard('إجمالي الأرصدة المودعة', '${_stats['total_balances']?.toStringAsFixed(2)} ₪', Colors.green, Icons.account_balance_wallet),
        _buildKPICard('عدد الزبائن الكلي', '${_stats['total_customers']}', Colors.blue, Icons.people),
        _buildKPICard('تنبيهات غير مسددة', '${_stats['unpaid_non_permanent_count']}', Colors.orange, Icons.warning),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChart() {
    List<PieChartSectionData> sections = [];
    int i = 0;
    List<Color> colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal];

    _paymentMethodDistribution.forEach((name, value) {
      sections.add(PieChartSectionData(
        value: value,
        title: name,
        color: colors[i % colors.length],
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
      i++;
    });

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        children: [
          const Text('توزيع المبيعات حسب طريقة الدفع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          SizedBox(
            height: 250,
            child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 40, sectionsSpace: 2)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBuyersTable() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('كبار المشترين (Top Buyers)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ..._topBuyers.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: Colors.blue[50], child: Text(b['name'][0], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                const SizedBox(width: 16),
                Expanded(child: Text(b['name'], style: const TextStyle(fontWeight: FontWeight.bold))),
                Text('${(b['total_spent'] as num).toStringAsFixed(2)} ₪', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blue)),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}
