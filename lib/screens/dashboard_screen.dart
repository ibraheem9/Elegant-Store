import 'help_screen.dart';
import '../utils/app_snackbar.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/notification_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../models/models.dart';
import 'sales_screen.dart';
import 'statistics_screen.dart';
import 'purchases_screen.dart';
import 'customers_screen.dart';
import 'payments_screen.dart';
import 'settings_screen.dart';
import 'payment_methods_screen.dart';
import 'purchases_methods_screen.dart';
import 'recycle_bin_screen.dart';
import 'notifications_screen.dart';
import 'accountants_screen.dart';
import 'customer_balances_screen.dart';
import 'unpaid_invoices_screen.dart';
import 'contact_us_screen.dart';
import 'about_us_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  int _previousIndex = 0;

  void setSelectedIndex(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
  }
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<PaymentMethodsScreenState> _paymentMethodsKey = GlobalKey<PaymentMethodsScreenState>();
  final GlobalKey<PurchasesMethodsScreenState> _purchasesMethodsKey = GlobalKey<PurchasesMethodsScreenState>();

  @override
  void initState() {
    super.initState();
    _checkRecoveryKeyConfirmation();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenTutorial = prefs.getBool('has_seen_tutorial') ?? false;

    if (!hasSeenTutorial && mounted) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          // Tutorial removed as requested
          prefs.setBool('has_seen_tutorial', true);
        }
      });
    }
  }

  Future<void> _checkRecoveryKeyConfirmation() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final bool isConfirmed = prefs.getBool('recovery_confirmed_${user.uuid}') ?? false;

    if (!isConfirmed && mounted) {
      // Small delay to ensure the context is ready
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _showRecoveryKeyConfirmationDialog(user);
      });
    }
  }

  void _showRecoveryKeyConfirmationDialog(User user) {
    bool isChecked = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('تنبيه أمان هام', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 10),
                Icon(Icons.security_rounded, color: Colors.orange, size: 28),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'هذا هو "مفتاح الاستعادة" الخاص بك. ستحتاجه لاستعادة حسابك في حال نسيان كلمة المرور.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.blue, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: user.uuid));
                          AppSnackBar.success(context, 'تم نسخ مفتاح الاستعادة');
                        },
                        tooltip: 'نسخ',
                      ),
                      Expanded(
                        child: Text(
                          user.uuid,
                          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'يرجى نسخ هذا الرمز وحفظه في مكان آمن جداً (خارج الهاتف). لن يتمكن أحد من استعادة حسابك بدونه.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                CheckboxListTile(
                  value: isChecked,
                  onChanged: (val) => setDialogState(() => isChecked = val ?? false),
                  title: const Text('أقر بأنني قمت بحفظ هذا المفتاح في مكان آمن ولن أفقده.', textAlign: TextAlign.right, style: TextStyle(fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.blue,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: !isChecked ? null : () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('recovery_confirmed_${user.uuid}', true);
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('تأكيد وحفظ', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      case 8: return const UnpaidInvoicesScreen();
      case 9: return PaymentMethodsScreen(key: _paymentMethodsKey);
      case 10: return PurchasesMethodsScreen(key: _purchasesMethodsKey);
      case 11: return const RecycleBinScreen();
      case 12: return const SettingsScreen();
      case 13: return const ContactUsScreen();
      case 14: return const AboutUsScreen();
      case 15: return const ProfileScreen();
      case 16: return const HelpScreen();
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
      case 8: return 'الفواتير غير المدفوعة';
      case 9: return 'طرق دفع المبيعات';
      case 10: return 'طرق دفع المشتريات';
      case 11: return 'سلة المحذوفات';
      case 12: return 'الإعدادات والسمة';
      case 13: return 'تواصل معنا';
      case 14: return 'عن المطور';
      case 15: return 'الملف الشخصي للمتجر';
      case 16: return 'دليل الاستخدام';
      default: return 'Abd Elhadi Store';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.read<AuthService>();

    final bool isMobile = width < 700;
    final bool isTablet = width >= 700 && width < 1100;
    final bool isDesktop = width >= 1100;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: _buildMobileDrawer(isDark, auth),
      body: Row(
        children: [
          if (isDesktop) _buildFullSidebar(theme, isDark, auth),
          if (isTablet) _buildNavigationRail(theme, isDark, auth),
          Expanded(
            child: Column(
              children: [
                _buildAdaptiveAppBar(theme, width, !isDesktop && !isTablet, isDark),
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Logo hidden as requested: اخفي الشعار منها
                const SizedBox(height: 60),
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(8, 'الفواتير غير المدفوعة', Icons.unpublished_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                if (auth.isManager())
                  _buildSidebarItem(5, 'إدارة الموظفين', Icons.badge_rounded),
                _buildSidebarItem(6, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(7, 'أرصدة الزبائن', Icons.account_balance_wallet_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(9, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(10, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(11, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(15, 'الملف الشخصي للمتجر', Icons.store_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(12, 'الإعدادات والسمة', Icons.settings_rounded),
                _buildSidebarItem(13, 'تواصل معنا', Icons.contact_support_rounded),
                _buildSidebarItem(14, 'عن المطور', Icons.info_outline_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(16, 'دليل الاستخدام', Icons.help_outline_rounded),
                const SizedBox(height: 20),
              ],
            ),
          ),
          _buildUserCard(true, isDark),
          const SafeArea(top: false, child: SizedBox(height: 10)),
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSidebarHeader(),
                const SizedBox(height: 5),
                _buildSidebarItem(0, 'لوحة التحكم', Icons.dashboard_rounded),
                _buildSidebarItem(1, 'شاشة البيع', Icons.receipt_long_rounded),
                _buildSidebarItem(8, 'الفواتير غير المدفوعة', Icons.unpublished_rounded),
                _buildSidebarItem(2, 'إحصائيات اليوم', Icons.bar_chart_rounded),
                _buildSidebarItem(3, 'المشتريات', Icons.shopping_cart_rounded),
                _buildSidebarItem(4, 'إدارة الزبائن', Icons.people_alt_rounded),
                if (auth.isManager())
                  _buildSidebarItem(5, 'إدارة الموظفين', Icons.badge_rounded),
                _buildSidebarItem(6, 'مراجعة المدفوعات', Icons.payments_rounded),
                _buildSidebarItem(7, 'أرصدة الزبائن', Icons.account_balance_wallet_rounded),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  child: Divider(color: Colors.white10),
                ),
                _buildSidebarItem(9, 'طرق دفع المبيعات', Icons.payment_rounded),
                _buildSidebarItem(10, 'طرق دفع المشتريات', Icons.account_balance_rounded),
                _buildSidebarItem(11, 'سلة المحذوفات', Icons.delete_sweep_rounded),
                _buildSidebarItem(15, 'الملف الشخصي للمتجر', Icons.store_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(12, 'الإعدادات والسمة', Icons.settings_rounded),
                _buildSidebarItem(13, 'تواصل معنا', Icons.contact_support_rounded),
                _buildSidebarItem(14, 'عن المطور', Icons.info_outline_rounded),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _buildSidebarItem(16, 'دليل الاستخدام', Icons.help_outline_rounded),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildUserCard(false, isDark),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ThemeData theme, bool isDark, AuthService auth) {
    int getRailIndex() {
      bool isManager = auth.isManager();
      // Map all indices to rail indices
      switch (_selectedIndex) {
        case 0: return 0;
        case 1: return 1;
        case 2: return 2;
        case 3: return 3;
        case 4: return 4;
        case 5: return 5; // Accountants (Manager only)
        case 6: return isManager ? 6 : 5;
        case 9: return isManager ? 7 : 6;
        case 10: return isManager ? 7 : 6;
        case 11: return isManager ? 8 : 7;
        case 12: return isManager ? 9 : 8;
        case 13: return isManager ? 10 : 9;
        case 14: return isManager ? 11 : 10;
        case 15: return isManager ? 12 : 11;
        default: return 0;
      }
    }

    return NavigationRail(
      backgroundColor: const Color(0xFF0F172A),
      selectedIndex: getRailIndex(),
      onDestinationSelected: (int index) {
        bool isManager = auth.isManager();
        int targetScreen;
        
        // Dynamic mapping based on manager status
        if (isManager) {
          switch (index) {
            case 0: targetScreen = 0; break;
            case 1: targetScreen = 1; break;
            case 2: targetScreen = 2; break;
            case 3: targetScreen = 3; break;
            case 4: targetScreen = 4; break;
            case 5: targetScreen = 5; break;
            case 6: targetScreen = 6; break;
            case 7: targetScreen = 9; break;
            case 8: targetScreen = 11; break;
            case 9: targetScreen = 12; break;
            case 10: targetScreen = 13; break;
            case 11: targetScreen = 14; break;
            case 12: targetScreen = 15; break;
            default: targetScreen = 0;
          }
        } else {
          switch (index) {
            case 0: targetScreen = 0; break;
            case 1: targetScreen = 1; break;
            case 2: targetScreen = 2; break;
            case 3: targetScreen = 3; break;
            case 4: targetScreen = 4; break;
            case 5: targetScreen = 6; break;
            case 6: targetScreen = 9; break;
            case 7: targetScreen = 11; break;
            case 8: targetScreen = 12; break;
            case 9: targetScreen = 13; break;
            case 10: targetScreen = 14; break;
            case 11: targetScreen = 15; break;
            default: targetScreen = 0;
          }
        }
        setState(() => _selectedIndex = targetScreen);
      },
      labelType: NavigationRailLabelType.none,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Image.asset('assets/icon.png', height: 32),
      ),
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.dashboard_rounded, color: Colors.white60), selectedIcon: Icon(Icons.dashboard_rounded), label: Text('لوحة التحكم')),
        const NavigationRailDestination(icon: Icon(Icons.receipt_long_rounded, color: Colors.white60), selectedIcon: Icon(Icons.receipt_long_rounded), label: Text('شاشة البيع')),
        const NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded, color: Colors.white60), selectedIcon: Icon(Icons.bar_chart_rounded), label: Text('إحصائيات اليوم')),
        const NavigationRailDestination(icon: Icon(Icons.shopping_cart_rounded, color: Colors.white60), selectedIcon: Icon(Icons.shopping_cart_rounded), label: Text('المشتريات')),
        const NavigationRailDestination(icon: Icon(Icons.people_alt_rounded, color: Colors.white60), selectedIcon: Icon(Icons.people_alt_rounded), label: Text('إدارة الزبائن')),
        if (auth.isManager())
          const NavigationRailDestination(icon: Icon(Icons.badge_rounded, color: Colors.white60), selectedIcon: Icon(Icons.badge_rounded), label: Text('إدارة الموظفين')),
        const NavigationRailDestination(icon: Icon(Icons.payments_rounded, color: Colors.white60), selectedIcon: Icon(Icons.payments_rounded), label: Text('مراجعة المدفوعات')),
        const NavigationRailDestination(icon: Icon(Icons.payment_rounded, color: Colors.white60), selectedIcon: Icon(Icons.payment_rounded), label: Text('طرق الدفع')),
        const NavigationRailDestination(icon: Icon(Icons.delete_sweep_rounded, color: Colors.white60), selectedIcon: Icon(Icons.delete_sweep_rounded), label: Text('المحذوفات')),
        const NavigationRailDestination(icon: Icon(Icons.settings_rounded, color: Colors.white60), selectedIcon: Icon(Icons.settings_rounded), label: Text('الإعدادات')),
        const NavigationRailDestination(icon: Icon(Icons.contact_support_rounded, color: Colors.white60), selectedIcon: Icon(Icons.contact_support_rounded), label: Text('تواصل معنا')),
        const NavigationRailDestination(icon: Icon(Icons.info_outline_rounded, color: Colors.white60), selectedIcon: Icon(Icons.info_outline_rounded), label: Text('عن المطور')),
        const NavigationRailDestination(icon: Icon(Icons.store_rounded, color: Colors.white60), selectedIcon: Icon(Icons.store_rounded), label: Text('الملف الشخصي')),
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
        indicatorColor: Colors.blue.withValues(alpha: 0.2),
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
        leading: Icon(icon, color: isSelected ? Colors.white : Colors.white60, size: 22),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        selectedTileColor: Colors.white.withValues(alpha: 0.15),
      ),
    );
  }

  Widget _buildUserCard(bool isDrawer, bool isDark) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    String roleLabel = 'محاسب';
    if (auth.isDeveloper()) {
      roleLabel = 'مطور النظام';
    } else if (auth.isManager()) {
      roleLabel = 'مدير المتجر';
    } else if (auth.isAccountant()) {
      roleLabel = 'محاسب';
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
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
                Text(roleLabel, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white54, size: 18),
            tooltip: 'تسجيل الخروج',
            onPressed: _handleLogout,
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
    return NotificationBadge(isDark: isDark);
  }

  /// Shows a confirmation dialog, runs a pre-logout sync with a progress
  /// indicator, then calls [AuthService.logout] to sign the user out.
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.logout_rounded, color: Colors.red),
          ],
        ),
        content: const Text(
          'هل تريد تسجيل الخروج؟',
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.start,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('تسجيل الخروج'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show a non-dismissible sync progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text(
                'جاري تسجيل الخروج...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'يُرجى الانتظار...',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    // Run sync then logout (non-blocking if offline)
    final auth = context.read<AuthService>();
    await auth.logout();

    // Close the progress dialog if still open
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({super.key});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
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
              const SizedBox(height: 12),
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
                        future: db.notificationRepo.getTotalCount(),
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
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
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
