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
  Map<String, double> _monthlySales = {};
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
    final sales = await db.getMonthlySales(month.year, month.month);
    setState(() => _monthlySales = sales);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _loadDayInvoices(selectedDay);
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                  _loadMonthlyData(focusedDay);
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    final dateStr = DateFormat('yyyy-MM-dd').format(date);
                    if (_monthlySales.containsKey(dateStr)) {
                      return Positioned(
                        bottom: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                          child: Text('${_monthlySales[dateStr]!.toInt()}₪', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ),
                      );
                    }
                    return null;
                  },
                ),
                headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 32, 32, 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('فواتير يوم: ${DateFormat('yyyy-MM-dd').format(_selectedDay!)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                          return ListTile(
                            title: Text(inv.customerName ?? 'زبون عابر', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text(inv.methodName ?? '-'),
                            trailing: Text('${inv.amount} ₪', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
