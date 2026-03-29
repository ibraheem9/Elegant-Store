import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'sales_screen.dart';
import 'statistics_screen.dart';
import 'purchases_screen.dart';
import 'customers_screen.dart';
import 'payments_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // Function to return the screen based on index - this ensures fresh state
  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const DashboardHomeScreen();
      case 1: return const SalesScreen();
      case 2: return const StatisticsScreen();
      case 3: return const PurchasesScreen();
      case 4: return const CustomersScreen();
      case 5: return const PaymentsScreen();
      case 6: return const CalendarScreen();
      case 7: return const ReportsScreen();
      case 8: return const SettingsScreen();
      default: return const DashboardHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;

    final bool isMobile = width < 650;
    final bool isTablet = width >= 650 && width < 1100;
    final bool isDesktop = width >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          if (isDesktop) _buildFullSidebar(theme),
          if (isTablet) _buildNavigationRail(theme),
          Expanded(
            child: Column(
              children: [
                _buildAdaptiveAppBar(theme, width, isMobile),
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
      bottomNavigationBar: isMobile ? _buildBottomNav(theme) : null,
    );
  }

  Widget _buildFullSidebar(ThemeData theme) {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          _buildSidebarHeader(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                _buildSidebarItem(5, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(6, 'التقويم المالي', Icons.calendar_month_rounded),
                _buildSidebarItem(7, 'التقارير التحليلية', Icons.pie_chart_rounded),
                _buildSidebarItem(8, 'الإعدادات والسمة', Icons.settings_rounded),
              ],
            ),
          ),
          _buildUserCard(true),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ThemeData theme) {
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
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text('الرئيسية')),
        NavigationRailDestination(icon: Icon(Icons.receipt_long_rounded), label: Text('البيع')),
        NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded), label: Text('الإحصائيات')),
        NavigationRailDestination(icon: Icon(Icons.shopping_cart_rounded), label: Text('المشتريات')),
        NavigationRailDestination(icon: Icon(Icons.people_alt_rounded), label: Text('الزبائن')),
        NavigationRailDestination(icon: Icon(Icons.payments_rounded), label: Text('المدفوعات')),
        NavigationRailDestination(icon: Icon(Icons.calendar_month_rounded), label: Text('التقويم')),
        NavigationRailDestination(icon: Icon(Icons.pie_chart_rounded), label: Text('التقارير')),
        NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('الإعدادات')),
      ],
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue[700],
      unselectedItemColor: const Color(0xFF94A3B8),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'البيع'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'الإحصائيات'),
        BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_rounded), label: 'المشتريات'),
        BottomNavigationBarItem(icon: Icon(Icons.pie_chart_rounded), label: 'التقارير'),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            height: 50,
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.storefront_rounded, color: Colors.blue, size: 28),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(child: Text('Elegant Store', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon) {
    bool isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? Colors.blue : const Color(0xFF94A3B8), size: 22),
              const SizedBox(width: 16),
              Text(title, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8), fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(bool isFull) {
    return Padding(
      padding: const EdgeInsets.all(24),
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
    );
  }

  Widget _buildAdaptiveAppBar(ThemeData theme, double width, bool isMobile) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Row(
        children: [
          if (width < 1100 && !isMobile) const Text('Elegant Store', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
          if (isMobile) Image.asset('assets/logo.png', height: 35, errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront_rounded, color: Colors.blue, size: 28)),
          const Spacer(),
          _buildNotificationIcon(),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon() {
    return Consumer<DatabaseService>(
      builder: (context, db, _) => FutureBuilder<Map<String, dynamic>>(
        future: db.getGlobalStats(),
        builder: (context, snap) {
          bool hasAlert = (snap.data?['unpaid_non_permanent_count'] ?? 0) > 0;
          return Stack(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle), child: const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B), size: 22)),
              if (hasAlert) Positioned(right: 2, top: 2, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ],
          );
        }
      ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 650;
    int crossAxisCount = (size.width > 1400) ? 4 : (size.width > 900 ? 2 : 1);
    final db = context.read<DatabaseService>();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('لوحة التحكم', style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
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
                  _buildStatCard('إجمالي الديون القائمة', '${stats['total_debts'].toStringAsFixed(2)} ₪', Icons.money_off_rounded, const Color(0xFFEF4444)),
                  _buildStatCard('إجمالي الأرصدة المودعة', '${stats['total_balances'].toStringAsFixed(2)} ₪', Icons.account_balance_rounded, const Color(0xFF10B981)),
                  _buildStatCard('عدد الزبائن الكلي', '${stats['total_customers']}', Icons.group_rounded, const Color(0xFF3B82F6)),
                  _buildStatCard('تنبيهات غير مسددة', '${stats['unpaid_non_permanent_count'] ?? 0}', Icons.warning_amber_rounded, Colors.orange),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 24, color: color)),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}
