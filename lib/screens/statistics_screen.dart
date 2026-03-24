import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  final _appDebtRepaymentController = TextEditingController();
  final _cashPurchasesController = TextEditingController();
  final _appPurchasesController = TextEditingController();
  
  bool _isLoading = false;
  DailyStatistics? _todayStats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseService>();
    final stats = await db.getTodayStatistics();
    if (stats != null) {
      setState(() {
        _todayStats = stats;
        _yesterdayCashController.text = stats.yesterdayCashInBox.toString();
        _todayCashController.text = stats.todayCashInBox.toString();
        _cashDebtRepaymentController.text = stats.totalCashDebtRepayment.toString();
        _appDebtRepaymentController.text = stats.totalAppDebtRepayment.toString();
        _cashPurchasesController.text = stats.totalCashPurchases.toString();
        _appPurchasesController.text = stats.totalAppPurchases.toString();
      });
    }
  }

  Future<void> _saveStats() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final now = DateTime.now();
    final todayStr = DateFormat('dd-MM-yyyy').format(now);

    final stats = DailyStatistics(
      statisticDate: todayStr,
      yesterdayCashInBox: double.tryParse(_yesterdayCashController.text) ?? 0.0,
      todayCashInBox: double.tryParse(_todayCashController.text) ?? 0.0,
      totalCashDebtRepayment: double.tryParse(_cashDebtRepaymentController.text) ?? 0.0,
      totalAppDebtRepayment: double.tryParse(_appDebtRepaymentController.text) ?? 0.0,
      totalCashPurchases: double.tryParse(_cashPurchasesController.text) ?? 0.0,
      totalAppPurchases: double.tryParse(_appPurchasesController.text) ?? 0.0,
      createdAt: now.toIso8601String(),
    );

    await db.insertDailyStatistics(stats);
    setState(() {
      _todayStats = stats;
      _isLoading = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإحصائيات بنجاح')));
    }
  }

  double _calculateDailyIncome() {
    if (_todayStats == null) return 0.0;
    // دخل اليوم بالشيكل = مجموع الكاش بالصندوق اليوم + الدين النقدي اليوم + المشتريات نقدي – الصندوق أمس نقدي – سداد دين نقدي
    return _todayStats!.todayCashInBox + 
           _todayStats!.totalCashDebtRepayment + 
           _todayStats!.totalCashPurchases - 
           _todayStats!.yesterdayCashInBox - 
           _todayStats!.totalCashDebtRepayment;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إحصائيات آخر اليوم', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            _buildInputField('مجموع الكاش بالصندوق بالأمس', _yesterdayCashController),
            _buildInputField('مجموع الكاش بالصندوق اليوم', _todayCashController),
            _buildInputField('مجموع سداد الديون النقدي', _cashDebtRepaymentController),
            _buildInputField('مجموع سداد الديون على التطبيق', _appDebtRepaymentController),
            _buildInputField('مجموع مشتريات نقدي', _cashPurchasesController),
            _buildInputField('مجموع مشتريات تطبيق', _appPurchasesController),
            
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveStats,
                child: _isLoading ? const CircularProgressIndicator() : const Text('حفظ الإحصائيات'),
              ),
            ),
            
            if (_todayStats != null) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text('النتائج المحسوبة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildResultRow('دخل اليوم بالشيكل', '${_calculateDailyIncome()} ₪', Colors.green),
              _buildResultRow('مجموع المشتريات الكلي', '${_todayStats!.totalCashPurchases + _todayStats!.totalAppPurchases} ₪', Colors.red),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
