import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../models/models.dart';
import 'sales_screen.dart';
import 'statistics_screen.dart';
import 'purchases_screen.dart';
import 'customers_screen.dart';
import 'payments_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'payment_methods_screen.dart';
import 'purchases_methods_screen.dart';
import 'recycle_bin_screen.dart';
import 'notifications_screen.dart';
import 'accountants_screen.dart';
import 'sync_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const DashboardHomeScreen();
      case 1: return const SalesScreen();
      case 2: return const StatisticsScreen();
      case 3: return const PurchasesScreen();
      case 4: return const CustomersScreen();
      case 5: return const AccountantsScreen();
      case 6: return const PaymentsScreen();
      case 7: return const CalendarScreen();
      case 8: return const PaymentMethodsScreen();
      case 9: return const PurchasesMethodsScreen();
      case 10: return const RecycleBinScreen();
      case 11: return const SettingsScreen();
      default: return const DashboardHomeScreen();
    }
  }

  String _getScreenTitle(int index) {
    switch (index) {
      case 0: return 'لوحة التحكم';
      case 1: return 'شاشة البيع';
      case 2: return 'إحصائيات اليوم';
      case 3: return 'المشتريات';
      case 4: return 'إدارة الزبائن';
      case 5: return 'إدارة الموظفين';
      case 6: return 'مراجعة المدفوعات';
      case 7: return 'التقويم المالي';
      case 8: return 'طرق دفع المبيعات';
      case 9: return 'طرق دفع المشتريات';
      case 10: return 'سلة المحذوفات';
      case 11: return 'الإعدادات والسمة';
      default: return 'Elegant Store';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.read<AuthService>();

    final bool isMobile = width < 650;
    final bool isTablet = width >= 650 && width < 1100;
    final bool isDesktop = width >= 1100;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: isMobile ? _buildMobileDrawer(isDark, auth) : null,
      body: Row(
        children: [
          if (isDesktop) _buildFullSidebar(theme, isDark, auth),
          if (isTablet) _buildNavigationRail(theme, isDark, auth),
          Expanded(
            child: Column(
              children: [
                _buildAdaptiveAppBar(theme, width, isMobile, isDark),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_selectedIndex),
                      child: _getScreen(_selectedIndex),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildBottomNav(theme, auth) : null,
    );
  }

  Widget _buildMobileDrawer(bool isDark, AuthService auth) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: Column(
        children: [
          _buildSidebarHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                if (auth.isManager())
                  _buildSidebarItem(5, 'إدارة الموظفين', Icons.badge_rounded),
                _buildSidebarItem(6, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(7, 'التقويم المالي', Icons.calendar_month_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(8, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(9, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(10, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(11, 'الإعدادات والسمة', Icons.settings_rounded),
              ],
            ),
          ),
          _buildUserCard(true, isDark),
        ],
      ),
    );
  }

  Widget _buildFullSidebar(ThemeData theme, bool isDark, AuthService auth) {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          _buildSidebarHeader(),
          const SizedBox(height: 5),
          Expanded(
            child: ListView(
              children: [
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                if (auth.isManager())
                  _buildSidebarItem(5, 'إدارة الموظفين', Icons.badge_rounded),
                _buildSidebarItem(6, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(7, 'التقويم المالي', Icons.calendar_month_rounded),
                _buildSidebarItem(8, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(9, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(10, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(11, 'الإعدادات والسمة', Icons.settings_rounded),
              ],
            ),
          ),
          _buildUserCard(true, isDark),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ThemeData theme, bool isDark, AuthService auth) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      backgroundColor: const Color(0xFF0F172A),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF94A3B8)),
      selectedIconTheme: const IconThemeData(color: Colors.white),
      labelType: NavigationRailLabelType.none,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Image.asset('assets/logo.png', height: 40, errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront_rounded, color: Colors.blue, size: 32)),
      ),
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text('الرئيسية')),
        const NavigationRailDestination(icon: Icon(Icons.receipt_long_rounded), label: Text('البيع')),
        const NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded), label: Text('إحصائيات')),
        const NavigationRailDestination(icon: Icon(Icons.shopping_cart_rounded), label: Text('المشتريات')),
        const NavigationRailDestination(icon: Icon(Icons.people_alt_rounded), label: Text('الزبائن')),
        if (auth.isManager())
          const NavigationRailDestination(icon: Icon(Icons.badge_rounded), label: Text('الموظفين')),
        const NavigationRailDestination(icon: Icon(Icons.payments_rounded), label: Text('المدفوعات')),
        const NavigationRailDestination(icon: Icon(Icons.calendar_month_rounded), label: Text('التقويم')),
        const NavigationRailDestination(icon: Icon(Icons.payment_rounded), label: Text('دفع المبيعات')),
        const NavigationRailDestination(icon: Icon(Icons.account_balance_rounded), label: Text('دفع المشتريات')),
        const NavigationRailDestination(icon: Icon(Icons.delete_sweep_rounded), label: Text('سلة المحذوفات')),
        const NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('الإعدادات')),
      ],
    );
  }

  Widget _buildBottomNav(ThemeData theme, AuthService auth) {
    return BottomNavigationBar(
      currentIndex: _selectedIndex > 4 ? 0 : _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue[700],
      unselectedItemColor: const Color(0xFF94A3B8),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'البيع'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'إحصائيات'),
        BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_rounded), label: 'المشتريات'),
        BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'الزبائن'),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Center(
          child: Image.asset(
            'assets/logo.png',
            height: 80,
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.storefront_rounded, color: Colors.blue, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon) {
    bool isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? Colors.blue : const Color(0xFF94A3B8), size: 22),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8), fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(bool isFull, bool isDark) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Consumer<AuthService>(
          builder: (context, auth, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.blue, radius: 16, child: Icon(Icons.person, color: Colors.white, size: 18)),
                if (isFull) ...[
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(auth.currentUser?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text(auth.isManager() ? 'مدير' : 'محاسب', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                  ])),
                  IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18), onPressed: () => auth.logout()),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveAppBar(ThemeData theme, double width, bool isMobile, bool isDark) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 85,
        padding: EdgeInsets.only(
          left: isMobile ? 8 : 24, 
          right: isMobile ? 8 : 24,
          top: 15, 
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF071028) : Colors.white, 
          border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)))
        ),
        child: Row(
          children: [
            if (isMobile) 
              IconButton(
                icon: Icon(Icons.menu_rounded, color: isDark ? Colors.white : Colors.black87),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            const SizedBox(width: 8),
            if (isMobile)
              Image.asset(
                'assets/logo.png',
                height: 45,
                errorBuilder: (context, error, stackTrace) => Text(
                  _getScreenTitle(_selectedIndex),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A))
                ),
              )
            else
              Text('Elegant Store', 
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A))),
            const Spacer(),
            _buildNotificationIcon(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(bool isDark) {
    return Consumer<DatabaseService>(
      builder: (context, db, _) => FutureBuilder<Map<String, dynamic>>(
        future: db.getGlobalStats(),
        builder: (context, snap) {
          bool hasAlert = (snap.data?['unpaid_non_permanent_count'] ?? 0) > 0;
          return Stack(
            children: [
              InkWell(
                onTap: () {
                   Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8), 
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.grey[100], shape: BoxShape.circle), 
                  child: Icon(Icons.notifications_none_rounded, color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF64748B), size: 22)
                ),
              ),
              if (hasAlert) Positioned(right: 2, top: 2, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ],
          );
        }
      ),
    );
  }
}

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
  String _syncStatus = "جاهز للمزامنة";
  User? _lastUser;
  Invoice? _lastInvoice;
  // Store reference to avoid using context in dispose()
  SyncService? _syncService;

  @override
  void initState() {
    super.initState();
    _loadSyncDetails();
    
    // Store the SyncService reference and add listener after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncService = context.read<SyncService>();
        _syncService!.addListener(_onSyncStatusChanged);
      }
    });
  }

  @override
  void dispose() {
    // Use stored reference — never access context in dispose()
    _syncService?.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (!mounted) return;
    final isSyncing = context.read<SyncService>().isSyncing;
    if (!isSyncing) {
       _loadSyncDetails();
    }
  }

  Future<void> _loadSyncDetails() async {
    final db = context.read<DatabaseService>();
    final user = await db.getLastSyncedUser();
    final invoice = await db.getLastSyncedInvoice();
    if (mounted) {
      setState(() {
        _lastUser = user;
        _lastInvoice = invoice;
      });
    }
  }

  Future<void> _handleSync() async {
    setState(() {
      _syncStatus = "جاري الاتصال بالسيرفر...";
    });

    try {
      final syncService = context.read<SyncService>();
      await syncService.performFullSync();
      if (mounted) {
        setState(() => _syncStatus = "تمت المزامنة بنجاح");
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('500')) msg = "خطأ في السيرفر (500)";
        setState(() => _syncStatus = "فشلت المزامنة: $msg");
      }
    } finally {
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() {
            _syncStatus = "جاهز للمزامنة";
          });
        });
      }
    }
  }

  void _openSyncDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SyncDetailsScreen()),
    ).then((_) => _loadSyncDetails()); // Refresh after returning
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 650;
    int crossAxisCount = (size.width > 1400) ? 4 : (size.width > 900 ? 2 : 1);
    final db = context.read<DatabaseService>();

    return Consumer<SyncService>(
      builder: (context, syncService, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'لوحة التحكم', 
                    style: TextStyle(
                      fontSize: isMobile ? 24 : 32, 
                      fontWeight: FontWeight.w900, 
                      color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A)
                    )
                  ),
                  _buildSyncButton(isDark, syncService.isSyncing),
                ],
              ),
              if (syncService.isSyncing || _syncStatus.contains('فشلت') || _syncStatus.contains('نجاح')) ...[
                const SizedBox(height: 16),
                _buildSyncProgress(isDark, syncService.isSyncing),
              ],
              const SizedBox(height: 24),
              _buildLastSyncDetails(isDark, isMobile),
              const SizedBox(height: 32),
              FutureBuilder<Map<String, dynamic>>(
                future: db.getGlobalStats(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final stats = snapshot.data!;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: isMobile ? 2.2 : 1.5,
                    children: [
                      _buildStatCard('إجمالي الديون القائمة', '${stats['total_debts'].toStringAsFixed(2)} ₪', Icons.money_off_rounded, const Color(0xFFEF4444), isDark),
                      _buildStatCard('إجمالي الأرصدة المودعة', '${stats['total_balances'].toStringAsFixed(2)} ₪', Icons.account_balance_rounded, const Color(0xFF10B981), isDark),
                      _buildStatCard('عدد الزبائن الكلي', '${stats['total_customers']}', Icons.group_rounded, const Color(0xFF3B82F6), isDark),
                      _buildStatCard('تنبيهات غير مسددة', '${stats['unpaid_non_permanent_count'] ?? 0}', Icons.warning_amber_rounded, Colors.orange, isDark, onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSyncButton(bool isDark, bool isSyncing) {
    return ElevatedButton.icon(
      onPressed: isSyncing ? null : _handleSync,
      icon: isSyncing 
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.sync_rounded, size: 20, color: Colors.white),
      label: Text(isSyncing ? 'جاري المزامنة...' : 'مزامنة البيانات', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSyncProgress(bool isDark, bool isSyncing) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync_rounded, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(_syncStatus, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.blue[900]), overflow: TextOverflow.ellipsis)),
            ],
          ),
          if (isSyncing) ...[
            const SizedBox(height: 12),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              child: LinearProgressIndicator(minHeight: 6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLastSyncDetails(bool isDark, bool isMobile) {
    final syncService = context.read<SyncService>();
    final details = syncService.lastSyncDetails;

    // Format last sync time for display
    String lastSyncDisplay = 'لم تتم مزامنة بعد';
    if (details != null && details.lastSyncTime.isNotEmpty) {
      try {
        final dt = DateTime.parse(details.lastSyncTime).toLocal();
        lastSyncDisplay = DateFormat('yyyy/MM/dd  hh:mm a', 'ar').format(dt);
      } catch (_) {
        lastSyncDisplay = details.lastSyncTime;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.5) : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.cloud_done_rounded,
                  size: 20,
                  color: details != null ? Colors.green : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'حالة المزامنة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.blue[300] : Colors.blue[800],
                  ),
                ),
              ),
              // ── More Details button ──────────────────────────────────
              TextButton.icon(
                onPressed: _openSyncDetails,
                icon: const Icon(Icons.bar_chart_rounded, size: 16),
                label: const Text('مزيد من التفاصيل', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: Colors.blue.withOpacity(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Last sync time ───────────────────────────────────────────
          _buildDetailItem(
            'آخر مزامنة:',
            lastSyncDisplay,
            Icons.access_time_rounded,
            isDark,
          ),
          const SizedBox(height: 12),
          // ── Last synced customer ─────────────────────────────────────
          if (isMobile) ...[
            _buildDetailItem(
              'آخر زبون مرفوع للسيرفر:',
              _lastUser?.name ?? 'لا يوجد',
              Icons.person_add_alt_1_rounded,
              isDark,
            ),
            const SizedBox(height: 12),
            _buildDetailItem(
              'آخر فاتورة مرفوعة:',
              _lastInvoice != null
                  ? '${_lastInvoice!.amount.toStringAsFixed(2)} ₪ — ${_lastInvoice!.customerName}'
                  : 'لا يوجد',
              Icons.receipt_long_rounded,
              isDark,
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'آخر زبون مرفوع للسيرفر:',
                    _lastUser?.name ?? 'لا يوجد',
                    Icons.person_add_alt_1_rounded,
                    isDark,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildDetailItem(
                    'آخر فاتورة مرفوعة:',
                    _lastInvoice != null
                        ? '${_lastInvoice!.amount.toStringAsFixed(2)} ₪ — ${_lastInvoice!.customerName}'
                        : 'لا يوجد',
                    Icons.receipt_long_rounded,
                    isDark,
                  ),
                ),
              ],
            ),
          // ── Quick stats row ──────────────────────────────────────────
          if (details != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniStat('مرفوع', '${details.customersUploaded + details.invoicesUploaded}', Icons.upload_rounded, Colors.green, isDark),
                const SizedBox(width: 16),
                _buildMiniStat('محمّل', '${details.customersDownloaded + details.invoicesDownloaded}', Icons.download_rounded, Colors.blue, isDark),
                if (details.mergedCustomers.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  _buildMiniStat('مدموج', '${details.mergedCustomers.length}', Icons.merge_type_rounded, Colors.orange, isDark),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)), 
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 24, color: color)),
            const Spacer(),
            Text(title, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF64748B), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A)), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
