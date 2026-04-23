import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ActivityLogScreen — shows every CREATE / UPDATE / DELETE across all tables
// with filters by action type, target type, user, and date range.
// ─────────────────────────────────────────────────────────────────────────────
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({Key? key}) : super(key: key);

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _logs = [];
  List<User> _users = [];
  bool _isLoading = false;

  // Filters
  String? _filterAction;       // CREATE | UPDATE | DELETE | null = all
  String? _filterTargetType;   // INVOICE | CUSTOMER | PURCHASE | … | null = all
  int?    _filterUserId;
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  int _offset = 0;
  static const int _pageSize = 50;
  bool _hasMore = true;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadLogs(reset: true);
  }

  Future<void> _loadUsers() async {
    final db = context.read<DatabaseService>();
    // Load accountants (staff users) for the user filter dropdown
    final all = await db.getAccountants();
    if (mounted) setState(() => _users = all);
  }

  Future<void> _loadLogs({bool reset = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    if (reset) {
      _offset = 0;
      _hasMore = true;
      _logs = [];
    }
    try {
      final db = context.read<DatabaseService>();
      final rows = await db.getActivityLog(
        action: _filterAction,
        targetType: _filterTargetType,
        performedById: _filterUserId,
        from: _fromDate,
        to: _toDate != null
            ? DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59)
            : null,
        limit: _pageSize,
        offset: _offset,
      );
      setState(() {
        _logs.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      debugPrint('ActivityLog load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _actionColor(String? action) {
    switch (action) {
      case 'CREATE': return Colors.green;
      case 'UPDATE': return const Color(0xFF0B74FF);
      case 'DELETE': return Colors.red;
      default:       return Colors.grey;
    }
  }

  IconData _actionIcon(String? action) {
    switch (action) {
      case 'CREATE': return Icons.add_circle_outline_rounded;
      case 'UPDATE': return Icons.edit_rounded;
      case 'DELETE': return Icons.delete_outline_rounded;
      default:       return Icons.info_outline_rounded;
    }
  }

  String _actionLabel(String? action) {
    switch (action) {
      case 'CREATE': return 'إضافة';
      case 'UPDATE': return 'تعديل';
      case 'DELETE': return 'حذف';
      default:       return action ?? '—';
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'INVOICE':        return 'فاتورة';
      case 'CUSTOMER':       return 'زبون';
      case 'PURCHASE':       return 'مشتريات';
      case 'PAYMENT_METHOD': return 'طريقة دفع';
      case 'ACCOUNTANT':     return 'محاسب';
      case 'TRANSACTION':    return 'معاملة';
      case 'DAILY_STAT':     return 'إحصائية يومية';
      default:               return type ?? '—';
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'INVOICE':        return Icons.receipt_long_rounded;
      case 'CUSTOMER':       return Icons.person_rounded;
      case 'PURCHASE':       return Icons.shopping_cart_rounded;
      case 'PAYMENT_METHOD': return Icons.credit_card_rounded;
      case 'ACCOUNTANT':     return Icons.badge_rounded;
      case 'TRANSACTION':    return Icons.swap_horiz_rounded;
      case 'DAILY_STAT':     return Icons.bar_chart_rounded;
      default:               return Icons.circle_outlined;
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60)  return 'الآن';
      if (diff.inMinutes < 60)  return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24)    return 'منذ ${diff.inHours} ساعة';
      if (diff.inDays == 1)     return 'أمس';
      if (diff.inDays < 7)      return 'منذ ${diff.inDays} أيام';
      return DateFormat('yyyy-MM-dd  HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  // ── Date picker helper ─────────────────────────────────────────────────────
  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2101),
  );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isManager = context.read<AuthService>().isManager();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDark),
          _buildFilterBar(isDark, isManager),
          const Divider(height: 1),
          Expanded(child: _buildLogList(isDark)),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B74FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history_rounded, color: Color(0xFF0B74FF), size: 24),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('سجل النشاط',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black.withOpacity(0.87))),
            Text('جميع العمليات المسجلة في النظام',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black.withOpacity(0.38))),
          ]),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () => _loadLogs(reset: true),
          ),
        ],
      ),
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────
  Widget _buildFilterBar(bool isDark, bool isManager) {
    final chipBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final selBg  = const Color(0xFF0B74FF);

    Widget chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? selBg : chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? selBg : (isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black.withOpacity(0.54)))),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        // Action filter
        chip('الكل',    _filterAction == null,     () { setState(() => _filterAction = null);     _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('إضافة',   _filterAction == 'CREATE',  () { setState(() => _filterAction = 'CREATE'); _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('تعديل',   _filterAction == 'UPDATE',  () { setState(() => _filterAction = 'UPDATE'); _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('حذف',     _filterAction == 'DELETE',  () { setState(() => _filterAction = 'DELETE'); _loadLogs(reset: true); }),
        const SizedBox(width: 12),
        // Divider
        Container(width: 1, height: 24, color: isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
        const SizedBox(width: 12),
        // Type filter
        chip('كل الأنواع',   _filterTargetType == null,         () { setState(() => _filterTargetType = null);         _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('فواتير',       _filterTargetType == 'INVOICE',    () { setState(() => _filterTargetType = 'INVOICE');    _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('زبائن',        _filterTargetType == 'CUSTOMER',   () { setState(() => _filterTargetType = 'CUSTOMER');   _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('مشتريات',      _filterTargetType == 'PURCHASE',   () { setState(() => _filterTargetType = 'PURCHASE');   _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('طرق الدفع',    _filterTargetType == 'PAYMENT_METHOD', () { setState(() => _filterTargetType = 'PAYMENT_METHOD'); _loadLogs(reset: true); }),
        const SizedBox(width: 6),
        chip('محاسبون',      _filterTargetType == 'ACCOUNTANT', () { setState(() => _filterTargetType = 'ACCOUNTANT'); _loadLogs(reset: true); }),
        const SizedBox(width: 12),
        // Divider
        Container(width: 1, height: 24, color: isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
        const SizedBox(width: 12),
        // Date range
        _buildDateChip(isDark, 'من', _fromDate, () async {
          final d = await _pickDate(_fromDate);
          if (d != null) { setState(() => _fromDate = d); _loadLogs(reset: true); }
        }),
        const SizedBox(width: 6),
        _buildDateChip(isDark, 'إلى', _toDate, () async {
          final d = await _pickDate(_toDate);
          if (d != null) { setState(() => _toDate = d); _loadLogs(reset: true); }
        }),
        if (_fromDate != null || _toDate != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () { setState(() { _fromDate = null; _toDate = null; }); _loadLogs(reset: true); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
            ),
          ),
        ],
        // User filter (manager only)
        if (isManager && _users.isNotEmpty) ...[
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
          const SizedBox(width: 12),
          _buildUserDropdown(isDark),
        ],
      ]),
    );
  }

  Widget _buildDateChip(bool isDark, String label, DateTime? date, VoidCallback onTap) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hasDate
              ? const Color(0xFF0B74FF).withOpacity(0.12)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasDate ? const Color(0xFF0B74FF) : (isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_rounded,
              size: 13,
              color: hasDate ? const Color(0xFF0B74FF) : (isDark ? Colors.white54 : Colors.black.withOpacity(0.45))),
          const SizedBox(width: 5),
          Text(
            hasDate ? '$label: ${DateFormat('MM/dd').format(date!)}' : label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasDate ? const Color(0xFF0B74FF) : (isDark ? Colors.white54 : Colors.black.withOpacity(0.45))),
          ),
        ]),
      ),
    );
  }

  Widget _buildUserDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _filterUserId != null
            ? const Color(0xFF0B74FF).withOpacity(0.12)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _filterUserId != null ? const Color(0xFF0B74FF) : (isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
        ),
      ),
      child: DropdownButton<int?>(
        value: _filterUserId,
        underline: const SizedBox(),
        isDense: true,
        hint: Text('كل المستخدمين',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.45))),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('كل المستخدمين', style: TextStyle(fontSize: 12))),
          ..._users.map((u) => DropdownMenuItem<int?>(
            value: u.id,
            child: Text(u.name, style: const TextStyle(fontSize: 12)),
          )),
        ],
        onChanged: (v) {
          setState(() => _filterUserId = v);
          _loadLogs(reset: true);
        },
      ),
    );
  }

  // ── Log list ───────────────────────────────────────────────────────────────
  Widget _buildLogList(bool isDark) {
    if (_isLoading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_toggle_off_rounded, size: 64,
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.12)),
          const SizedBox(height: 12),
          Text('لا توجد سجلات', style: TextStyle(color: isDark ? Colors.white38 : Colors.black.withOpacity(0.38))),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _logs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _logs.length) {
          // Load more trigger
          if (!_isLoading) _loadLogs();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildLogCard(_logs[index], isDark);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, bool isDark) {
    final action     = log['action'] as String?;
    final targetType = log['target_type'] as String?;
    final summary    = log['summary'] as String?;
    final byName     = log['edited_by_name'] as String?;
    final createdAt  = log['created_at'] as String?;
    final reason     = log['edit_reason'] as String?;
    final fieldName  = log['field_name'] as String?;
    final oldValue   = log['old_value'] as String?;
    final newValue   = log['new_value'] as String?;

    final actionColor = _actionColor(action);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Action icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: actionColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_actionIcon(action), color: actionColor, size: 20),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Row 1: action badge + type + time
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: actionColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_actionLabel(action),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: actionColor)),
                ),
                const SizedBox(width: 8),
                Icon(_typeIcon(targetType), size: 13, color: isDark ? Colors.white38 : Colors.black.withOpacity(0.38)),
                const SizedBox(width: 4),
                Text(_typeLabel(targetType),
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.54))),
                const Spacer(),
                Text(_relativeTime(createdAt),
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.38))),
              ]),
              const SizedBox(height: 8),
              // Summary
              if (summary != null && summary.isNotEmpty)
                Text(summary,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white.withOpacity(0.87) : Colors.black.withOpacity(0.87))),
              // Field change detail
              if (fieldName != null && (oldValue != null || newValue != null)) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Text('$fieldName: ',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black.withOpacity(0.38))),
                    if (oldValue != null) ...[
                      Text(oldValue,
                          style: const TextStyle(fontSize: 11, color: Colors.red,
                              decoration: TextDecoration.lineThrough)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.grey),
                      ),
                    ],
                    if (newValue != null)
                      Text(newValue,
                          style: const TextStyle(fontSize: 11, color: Colors.green,
                              fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
              // Reason
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.info_outline_rounded, size: 12,
                      color: isDark ? Colors.white30 : Colors.black.withOpacity(0.38)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('السبب: $reason',
                        style: TextStyle(fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black.withOpacity(0.45),
                            fontStyle: FontStyle.italic)),
                  ),
                ]),
              ],
              // Performed by
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.person_outline_rounded, size: 12,
                    color: isDark ? Colors.white30 : Colors.black.withOpacity(0.38)),
                const SizedBox(width: 4),
                Text(byName != null && byName.isNotEmpty ? byName : 'النظام',
                    style: TextStyle(fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black.withOpacity(0.45))),
                const SizedBox(width: 8),
                if (createdAt != null) ...[
                  Icon(Icons.access_time_rounded, size: 12,
                      color: isDark ? Colors.white30 : Colors.black.withOpacity(0.38)),
                  const SizedBox(width: 4),
                  Text(
                    () {
                      try {
                        return DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.parse(createdAt).toLocal());
                      } catch (_) { return createdAt; }
                    }(),
                    style: TextStyle(fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black.withOpacity(0.45)),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
