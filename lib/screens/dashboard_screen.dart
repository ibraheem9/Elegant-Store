import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'sales_screen.dart';
import 'statistics_screen.dart';
import 'purchases_screen.dart';
import 'customers_screen.dart';
import 'payments_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardHomeScreen(),
    const SalesScreen(),
    const StatisticsScreen(),
    const PurchasesScreen(),
    const CustomersScreen(),
    const PaymentsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront_rounded, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'Elegant Store',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Consumer<AuthService>(
                builder: (context, auth, _) => Text(
                  'مرحباً، ${auth.currentUser?.name ?? "المستخدم"}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: () {
              Provider.of<AuthService>(context, listen: false).logout();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              selectedIconTheme: IconThemeData(color: theme.primaryColor),
              unselectedIconTheme: const IconThemeData(color: Colors.grey),
              selectedLabelTextStyle: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold),
              unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
              elevation: 4,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text('الرئيسية')),
                NavigationRailDestination(icon: Icon(Icons.receipt_rounded), label: Text('البيع')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded), label: Text('الإحصائيات')),
                NavigationRailDestination(icon: Icon(Icons.shopping_cart_rounded), label: Text('المشتريات')),
                NavigationRailDestination(icon: Icon(Icons.people_rounded), label: Text('الزبائن')),
                NavigationRailDestination(icon: Icon(Icons.payments_rounded), label: Text('المدفوعات')),
              ],
            ),
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: _screens[_selectedIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: theme.primaryColor,
              unselectedItemColor: Colors.grey,
              backgroundColor: Colors.white,
              elevation: 8,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
                BottomNavigationBarItem(icon: Icon(Icons.receipt_rounded), label: 'البيع'),
                BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'الإحصائيات'),
                BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_rounded), label: 'المشتريات'),
                BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'الزبائن'),
                BottomNavigationBarItem(icon: Icon(Icons.payments_rounded), label: 'المدفوعات'),
              ],
            ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final crossAxisCount = size.width > 1200 ? 4 : (size.width > 800 ? 3 : 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'لوحة التحكم',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'نظرة عامة على أداء المتجر لليوم',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 32),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 1.2,
            children: [
              _buildStatCard('إجمالي المبيعات', '1,250 ₪', Icons.trending_up_rounded, Colors.blue),
              _buildStatCard('فواتير معلقة', '8', Icons.receipt_long_rounded, Colors.orange),
              _buildStatCard('إجمالي الديون', '450 ₪', Icons.money_off_rounded, Colors.red),
              _buildStatCard('الزبائن النشطين', '24', Icons.people_rounded, Colors.green),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'العمليات السريعة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildQuickAction(context, 'فاتورة جديدة', Icons.add_shopping_cart_rounded, Colors.blue),
              _buildQuickAction(context, 'إضافة زبون', Icons.person_add_rounded, Colors.green),
              _buildQuickAction(context, 'تسجيل مشتريات', Icons.inventory_2_rounded, Colors.orange),
              _buildQuickAction(context, 'تحصيل دفعات', Icons.payments_rounded, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, String title, IconData icon, Color color) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
