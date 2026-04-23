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
import 'customer_balances_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<PaymentMethodsScreenState> _paymentMethodsKey = GlobalKey<PaymentMethodsScreenState>();
  final GlobalKey<PurchasesMethodsScreenState> _purchasesMethodsKey = GlobalKey<PurchasesMethodsScreenState>();

  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const DashboardHomeScreen();
      case 1: return const SalesScreen();
      case 2: return const StatisticsScreen();
      case 3: return const PurchasesScreen();
      case 4: return const CustomersScreen();
      case 5: return const AccountantsScreen();
      case 6: return const PaymentsScreen();
      case 7: return const CustomerBalancesScreen();
      case 8: return const CalendarScreen();
      case 9: return PaymentMethodsScreen(key: _paymentMethodsKey);
      case 10: return PurchasesMethodsScreen(key: _purchasesMethodsKey);
      case 11: return const RecycleBinScreen();
      case 12: return const SettingsScreen();
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
      case 7: return 'أرصدة الزبائن';
      case 8: return 'التقويم المالي';
      case 9: return 'طرق دفع المبيعات';
      case 10: return 'طرق دفع المشتريات';
      case 11: return 'سلة المحذوفات';
      case 12: return 'الإعدادات والسمة';
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
          // Logo hidden as requested: اخفي الشعار منها
          const SizedBox(height: 60), 
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
                _buildSidebarItem(7, 'أرصدة الزبائن', Icons.account_balance_wallet_rounded),
                _buildSidebarItem(8, 'التقويم المالي', Icons.calendar_month_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(9, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(10, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(11, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(12, 'الإعدادات والسمة', Icons.settings_rounded),
              ],
            ),
          ),
          // Raised to be fully visible: رفع لاعلى لانه لا يظهر بشكل كامل
          SafeArea(
            top: false,
            child: _buildUserCard(true, isDark),
          ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                if (auth.isManager())
                   _buildSidebarItem(5, 'إدارة الموظفين', Icons.badge_rounded),
                _buildSidebarItem(6, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(7, 'أرصدة الزبائن', Icons.account_balance_wallet_rounded),
                _buildSidebarItem(8, 'التقويم المالي', Icons.calendar_month_rounded),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  child: Divider(color: Colors.white10),
                ),
                _buildSidebarItem(9, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(10, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(11, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(12, 'الإعدادات والسمة', Icons.settings_rounded),
              ],
            ),
          ),
          _buildUserCard(false, isDark),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ThemeData theme, bool isDark, AuthService auth) {
    return NavigationRail(
      backgroundColor: const Color(0xFF0F172A),
      selectedIndex: _selectedIndex,
      onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
      labelType: NavigationRailLabelType.none,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Image.asset('assets/logo.png', height: 40),
      ),
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.dashboard_rounded, color: Colors.white60), selectedIcon: Icon(Icons.dashboard_rounded, color: Colors.blue), label: Text('لوحة التحكم')),
        const NavigationRailDestination(icon: Icon(Icons.receipt_long_rounded, color: Colors.white60), selectedIcon: Icon(Icons.receipt_long_rounded, color: Colors.blue), label: Text('شاشة البيع')),
        const NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded, color: Colors.white60), selectedIcon: Icon(Icons.bar_chart_rounded, color: Colors.blue), label: Text('إحصائيات اليوم')),
        const NavigationRailDestination(icon: Icon(Icons.shopping_cart_rounded, color: Colors.white60), selectedIcon: Icon(Icons.shopping_cart_rounded, color: Colors.blue), label: Text('المشتريات')),
        const NavigationRailDestination(icon: Icon(Icons.people_alt_rounded, color: Colors.white60), selectedIcon: Icon(Icons.people_alt_rounded, color: Colors.blue), label: Text('إدارة الزبائن')),
        if (auth.isManager())
          const NavigationRailDestination(icon: Icon(Icons.badge_rounded, color: Colors.white60), selectedIcon: Icon(Icons.badge_rounded, color: Colors.blue), label: Text('إدارة الموظفين')),
        const NavigationRailDestination(icon: Icon(Icons.payments_rounded, color: Colors.white60), selectedIcon: Icon(Icons.payments_rounded, color: Colors.blue), label: Text('مراجعة المدفوعات')),
        const NavigationRailDestination(icon: Icon(Icons.calendar_month_rounded, color: Colors.white60), selectedIcon: Icon(Icons.calendar_month_rounded, color: Colors.blue), label: Text('التقويم المالي')),
        const NavigationRailDestination(icon: Icon(Icons.payment_rounded, color: Colors.white60), selectedIcon: Icon(Icons.payment_rounded, color: Colors.blue), label: Text('طرق الدفع')),
        const NavigationRailDestination(icon: Icon(Icons.delete_sweep_rounded, color: Colors.white60), selectedIcon: Icon(Icons.delete_sweep_rounded, color: Colors.blue), label: Text('المحذوفات')),
        const NavigationRailDestination(icon: Icon(Icons.settings_rounded, color: Colors.white60), selectedIcon: Icon(Icons.settings_rounded, color: Colors.blue), label: Text('الإعدادات')),
      ],
    );
  }

  Widget _buildBottomNav(ThemeData theme, AuthService auth) {
    // Current mapping in _getScreen:
    // 0: الرئيسية (Dashboard)
    // 1: البيع (Sales)
    // 2: الإحصائيات (Statistics)
    // 3: المشتريات (Purchases)
    // 4: الزبائن (Customers)
    
    // Desired Order (Right to Left in Arabic Layout):
    // [0] البيع (Sales) - Screen 1
    // [1] الزبائن (Customers) - Screen 4
    // [2] الرئيسية (Home) - Screen 0
    // [3] إحصائيات اليوم (Stats) - Screen 2
    // [4] المشتريات (Purchases) - Screen 3

    int getNavIndex() {
      switch (_selectedIndex) {
        case 1: return 0; // Sales
        case 4: return 1; // Customers
        case 0: return 2; // Home
        case 2: return 3; // Stats
        case 3: return 4; // Purchases
        default: return 2; // Default to Home
      }
    }

    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: Colors.blue.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue);
          }
          return const TextStyle(fontSize: 12, color: Colors.grey);
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: Colors.blue);
          }
          return const IconThemeData(color: Colors.grey);
        }),
      ),
      child: NavigationBar(
        selectedIndex: getNavIndex(),
        onDestinationSelected: (index) {
          int targetScreen;
          switch (index) {
            case 0: targetScreen = 1; break; // Sales
            case 1: targetScreen = 4; break; // Customers
            case 2: targetScreen = 0; break; // Home
            case 3: targetScreen = 2; break; // Stats
            case 4: targetScreen = 3; break; // Purchases
            default: targetScreen = 0;
          }
          setState(() => _selectedIndex = targetScreen);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'البيع'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: 'الزبائن'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'الإحصائيات'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart_rounded), label: 'المشتريات'),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
      child: Center(
        child: Image.asset(
          'assets/logo.png',
          height: 56,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              Image.asset('assets/icon.png', height: 48, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon) {
    bool isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          setState(() {
            _previousIndex = _selectedIndex;
            _selectedIndex = index;
          });
          if (MediaQuery.of(context).size.width < 650) Navigator.pop(context);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: isSelected ? Colors.blue : Colors.white60, size: 22),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        selectedTileColor: Colors.blue.withOpacity(0.15),
      ),
    );
  }

  Widget _buildUserCard(bool isDrawer, bool isDark) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.1))),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.blue, radius: 18, child: Text(user?.name.substring(0, 1).toUpperCase() ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user?.name ?? 'المستخدم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                Text(user?.role == 'manager' ? 'مدير النظام' : 'محاسب', style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white54, size: 18),
            onPressed: () => auth.logout(),
          ),
        ],
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
            // Back button for sub-screens (payment methods 9 & 10)
            if (_selectedIndex == 9 || _selectedIndex == 10)
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white : Colors.black87),
                tooltip: 'رجوع',
                onPressed: () {
                  // If currently in reorder mode, exit it instead of navigating away
                  if (_selectedIndex == 9) {
                    final s = _paymentMethodsKey.currentState;
                    if (s != null && s.isReordering) { s.exitReorderMode(); return; }
                  } else if (_selectedIndex == 10) {
                    final s = _purchasesMethodsKey.currentState;
                    if (s != null && s.isReordering) { s.exitReorderMode(); return; }
                  }
                  setState(() => _selectedIndex = _previousIndex);
                },
              )
            else if (isMobile)
              IconButton(
                icon: Icon(Icons.menu_rounded, color: isDark ? Colors.white : Colors.black87),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getScreenTitle(_selectedIndex),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: isMobile ? 17 : 20,
                  color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildNotificationIcon(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(bool isDark) {
    return Consumer<DatabaseService>(
      builder: (context, db, _) => FutureBuilder<int>(
        future: db.getSmartNotificationsCount(),
        builder: (context, snap) {
          final count = snap.data ?? 0;
          return Stack(
            children: [
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  );
                  // Rebuild badge after returning from notifications
                  if (mounted) setState(() {});
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                    color: count > 0 ? Colors.orange : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF64748B)),
                    size: 22,
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          );
        },
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
  SyncService? _syncService;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncService = context.read<SyncService>();
        _syncService!.addListener(_onSyncStatusChanged);
      }
    });
  }

  @override
  void dispose() {
    _syncService?.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (!mounted) return;
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 650;
    int crossAxisCount = (size.width > 1400) ? 4 : 2;
    final db = context.read<DatabaseService>();

    return Consumer<SyncService>(
      builder: (context, syncService, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: isMobile ? 1.05 : 1.5,
                    children: [
                      _buildStatCard('إجمالي الديون القائمة', '${stats['total_debts'].toStringAsFixed(2)} ₪', Icons.money_off_rounded, const Color(0xFFEF4444), isDark),
                      _buildStatCard('إجمالي الأرصدة المودعة', '${stats['total_balances'].toStringAsFixed(2)} ₪', Icons.account_balance_rounded, const Color(0xFF10B981), isDark),
                      _buildStatCard('عدد الزبائن الكلي', '${stats['total_customers']}', Icons.group_rounded, const Color(0xFF3B82F6), isDark),
                      FutureBuilder<int>(
                        future: db.getSmartNotificationsCount(),
                        builder: (ctx, snap) {
                          final cnt = snap.data ?? 0;
                          return _buildStatCard('تنبيهات غير مسددة', '$cnt', Icons.warning_amber_rounded, Colors.orange, isDark, onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
                          });
                        },
                      ),
                      FutureBuilder<Map<String, dynamic>>(
                        future: db.getSalesStats(
                          start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                          end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
                        ),
                        builder: (ctx, snap) {
                          final total = (snap.data?['total_sales'] ?? 0.0) as double;
                          return _buildStatCard('إجمالي مبيعات اليوم', '${total.toStringAsFixed(2)} ₪', Icons.trending_up_rounded, const Color(0xFF8B5CF6), isDark);
                        },
                      ),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── More Details button ────────────────────────────────────────────────
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'حالة المزامنة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.blue[300] : Colors.blue[800],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.cloud_done_rounded,
                      size: 20,
                      color: details != null ? Colors.green : Colors.grey),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Last sync time ───────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('آخر مزامنة:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(lastSyncDisplay, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.access_time_rounded, size: 18, color: Colors.grey),
            ],
          ),
          
          // ── Quick stats row ──────────────────────────────────────────
          if (details != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (details.mergedCustomers.isNotEmpty) ...[
                  _buildMiniStat('مدموج', '${details.mergedCustomers.length}', Icons.merge_type_rounded, Colors.orange, isDark),
                  const SizedBox(width: 16),
                ],
                // Uploaded / Downloaded counts
                _buildMiniStat('محمّل', '${details.customersDownloaded + details.invoicesDownloaded}', Icons.download_rounded, Colors.blue, isDark),
                const SizedBox(width: 16),
                _buildMiniStat('مرفوع', '${details.customersUploaded + details.invoicesUploaded}', Icons.upload_rounded, Colors.green, isDark),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey[600], fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
