import '../utils/timestamp_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

/// Standalone screen for soft-deleted purchases with 10-record pagination.
class PurchasesRecycleBinScreen extends StatefulWidget {
  const PurchasesRecycleBinScreen({Key? key}) : super(key: key);

  @override
  State<PurchasesRecycleBinScreen> createState() =>
      _PurchasesRecycleBinScreenState();
}

class _PurchasesRecycleBinScreenState
    extends State<PurchasesRecycleBinScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  static const int _pageSize = 10;

  final List<Purchase> _items = [];
  int _totalCount = 0;
  int _offset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  final ScrollController _scrollCtrl = ScrollController();

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _items.clear();
      _offset = 0;
      _hasMore = true;
    });
    final db = context.read<DatabaseService>();
    final count = await db.getDeletedPurchasesCount();
    final rows = await db.getDeletedPurchasesPaged(
      limit: _pageSize,
      offset: 0,
    );
    if (mounted) {
      setState(() {
        _totalCount = count;
        _items.addAll(rows);
        _offset = rows.length;
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final db = context.read<DatabaseService>();
    final rows = await db.getDeletedPurchasesPaged(
      limit: _pageSize,
      offset: _offset,
    );
    if (mounted) {
      setState(() {
        _items.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 120) {
      _loadNextPage();
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _restore(Purchase p) async {
    final db = context.read<DatabaseService>();
    await db.restorePurchase(p.id!);
    _snack('تمت استعادة "${p.merchantName}" بنجاح', Colors.green);
    await _loadFirstPage();
  }

  Future<void> _confirmRestore(Purchase p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restore_rounded,
                    color: Colors.green, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('استعادة المشتريات',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          content: Text(
            'هل تريد استعادة "${p.merchantName}" (${p.amount.toStringAsFixed(2)} ₪)؟',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('استعادة',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _restore(p);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isManager =
        context.read<AuthService>().currentUser?.role == 'MANAGER' ||
            context.read<AuthService>().currentUser?.role == 'DEVELOPER';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سلة محذوفات المشتريات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_loading)
              Text(
                '$_totalCount سجل محذوف',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.5),
                ),
              ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadFirstPage,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? _buildEmptyState(isDark)
                : RefreshIndicator(
                    onRefresh: _loadFirstPage,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          );
                        }
                        return _buildCard(_items[i], isDark, isManager);
                      },
                    ),
                  ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: 72,
            color: isDark
                ? Colors.white.withOpacity(0.15)
                : Colors.black.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'سلة المحذوفات فارغة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'لا توجد مشتريات محذوفة حالياً',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : Colors.black.withOpacity(0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Purchase p, bool isDark, bool isManager) {
    final deletedAt = p.deletedAt != null
        ? DateFormat('yyyy/MM/dd  hh:mm a', 'ar')
            .format(DateTime.tryParse(p.deletedAt!) ?? DateTime.now())
        : '—';
    final createdAt = p.createdAt.isNotEmpty
        ? p.createdAt.toLocalShort()
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.merchantName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.paymentSource,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                // Amount badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Text(
                    '${p.amount.toStringAsFixed(2)} ₪',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // ── Info rows ─────────────────────────────────────────────────
            _infoRow(
              Icons.calendar_today_rounded,
              'تاريخ الإنشاء',
              createdAt,
              isDark,
            ),
            const SizedBox(height: 6),
            _infoRow(
              Icons.delete_forever_rounded,
              'تاريخ الحذف',
              deletedAt,
              isDark,
              valueColor: Colors.red.withOpacity(0.8),
            ),
            if (p.notes != null && p.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoRow(
                Icons.notes_rounded,
                'ملاحظات',
                p.notes!,
                isDark,
              ),
            ],
            // ── Restore button (manager/developer only) ───────────────────
            if (isManager) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmRestore(p),
                  icon: const Icon(Icons.restore_rounded,
                      size: 18, color: Colors.green),
                  label: const Text(
                    'استعادة',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark
              ? Colors.white.withOpacity(0.4)
              : Colors.black.withOpacity(0.35),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: isDark
                ? Colors.white.withOpacity(0.45)
                : Colors.black.withOpacity(0.4),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ??
                  (isDark ? Colors.white.withOpacity(0.85) : Colors.black87),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
