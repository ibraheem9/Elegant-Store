import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'customers_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  String _activeFilter = 'today'; // today, week, month, custom

  List<Invoice> _unpaidInvoices = [];
  List<Invoice> _paidInvoices = [];
  List<PaymentMethod> _saleMethods = [];
  Map<int, double> _methodTotals = {};
  bool _isLoading = false;
  String _searchQuery = "";
  String _sortBy = "name"; // name, date, amount
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setFilter('today');
  }

  void _setFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _activeFilter = filter;
      if (filter == 'today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'week') {
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final methods = await db.getPaymentMethods(category: 'SALE');
      final allInvoices = await db.getInvoices(start: _startDate, end: _endDate);

      Map<int, double> totals = {};
      for (var m in methods) {
        if (m.type == 'app') {
          double sum = allInvoices
              .where((inv) => inv.paymentMethodId == m.id && (inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid'))
              .fold(0, (prev, element) => prev + element.amount);
          totals[m.id!] = sum;
        }
      }

      setState(() {
        _saleMethods = methods;
        _methodTotals = totals;
        _unpaidInvoices = allInvoices.where((inv) => 
          (inv.paymentStatus == 'UNPAID' || inv.paymentStatus == 'pending')
        ).toList();

        _paidInvoices = allInvoices.where((inv) => 
          inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid' || inv.paymentStatus == 'PARTIAL'
        ).toList();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading payments data: $e");
      setState(() => _isLoading = false);
    }
  }

  List<Invoice> _processList(List<Invoice> list) {
    List<Invoice> filtered = list;
    if (_searchQuery.isNotEmpty) {
      filtered = list.where((inv) => 
        (inv.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
        (inv.amount.toString().contains(_searchQuery))
      ).toList();
    }

    filtered.sort((a, b) {
      int result = 0;
      if (_sortBy == 'name') {
        result = (a.customerName ?? '').compareTo(b.customerName ?? '');
      } else if (_sortBy == 'date') {
        result = a.createdAt.compareTo(b.createdAt);
      } else if (_sortBy == 'amount') {
        result = a.amount.compareTo(b.amount);
      }
      return _isAscending ? result : -result;
    });

    return filtered;
  }

  Future<void> _confirmPayment(Invoice inv, PaymentMethod selectedMethod) async {
    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    final currentUser = auth.currentUser;

    String timestamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    String editLog = "\n[تمت التسوية: $timestamp بواسطة ${currentUser?.name ?? 'نظام'}]";
    
    String currentNotes = inv.notes ?? "";
    if (currentNotes.contains("[تمت التسوية:")) {
      currentNotes = currentNotes.split("[تمت التسوية:").first.trim();
    }
    String updatedNotes = currentNotes + editLog;

    String newStatus = 'PAID';
    if (selectedMethod.type == 'deferred' || selectedMethod.type == 'unpaid') {
      newStatus = 'UNPAID';
    }

    final updatedInvoice = Invoice(
      id: inv.id,
      userId: inv.userId,
      invoiceDate: inv.invoiceDate,
      amount: inv.amount,
      notes: updatedNotes,
      paymentStatus: newStatus,
      paymentMethodId: selectedMethod.id,
      type: inv.type,
      createdAt: inv.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    );

    await db.updateInvoice(updatedInvoice);
    await db.logEdit(inv.id!, 'INVOICE', 'طريقة الدفع', inv.methodName ?? 'غير محدد', selectedMethod.name);

    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسوية الفاتورة بنجاح'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopBar(isDark, isMobile),
          _buildTabBar(isDark, isMobile),
          Expanded(
            child: _isLoading
               ? const Center(child: CircularProgressIndicator())
               : TabBarView(
                   controller: _tabController,
                   children: [
                     _buildUnpaidTab(isDark, isMobile),
                     _buildPaidTab(isDark, isMobile),
                   ],
                 ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark, bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تسوية ومعالجة المدفوعات', style: TextStyle(fontSize: isMobile ? 22 : 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    if (!isMobile) const Text('متابعة الفواتير المعلقة للزبائن وسجل المدفوعات المكتملة', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              if (!isMobile) _buildFilterBar(isDark),
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 16),
            _buildFilterBar(isDark),
          ],
          const SizedBox(height: 24),
          _buildSearchBar(isDark, isMobile),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
        ),
        child: Row(
          children: [
            _filterBtn('اليوم', 'today', isDark),
            _filterBtn('أسبوع', 'week', isDark),
            _filterBtn('شهر', 'month', isDark),
            _filterBtn('تاريخ', 'custom', isDark, icon: Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  Widget _filterBtn(String label, String value, bool isDark, {IconData? icon}) {
    bool active = _activeFilter == value;
    return GestureDetector(
      onTap: () async {
        if (value == 'custom') {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime(2101),
            initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
          );
          if (picked != null) {
            setState(() {
              _activeFilter = 'custom';
              _startDate = picked.start;
              _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
            });
            _loadData();
          }
        } else {
          _setFilter(value);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54)), const SizedBox(width: 4)],
            Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54), fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: isMobile ? 'بحث...' : 'بحث باسم الزبون أو اللقب أو المبلغ...',
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _buildSortMenu(isDark),
      ],
    );
  }

  Widget _buildSortMenu(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.sort, color: Colors.blue),
        tooltip: 'ترتيب',
        onSelected: (val) {
          if (_sortBy == val) {
            setState(() => _isAscending = !_isAscending);
          } else {
            setState(() {
              _sortBy = val;
              _isAscending = true;
            });
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'name', child: Text('الاسم')),
          const PopupMenuItem(value: 'date', child: Text('التاريخ')),
          const PopupMenuItem(value: 'amount', child: Text('المبلغ')),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark, bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.blue,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'بحاجة لتسوية'),
          Tab(text: 'سجل المدفوعات'),
        ],
      ),
    );
  }

  Widget _buildUnpaidTab(bool isDark, bool isMobile) {
    final list = _processList(_unpaidInvoices);
    return _buildList(list, isDark, true, isMobile);
  }

  Widget _buildPaidTab(bool isDark, bool isMobile) {
    final list = _processList(_paidInvoices);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLaptop = constraints.maxWidth > 900;
        
        if (isLaptop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 320,
                padding: const EdgeInsets.fromLTRB(32, 32, 16, 32),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.analytics_outlined, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('ملخص الحسابات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildAppMethodsSummary(isDark, vertical: true),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, indent: 32, endIndent: 32),
              Expanded(
                child: _buildList(list, isDark, false, false),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildAppMethodsSummary(isDark, vertical: false),
            Expanded(child: _buildList(list, isDark, false, isMobile)),
          ],
        );
      },
    );
  }

  Widget _buildAppMethodsSummary(bool isDark, {bool vertical = false}) {
    final appMethods = _saleMethods.where((m) => m.type == 'app').toList();
    if (appMethods.isEmpty) return const SizedBox.shrink();

    if (vertical) {
      return Column(
        children: appMethods.map((m) {
          final total = _methodTotals[m.id] ?? 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSummaryCard(m.name, total, isDark),
          );
        }).toList(),
      );
    }

    return Container(
      height: 100,
      margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: appMethods.length,
          itemBuilder: (context, index) {
            final m = appMethods[index];
            final total = _methodTotals[m.id] ?? 0.0;
            return Container(
              width: 240,
              margin: const EdgeInsets.only(left: 12),
              child: _buildSummaryCard(m.name, total, isDark),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String name, double total, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                Text('${total.toStringAsFixed(2)} ₪', 
                  style: const TextStyle(color: Colors.blue, fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Invoice> invoices, bool isDark, bool isUnpaidTab, bool isMobile) {
    if (invoices.isEmpty) {
      return Center(child: Text(isUnpaidTab ? 'لا توجد فواتير معلقة' : 'لا توجد فواتير مدفوعة في هذه الفترة'));
    }

    return ListView.builder(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final inv = invoices[index];
        return _buildInvoiceCard(inv, isDark, isUnpaidTab, isMobile);
      },
    );
  }

  void _navigateToCustomerDetails(int customerId) async {
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    try {
      final customer = customers.firstWhere((c) => c.id == customerId);
      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer))).then((_) => _loadData());
    } catch (e) {
      debugPrint("Customer not found: $e");
    }
  }

  Widget _buildInvoiceCard(Invoice inv, bool isDark, bool isUnpaidTab, bool isMobile) {
    PaymentMethod? localSelectedMethod;
    try {
      if (inv.paymentMethodId != null) {
        localSelectedMethod = _saleMethods.firstWhere((m) => m.id == inv.paymentMethodId);
      }
    } catch (_) {}

    Color typeColor = inv.type == 'WITHDRAWAL' ? Colors.orange : (inv.type == 'DEPOSIT' ? Colors.green : Colors.blue);
    String typeLabel = inv.type == 'WITHDRAWAL' ? 'سحب نقدي' : (inv.type == 'DEPOSIT' ? 'دفع مقدم' : 'بيع');
    
    Color bottomBarColor = Colors.orange;
    if (inv.type == 'DEPOSIT') {
      bottomBarColor = Colors.green;
    } else if (inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid') {
      bottomBarColor = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _navigateToCustomerDetails(inv.userId),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: isMobile ? _buildMobileCardContent(inv, typeColor, typeLabel, isUnpaidTab, isDark) : _buildDesktopCardContent(inv, typeColor, typeLabel, isUnpaidTab, isDark),
            ),
          ),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: bottomBarColor,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCardContent(Invoice inv, Color typeColor, String typeLabel, bool isUnpaidTab, bool isDark) {
    PaymentMethod? localSelectedMethod;
    try { if (inv.paymentMethodId != null) localSelectedMethod = _saleMethods.firstWhere((m) => m.id == inv.paymentMethodId); } catch (_) {}
    
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(inv.customerName ?? 'زبون عابر', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text('${inv.invoiceDate}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              if (inv.notes != null && inv.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('ملاحظات: ${inv.notes}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[600])),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${inv.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: typeColor)),
              if (!isUnpaidTab) Text(inv.methodName ?? 'كاش', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
            ],
          ),
        ),
        if (isUnpaidTab) ...[
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<PaymentMethod>(
              value: localSelectedMethod,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              decoration: InputDecoration(
                labelText: 'وسيلة الدفع',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _saleMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: (val) => localSelectedMethod = val,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () {
              if (localSelectedMethod != null) _confirmPayment(inv, localSelectedMethod!);
              else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار وسيلة الدفع أولاً')));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('تسوية الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileCardContent(Invoice inv, Color typeColor, String typeLabel, bool isUnpaidTab, bool isDark) {
    PaymentMethod? localSelectedMethod;
    try { if (inv.paymentMethodId != null) localSelectedMethod = _saleMethods.firstWhere((m) => m.id == inv.paymentMethodId); } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(inv.customerName ?? 'زبون عابر', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            Text('${inv.amount.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: typeColor)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 4),
            Text('${inv.invoiceDate}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
        if (inv.notes != null && inv.notes!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('ملاحظات: ${inv.notes}', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[600])),
        ],
        if (!isUnpaidTab) ...[
           const SizedBox(height: 8),
           Text(inv.methodName ?? 'كاش', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
        ],
        if (isUnpaidTab) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  value: localSelectedMethod,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  decoration: InputDecoration(
                    labelText: 'وسيلة الدفع',
                    labelStyle: const TextStyle(fontSize: 10),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: _saleMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) => localSelectedMethod = val,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (localSelectedMethod != null) _confirmPayment(inv, localSelectedMethod!);
                  else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار وسيلة الدفع')));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('تسوية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
