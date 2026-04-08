import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _startDate;
  DateTime? _endDate;
  List<Invoice> _unpaidInvoices = [];
  List<Invoice> _paidInvoices = [];
  List<PaymentMethod> _saleMethods = [];
  bool _isLoading = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _endDate = DateTime.now().add(const Duration(days: 1));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final methods = await db.getPaymentMethods(category: 'SALE');
    final allInvoices = await db.getInvoices(start: _startDate, end: _endDate);

    setState(() {
      _saleMethods = methods;
      _unpaidInvoices = allInvoices.where((inv) => 
        (inv.paymentStatus == 'UNPAID' || inv.paymentStatus == 'pending')
      ).toList();

      _paidInvoices = allInvoices.where((inv) => 
        inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid' || inv.paymentStatus == 'PARTIAL'
      ).toList();

      _isLoading = false;
    });
  }

  List<Invoice> _filterBySearch(List<Invoice> list) {
    if (_searchQuery.isEmpty) return list;
    return list.where((inv) => 
      (inv.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
      (inv.amount.toString().contains(_searchQuery))
    ).toList();
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopBar(isDark),
          _buildTabBar(isDark),
          Expanded(
            child: _isLoading
               ? const Center(child: CircularProgressIndicator())
               : TabBarView(
                   controller: _tabController,
                   children: [
                     _buildList(_filterBySearch(_unpaidInvoices), isDark, true),
                     _buildList(_filterBySearch(_paidInvoices), isDark, false),
                   ],
                 ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تسوية ومعالجة المدفوعات', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                  const SizedBox(height: 4),
                  const Text('متابعة الفواتير المعلقة للزبائن عبر الدائمين', style: TextStyle(color: Colors.grey)),
                ],
              ),
              _buildDateFilter(isDark),
            ],
          ),
          const SizedBox(height: 24),
          _buildSearchBar(isDark),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'بحث باسم الزبون أو المبلغ...',
          prefixIcon: const Icon(Icons.search, color: Colors.blue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
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
          Tab(text: 'فواتير غير مدفوعة'),
          Tab(text: 'سجل المدفوعات'),
        ],
      ),
    );
  }

  Widget _buildDateFilter(bool isDark) {
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          initialDateRange: DateTimeRange(start: _startDate!, end: _endDate!.subtract(const Duration(days: 1))),
        );
        if (picked != null) {
          setState(() {
            _startDate = picked.start;
            _endDate = picked.end.add(const Duration(hours: 23, minutes: 59));
          });
          _loadData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.blue[50], 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.blue[100]!)
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              "${DateFormat('yyyy-MM-dd').format(_startDate!)} - ${DateFormat('yyyy-MM-dd').format(_endDate!.subtract(const Duration(minutes: 1)))}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Invoice> invoices, bool isDark, bool isUnpaidTab) {
    if (invoices.isEmpty) {
      return Center(child: Text(isUnpaidTab ? 'لا توجد فواتير معلقة' : 'لا توجد فواتير مدفوعة في هذه الفترة'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final inv = invoices[index];
        return _buildInvoiceCard(inv, isDark, isUnpaidTab);
      },
    );
  }

  Widget _buildInvoiceCard(Invoice inv, bool isDark, bool isUnpaidTab) {
    PaymentMethod? localSelectedMethod;
    try {
      if (inv.paymentMethodId != null) {
        localSelectedMethod = _saleMethods.firstWhere((m) => m.id == inv.paymentMethodId);
      }
    } catch (_) {}

    Color typeColor = inv.type == 'WITHDRAWAL' ? Colors.orange : (inv.type == 'DEPOSIT' ? Colors.green : Colors.blue);
    String typeLabel = inv.type == 'WITHDRAWAL' ? 'سحب نقدي' : (inv.type == 'DEPOSIT' ? 'دفع مقدم (إيداع رصيد)' : 'بيع');
    
    // الألوان للأشرطة السفلية
    Color bottomBarColor = Colors.orange; // الافتراضي دين
    if (inv.type == 'DEPOSIT') {
      bottomBarColor = Colors.green; // إيداع
    } else if (inv.paymentStatus == 'PAID' || inv.paymentStatus == 'paid') {
      bottomBarColor = Colors.blue; // مدفوع
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
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
                      Text('التاريخ: ${inv.invoiceDate}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      if (inv.notes != null) Text('ملاحظات: ${inv.notes}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text('${inv.amount} ₪', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: typeColor)),
                ),
                if (isUnpaidTab) ...[
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<PaymentMethod>(
                      value: localSelectedMethod,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: const InputDecoration(labelText: 'وسيلة الدفع', border: OutlineInputBorder()),
                      items: _saleMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                      onChanged: (val) => localSelectedMethod = val,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () => _confirmPayment(inv, localSelectedMethod!),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.all(20)),
                    child: const Text('تسوية الآن', style: TextStyle(color: Colors.white)),
                  ),
                ] else
                  Text(inv.methodName ?? 'كاش', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ),
          // الشريط السفلي الملون
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: bottomBarColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
