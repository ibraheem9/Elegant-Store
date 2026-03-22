import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final _yesterdayController = TextEditingController();
  final _todayController = TextEditingController();

  void _calculateStats() async {
    if (_yesterdayController.text.isEmpty || _todayController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final yesterday = double.parse(_yesterdayController.text);
    final today = double.parse(_todayController.text);
    final dailyIncome = today - yesterday;

    final dbService = context.read<DatabaseService>();
    final stats = DailyStatistics(
      statisticDate: DateTime.now().toString().split(' ')[0],
      yesterdayCashInBox: yesterday,
      todayCashInBox: today,
      dailyCashIncome: dailyIncome,
      totalCashDebtRepayment: 0,
      totalAppDebtRepayment: 0,
      totalCashPurchases: 0,
      totalAppPurchases: 0,
      totalPurchases: 0,
      totalDailySales: 0,
      createdAt: DateTime.now().toIso8601String(),
    );

    await dbService.insertDailyStatistics(stats);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily Income: ₪${dailyIncome.toStringAsFixed(2)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Yesterday\'s Cash in Box (₪)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _yesterdayController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Today\'s Cash in Box (₪)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _todayController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _calculateStats,
                    child: const Text('Calculate'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _yesterdayController.dispose();
    _todayController.dispose();
    super.dispose();
  }
}
