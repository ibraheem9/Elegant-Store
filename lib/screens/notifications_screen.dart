import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'customers_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _error;

  // Filter: 'all', 'unpaid', 'ceiling'
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final db = context.read<DatabaseService>();
      final data = await db.getSmartNotifications();
      setState(() { _notifications = data; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'unpaid') return _notifications.where((n) => n['type'] == 'UNPAID_INVOICES').toList();
    if (_filter == 'ceiling') return _notifications.where((n) => n['type'] == 'CEILING_WARNING').toList();
    return _notifications;
  }

  int get _unpaidCount => _notifications.where((n) => n['type'] == 'UNPAID_INVOICES').length;
  int get _ceilingCount => _notifications.where((n) => n['type'] == 'CEILING_WARNING').length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0F1E) : const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('التنبيهات', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            if (_notifications.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_notifications.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadNotifications,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _notifications.isEmpty
                  ? _buildEmpty(isDark)
                  : Column(
                      children: [
                        _buildFilterBar(isDark),
                        Expanded(child: _buildList(isDark)),
                      ],
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('حدث خطأ: $_error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadNotifications, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_active_outlined, size: 72, color: Colors.green[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد تنبيهات',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'جميع الزبائن ليس لديهم ديون مستحقة',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Flexible(
            flex: 1,
            child: _filterChip('all', 'الكل', _notifications.length, Colors.blueGrey, isDark),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 2,
            child: _filterChip('unpaid', 'فواتير غير مدفوعة', _unpaidCount, Colors.orange, isDark),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 2,
            child: _filterChip('ceiling', 'تحذير سقف الدين', _ceilingCount, Colors.red, isDark),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, int count, Color color, bool isDark) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: selected ? color : (isDark ? Colors.white60 : Colors.grey[600]), fontWeight: selected ? FontWeight.bold : FontWeight.normal),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool isDark) {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(child: Text('لا توجد تنبيهات في هذا التصنيف', style: TextStyle(color: Colors.grey[500])));
    }
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final n = items[index];
          if (n['type'] == 'UNPAID_INVOICES') return _buildUnpaidCard(n, isDark);
          if (n['type'] == 'CEILING_WARNING') return _buildCeilingCard(n, isDark);
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildUnpaidCard(Map<String, dynamic> n, bool isDark) {
    final name = n['customerName'] as String;
    final nickname = n['customerNickname'] as String?;
    final balance = n['balance'] as double;
    final unpaidCount = n['unpaidCount'] as int;
    final unpaidTotal = n['unpaidTotal'] as double;
    final customerId = n['customerId'] as int;

    return GestureDetector(
      onTap: () => _navigateToCustomer(customerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nickname != null && nickname.isNotEmpty ? '$name ($nickname)' : name,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'يوجد $unpaidCount فاتورة غير مدفوعة بقيمة ${unpaidTotal.toStringAsFixed(2)} ₪',
                          style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'رصيد الدين الحالي: ${balance.toStringAsFixed(2)} ₪',
                          style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                ],
              ),
            ),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCeilingCard(Map<String, dynamic> n, bool isDark) {
    final name = n['customerName'] as String;
    final nickname = n['customerNickname'] as String?;
    final balance = n['balance'] as double;
    final limit = n['creditLimit'] as double;
    final percentage = n['percentage'] as int;
    final customerId = n['customerId'] as int;
    final isExceeded = balance >= limit;

    final color = isExceeded ? Colors.red : Colors.deepOrange;

    return GestureDetector(
      onTap: () => _navigateToCustomer(customerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isExceeded ? Icons.block_rounded : Icons.warning_amber_rounded, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nickname != null && nickname.isNotEmpty ? '$name ($nickname)' : name,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                              child: Text('$percentage%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isExceeded
                              ? '${nickname != null && nickname.isNotEmpty ? nickname : name} تجاوز الحد الأقصى من الدين باستخدام ${balance.toStringAsFixed(0)} من أصل ${limit.toStringAsFixed(0)} ₪'
                              : '${nickname != null && nickname.isNotEmpty ? nickname : name} أوشك على بلوغ الحد الأقصى من الدين باستخدام ${balance.toStringAsFixed(0)} من أصل ${limit.toStringAsFixed(0)} ₪',
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (balance / limit).clamp(0.0, 1.0),
                            backgroundColor: color.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                ],
              ),
            ),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToCustomer(int customerId) async {
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    final matches = customers.where((c) => c.id == customerId);
    final customer = matches.isEmpty ? null : matches.first;
    if (customer == null || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(customer: customer),
      ),
    );
  }
}
