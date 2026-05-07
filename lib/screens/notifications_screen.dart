import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/notification_repository.dart';
import 'customers_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationsScreen — paginated, reads from local app_notifications table.
//
// Design rules:
//   • 20 items per page, load-more button at the bottom.
//   • Filter bar: all / unpaid / ceiling.
//   • Badge count = COUNT(*) on the table (fast, no JOIN).
//   • Hard-delete on condition resolved (handled by DatabaseService hooks).
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const int _pageSize = 20;

  final List<AppNotification> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 0;

  // Filter: 'all' | NotificationType.value
  String _filter = 'all';

  // Counts for filter chips (loaded once per refresh)
  int _totalCount = 0;
  int _unpaidCount = 0;
  int _ceilingCount = 0;

  @override
  void initState() {
    super.initState();
    // Rebuild notifications from the live DB state every time the screen opens,
    // then load the first page from the freshly-updated table.
    _rebuildThenLoad();
  }

  // ── Data loading ──────────────────────────────────────────────────────────────────────────────

  NotificationRepository get _repo =>
      context.read<DatabaseService>().notificationRepo;

  /// Rebuilds the app_notifications table from live data, then loads page 1.
  /// Called on screen open and on pull-to-refresh.
  Future<void> _rebuildThenLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items.clear();
      _currentPage = 0;
      _hasMore = true;
    });
    try {
      // Sync the persisted table with the current DB state before reading.
      await _repo.rebuildAll();
      await _readPage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Reads page 0 from the already-up-to-date app_notifications table.
  Future<void> _readPage() async {
    try {
      final typeFilter = _filter == 'all' ? null : _filter;
      final page = await _repo.getPage(
        page: 0,
        pageSize: _pageSize,
        typeFilter: typeFilter,
      );
      final counts = await _repo.getCountByType();
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _currentPage = 1;
        _hasMore = page.length == _pageSize;
        _unpaidCount = counts[NotificationType.unpaidInvoices.value] ?? 0;
        _ceilingCount = counts[NotificationType.ceilingWarning.value] ?? 0;
        _totalCount = _unpaidCount + _ceilingCount;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFirstPage() => _rebuildThenLoad();

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final typeFilter = _filter == 'all' ? null : _filter;
      final page = await _repo.getPage(
        page: _currentPage,
        pageSize: _pageSize,
        typeFilter: typeFilter,
      );
      setState(() {
        _items.addAll(page);
        _currentPage++;
        _hasMore = page.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  void _onFilterChanged(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _loadFirstPage();
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _navigateToCustomer(int customerId) async {
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    final match = customers.where((c) => c.id == customerId).firstOrNull;
    if (match == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(customer: match),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0F1E) : const Color(0xFFF8FAFF),
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          _buildFilterBar(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  AppBar _buildAppBar(bool isDark) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'التنبيهات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (_totalCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_totalCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
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
          onPressed: _loadFirstPage,
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  // ── Filter bar ───────────────────────────────────────────────────────────

  Widget _buildFilterBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Flexible(
            flex: 1,
            child: _filterChip('all', 'الكل', _totalCount, Colors.blueGrey, isDark),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 2,
            child: _filterChip(
              NotificationType.unpaidInvoices.value,
              'فواتير غير مدفوعة',
              _unpaidCount,
              Colors.orange,
              isDark,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 2,
            child: _filterChip(
              NotificationType.ceilingWarning.value,
              'تحذير سقف الدين',
              _ceilingCount,
              Colors.red,
              isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String value,
    String label,
    int count,
    Color color,
    bool isDark,
  ) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color
                : (isDark ? Colors.white24 : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? color
                      : (isDark ? Colors.white60 : Colors.grey[600]),
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              'حدث خطأ أثناء تحميل التنبيهات',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return _buildEmpty(isDark);
    }
    return _buildList(isDark);
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_active_outlined,
              size: 72, color: Colors.green[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد تنبيهات',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
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

  Widget _buildList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return _buildLoadMoreButton(isDark);
          }
          final n = _items[index];
          if (n.type == NotificationType.unpaidInvoices.value) {
            return _buildUnpaidCard(n, isDark);
          }
          if (n.type == NotificationType.ceilingWarning.value) {
            return _buildCeilingCard(n, isDark);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildLoadMoreButton(bool isDark) {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadNextPage,
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('تحميل المزيد'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  // ── Unpaid invoices card ─────────────────────────────────────────────────

  Widget _buildUnpaidCard(AppNotification n, bool isDark) {
    final hasNick =
        n.customerNickname != null && n.customerNickname!.isNotEmpty;
    final displayName =
        hasNick ? '${n.customerName} (${n.customerNickname})' : n.customerName;
    final shortName = hasNick ? n.customerNickname! : n.customerName;

    return GestureDetector(
      onTap: () => _navigateToCustomer(n.customerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.orange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'لدى $shortName ${n.unpaidCount ?? 0} فاتورة غير مدفوعة بإجمالي ${(n.unpaidTotal ?? 0).toStringAsFixed(0)} ₪',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الرصيد الكلي: ${n.balance.toStringAsFixed(2)} ₪',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            Container(
              height: 3,
              decoration: const BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ceiling warning card ─────────────────────────────────────────────────

  Widget _buildCeilingCard(AppNotification n, bool isDark) {
    final hasNick =
        n.customerNickname != null && n.customerNickname!.isNotEmpty;
    final displayName =
        hasNick ? '${n.customerName} (${n.customerNickname})' : n.customerName;
    final shortName = hasNick ? n.customerNickname! : n.customerName;

    final limit = n.creditLimit ?? 0.0;
    final pct = n.percentage ?? 0;
    final isExceeded = n.balance >= limit;
    final color = isExceeded ? Colors.red : Colors.deepOrange;

    return GestureDetector(
      onTap: () => _navigateToCustomer(n.customerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                    child: Icon(
                      isExceeded
                          ? Icons.block_rounded
                          : Icons.warning_amber_rounded,
                      color: color,
                      size: 22,
                    ),
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
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pct%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isExceeded
                              ? '$shortName تجاوز الحد الأقصى من الدين باستخدام ${n.balance.toStringAsFixed(0)} من أصل ${limit.toStringAsFixed(0)} ₪'
                              : '$shortName أوشك على بلوغ الحد الأقصى من الدين باستخدام ${n.balance.toStringAsFixed(0)} من أصل ${limit.toStringAsFixed(0)} ₪',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (n.balance / limit).clamp(0.0, 1.0),
                            backgroundColor: color.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
