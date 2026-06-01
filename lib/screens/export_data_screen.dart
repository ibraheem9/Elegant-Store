import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/theme_service.dart';
import '../utils/app_snackbar.dart';

class ExportDataScreen extends StatefulWidget {
  const ExportDataScreen({super.key});

  @override
  State<ExportDataScreen> createState() => _ExportDataScreenState();
}

class _ExportDataScreenState extends State<ExportDataScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isExporting = false;

  final Map<String, bool> _tablesToInclude = {
    'invoices': true,
    'transactions': true,
    'purchases': true,
    'users': true, // Customers
  };

  final Map<String, String> _tableLabels = {
    'invoices': 'الفواتير',
    'transactions': 'المعاملات المالية',
    'purchases': 'المشتريات',
    'users': 'العملاء (الجدد)',
  };

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: const Locale('ar', 'AE'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _handleExport() async {
    final selectedTables = _tablesToInclude.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    if (selectedTables.isEmpty) {
      AppSnackBar.show(context, 'يرجى اختيار نوع واحد على الأقل من البيانات لتصديره', isError: true);
      return;
    }

    setState(() => _isExporting = true);

    try {
      final db = context.read<DatabaseService>();
      final exportService = ExportService(db);
      
      final String? filePath = await exportService.exportFilteredAndShare(
        startDate: _startDate,
        endDate: _endDate,
        tablesToInclude: selectedTables,
      );

      if (!mounted) return;

      if (filePath != null) {
        AppSnackBar.show(context, 'تم تصدير البيانات بنجاح ✓');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, 'فشل التصدير: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final isDark = themeNotifier.themeMode == ThemeMode.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          'تصدير مخصص للبيانات',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(
                  'تحديد النطاق الزمني',
                  isDark,
                  [
                    _buildDateSelector(context, 'تاريخ البداية', _startDate, true, isDark),
                    const SizedBox(height: 16),
                    _buildDateSelector(context, 'تاريخ النهاية', _endDate, false, isDark),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  'اختيار البيانات المشمولة',
                  isDark,
                  _tablesToInclude.keys.map((key) {
                    return CheckboxListTile(
                      title: Text(_tableLabels[key]!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      value: _tablesToInclude[key],
                      onChanged: (val) {
                        setState(() => _tablesToInclude[key] = val ?? false);
                      },
                      activeColor: const Color(0xFF0B74FF),
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _handleExport,
                    icon: _isExporting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded),
                    label: Text(
                      _isExporting ? 'جاري التصدير...' : 'تصدير البيانات المحددة',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B74FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'سيتم إنشاء ملف JSON يحتوي على السجلات المختارة ضمن الفترة الزمنية المحددة. يمكنك استخدام هذا الملف للاحتفاظ بنسخة احتياطية أو للمراجعة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context, String label, DateTime date, bool isStart, bool isDark) {
    return InkWell(
      onTap: () => _selectDate(context, isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF071028) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: isDark ? Colors.grey : Colors.black54, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  DateFormat('yyyy-MM-dd').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Icon(Icons.calendar_today_rounded, color: Color(0xFF0B74FF)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0B74FF))),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}
