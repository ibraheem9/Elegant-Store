import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
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
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const DashboardHomeScreen(),
      const SalesScreen(),
      const StatisticsScreen(),
      const PurchasesScreen(),
      const CustomersScreen(),
      const PaymentsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elegant Store'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Consumer<AuthService>(
                builder: (context, authService, _) {
                  return Text(
                    authService.currentUser?.name ?? 'User',
                    style: const TextStyle(fontSize: 14),
                  );
                },
              ),
            ),
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Logout'),
                onTap: () {
                  context.read<AuthService>().logout();
                  Navigator.of(context).pushReplacementNamed('/login');
                },
              ),
            ],
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Statistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Purchases',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Customers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payment),
            label: 'Payments',
          ),
        ],
      ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dbService = context.read<DatabaseService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E3A8A),
                  const Color(0xFF3B82F6),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Consumer<AuthService>(
              builder: (context, authService, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome back!',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      authService.currentUser?.name ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Stats cards
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Pending invoices
          FutureBuilder(
            future: dbService.getPendingInvoices(),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              final total = snapshot.data
                      ?.fold<double>(0, (sum, inv) => sum + inv.amount) ??
                  0;

              return StatCard(
                title: 'Pending Invoices',
                value: count.toString(),
                subtitle: 'Total: ₪${total.toStringAsFixed(2)}',
                icon: Icons.receipt,
                color: Colors.orange,
              );
            },
          ),
          const SizedBox(height: 12),

          // Total customers
          FutureBuilder(
            future: dbService.getCustomers(),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;

              return StatCard(
                title: 'Total Customers',
                value: count.toString(),
                subtitle: 'Active customers',
                icon: Icons.people,
                color: Colors.blue,
              );
            },
          ),
          const SizedBox(height: 12),

          // Today's sales
          FutureBuilder(
            future: dbService.getTodayInvoices(),
            builder: (context, snapshot) {
              final total = snapshot.data
                      ?.fold<double>(0, (sum, inv) => sum + inv.amount) ??
                  0;

              return StatCard(
                title: 'Today\'s Sales',
                value: '₪${total.toStringAsFixed(2)}',
                subtitle: '${snapshot.data?.length ?? 0} invoices',
                icon: Icons.trending_up,
                color: Colors.green,
              );
            },
          ),
          const SizedBox(height: 12),

          // Today's purchases
          FutureBuilder(
            future: dbService.getTodayPurchases(),
            builder: (context, snapshot) {
              final total = snapshot.data
                      ?.fold<double>(0, (sum, purchase) => sum + purchase.amount) ??
                  0;

              return StatCard(
                title: 'Today\'s Purchases',
                value: '₪${total.toStringAsFixed(2)}',
                subtitle: '${snapshot.data?.length ?? 0} purchases',
                icon: Icons.shopping_cart,
                color: Colors.red,
              );
            },
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const StatCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
