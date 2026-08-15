import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';
import '../utils/timestamp_formatter.dart';
import 'profit_calculation_screen.dart';

class ProfitHistoryScreen extends StatefulWidget {
  const ProfitHistoryScreen({super.key});

  @override
  State<ProfitHistoryScreen> createState() => _ProfitHistoryScreenState();
}

class _ProfitHistoryScreenState extends State<ProfitHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final history = await db.getProfitHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  void _shareViaWhatsApp(Map<String, dynamic> record) async {
    final date = (record['created_at'] as String).toLocalShort();
    final profit = (record['net_profit'] as num).toStringAsFixed(2);
    final capital = (record['total_capital'] as num).toStringAsFixed(2);
    final inventory = (record['inventory_value'] as num).toStringAsFixed(2);

    final message = '''
*تقرير صافي الربح - متجر عبد الهادي*
---------------------------
*التاريخ:* $date
*قيمة البضاعة:* $inventory ₪
*رأس المال:* $capital ₪
---------------------------
*صافي الربح النهائي:* $profit ₪
---------------------------
تم الحساب عبر تطبيق متجر عبد الهادي
''';

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse("whatsapp://send?text=$encodedMessage");
    final webUrl = Uri.parse("https://wa.me/?text=$encodedMessage");

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl);
    } else if (await canLaunchUrl(webUrl)) {
      await launchUrl(webUrl);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب لمشاركة التقرير')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل وإدارة الأرباح', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadHistory,
            tooltip: 'تحديث السجل',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQuickActions(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                    ? _buildEmptyState()
                    : _buildHistoryTable(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              title: 'حساب جديد',
              icon: Icons.add_chart_rounded,
              color: Colors.blue,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfitCalculationScreen()),
                );
                _loadHistory();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              title: 'إدارة الشركاء',
              icon: Icons.people_alt_rounded,
              color: Colors.teal,
              onTap: () async {
                // Open ProfitCalculationScreen at step 2 (Partners)
                // Since ProfitCalculationScreen is linear, we just navigate normally.
                // The user can manage partners there.
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfitCalculationScreen()),
                );
                _loadHistory();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('لا يوجد سجل أرباح حتى الآن', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('ابدأ حساباً جديداً ليظهر هنا', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(isDark ? Colors.white10 : Colors.grey[100]),
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('صافي الربح')),
            DataColumn(label: Text('رأس المال')),
            DataColumn(label: Text('المخزون')),
            DataColumn(label: Text('مشاركة')),
          ],
          rows: _history.map((record) {
            return DataRow(cells: [
              DataCell(Text((record['created_at'] as String).toLocalShort(), style: const TextStyle(fontSize: 12))),
              DataCell(Text('${(record['net_profit'] as num).toStringAsFixed(2)} ₪', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
              DataCell(Text('${(record['total_capital'] as num).toStringAsFixed(2)} ₪')),
              DataCell(Text('${(record['inventory_value'] as num).toStringAsFixed(2)} ₪')),
              DataCell(IconButton(
                icon: const Icon(Icons.share_rounded, color: Colors.blue, size: 20),
                onPressed: () => _shareViaWhatsApp(record),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
