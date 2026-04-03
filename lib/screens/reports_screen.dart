import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import 'package:fl_chart/fl_chart.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = context.read<DatabaseService>();
    final stats = await db.getGlobalStats();
    setState(() {
      _stats = stats;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التقارير التحليلية', style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                const SizedBox(height: 32),
                
                // KPI Cards
                _buildKPISection(isMobile),
                
                const SizedBox(height: 40),
                if (isMobile) ...[
                  _buildChartCard('توزيع المبيعات'),
                  const SizedBox(height: 24),
                  _buildTopCustomersList(),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildChartCard('توزيع المبيعات حسب طريقة الدفع')),
                      const SizedBox(width: 32),
                      Expanded(flex: 1, child: _buildTopCustomersList()),
                    ],
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildKPISection(bool isMobile) {
    return GridView.count(
      crossAxisCount: isMobile ? 1 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: isMobile ? 2.5 : 1.3,
      children: [
        _buildStatBox('إجمالي الديون القائمة', '${_stats['total_debts']?.toStringAsFixed(2)} ₪', Colors.red),
        _buildStatBox('إجمالي أرصدة الزبائن', '${_stats['total_balances']?.toStringAsFixed(2)} ₪', Colors.green),
        _buildStatBox('عدد الزبائن الدائمين', '${_stats['permanent_count']}', Colors.blue),
        _buildStatBox('إجمالي الزبائن المسجلين', '${_stats['total_customers']}', Colors.purple),
      ],
    );
  }

  Widget _buildStatBox(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildChartCard(String title) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pie_chart_rounded, size: 80, color: Colors.blueGrey),
                  SizedBox(height: 16),
                  Text('الرسوم البيانية قيد المعالجة...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCustomersList() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('أكثر الزبائن تفاعلاً', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 24),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: Colors.blue[50], child: Text('${index + 1}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('جاري التحليل...', style: TextStyle(color: Colors.grey))),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
