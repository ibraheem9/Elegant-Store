import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, Map<String, double>> _monthlyStats = {}; 
  List<Invoice> _selectedDayInvoices = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadMonthlyData(_focusedDay);
    _loadDayInvoices(_focusedDay);
  }

  Future<void> _loadMonthlyData(DateTime month) async {
    final db = context.read<DatabaseService>();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    
    final invoices = await db.getInvoices(start: start, end: end);
    
    Map<String, Map<String, double>> stats = {};
    
    for (var inv in invoices) {
      if (inv.type != 'SALE') continue;
      
      final dateKey = inv.createdAt.substring(0, 10);
      if (!stats.containsKey(dateKey)) {
        stats[dateKey] = {'cash': 0.0, 'app': 0.0};
      }
      
      String mName = (inv.methodName ?? '').toLowerCase();
      if (mName.contains('كاش') || mName.contains('نقدي') || mName.contains('cash')) {
        stats[dateKey]!['cash'] = (stats[dateKey]!['cash'] ?? 0.0) + inv.amount;
      } else if (mName.contains('تطبيق') || mName.contains('بنكي') || mName.contains('app')) {
        stats[dateKey]!['app'] = (stats[dateKey]!['app'] ?? 0.0) + inv.amount;
      }
    }

    setState(() => _monthlyStats = stats);
  }

  Future<void> _loadDayInvoices(DateTime day) async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final invoices = await db.getInvoices(start: start, end: end);
    setState(() {
      _selectedDayInvoices = invoices;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 900;

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      body: isMobile 
        ? SingleChildScrollView(
            child: Column(
              children: [
                _buildCalendarCard(isDark, true),
                _buildInvoicesCard(isDark, true),
              ],
            ),
          )
        : Row(
            children: [
              Expanded(flex: 2, child: _buildCalendarCard(isDark, false)),
              Expanded(flex: 1, child: _buildInvoicesCard(isDark, false)),
            ],
          ),
    );
  }

  Widget _buildCalendarCard(bool isDark, bool isMobile) {
    return Container(
      margin: EdgeInsets.all(isMobile ? 12 : 32),
      padding: EdgeInsets.all(isMobile ? 8 : 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
      ),
      child: TableCalendar(
        locale: 'ar_SA',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        startingDayOfWeek: StartingDayOfWeek.sunday,
        availableCalendarFormats: const {CalendarFormat.month: 'Month'},
        rowHeight: isMobile ? 70 : 90, 
        daysOfWeekHeight: isMobile ? 30 : 40,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
          _loadDayInvoices(selectedDay);
        },
        onPageChanged: (focusedDay) {
          setState(() => _focusedDay = focusedDay);
          _loadMonthlyData(focusedDay);
        },
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: Colors.blue.withOpacity(0.3), shape: BoxShape.circle),
          defaultTextStyle: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: isMobile ? 12 : 14),
          weekendTextStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red, fontSize: isMobile ? 12 : 14),
          outsideDaysVisible: false,
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 13),
          weekendStyle: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 13),
          dowTextFormatter: (date, locale) {
            // Short names to prevent overlap on mobile
            final names = ['أحد', 'نثن', 'ثلاث', 'ربع', 'خمس', 'جمع', 'سبت'];
            return names[date.weekday % 7];
          },
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
          leftChevronIcon: Icon(Icons.chevron_left, color: isDark ? Colors.white : Colors.black),
          rightChevronIcon: Icon(Icons.chevron_right, color: isDark ? Colors.white : Colors.black),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, events) {
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            final stats = _monthlyStats[dateStr];
            if (stats == null) return null;

            final cash = stats['cash'] ?? 0.0;
            final app = stats['app'] ?? 0.0;

            if (cash == 0 && app == 0) return null;

            return Positioned(
              bottom: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cash > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text('ك:${cash.toInt()}', style: TextStyle(fontSize: isMobile ? 7 : 8, fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                  if (app > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text('ت:${app.toInt()}', style: TextStyle(fontSize: isMobile ? 7 : 8, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInvoicesCard(bool isDark, bool isMobile) {
    return Container(
      margin: isMobile ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : const EdgeInsets.fromLTRB(0, 32, 32, 32),
      padding: const EdgeInsets.all(24),
      height: isMobile ? 400 : double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('عمليات يوم: ${DateFormat('yyyy-MM-dd').format(_selectedDay!)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 24),
          if (_isLoading)
             const Center(child: CircularProgressIndicator())
          else if (_selectedDayInvoices.isEmpty)
             const Expanded(child: Center(child: Text('لا توجد مبيعات في هذا اليوم')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _selectedDayInvoices.length,
                itemBuilder: (context, index) {
                  final inv = _selectedDayInvoices[index];
                  Color typeColor = Colors.blue;
                  if (inv.type == 'DEPOSIT') typeColor = Colors.green;
                  if (inv.type == 'WITHDRAWAL') typeColor = Colors.orange;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(inv.customerName ?? 'عابر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                      subtitle: Text(inv.methodName ?? '-', style: const TextStyle(fontSize: 11)),
                      trailing: Text('${inv.amount} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: typeColor)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
