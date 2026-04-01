import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({Key? key}) : super(key: key);

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _phoneController = TextEditingController();

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<User> _allCustomers = [];
  List<User> _filteredCustomers = [];
  User? _selectedCustomer;

  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedPaymentMethod;
  List<Invoice> _invoices = [];
  Map<String, dynamic> _todayStats = {'total_sales': 0.0, 'total_debt': 0.0, 'buyers_count': 0};
  bool _isLoading = false;
  bool _isDataLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isDataLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final customers = await db.getCustomers();
      final methods = await db.getPaymentMethods();
      final invoices = await db.getTodayInvoices();
      final stats = await db.getSalesStatsToday();

      setState(() {
        _allCustomers = customers;
        _paymentMethods = methods;
        _invoices = invoices;
        _todayStats = stats;
        if (methods.isNotEmpty && _selectedPaymentMethod == null) {
          _selectedPaymentMethod = methods.first;
        }
        _isDataLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _isDataLoading = false);
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) _overlayEntry!.remove();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OverlayEntry(
      builder: (context) => Positioned(
        width: 400, 
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 15,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.blue[100]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _filteredCustomers.isEmpty
                  ? ListTile(title: Text('لا يوجد نتائج', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)))
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _filteredCustomers.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                      itemBuilder: (context, index) {
                        final c = _filteredCustomers[index];
                        return ListTile(
                          hoverColor: isDark ? Colors.white10 : Colors.blue[50],
                          title: Text(c.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text(c.phone ?? 'بدون هاتف', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
                          trailing: Text('${c.balance} ₪',
                            style: TextStyle(
                              color: c.balance >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                          onTap: () {
                            _selectCustomer(c);
                            _hideOverlay();
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _filterCustomers(String query) {
    if (query.trim().isEmpty) {
      _filteredCustomers = [];
      _hideOverlay();
      return;
    }

    final searchLower = query.trim().toLowerCase();
    _filteredCustomers = _allCustomers
        .where((c) => c.name.toLowerCase().contains(searchLower) || (c.phone != null && c.phone!.contains(searchLower)))
        .toList();

    if (_filteredCustomers.isNotEmpty) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    setState(() {});
  }

  void _selectCustomer(User customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerSearchController.text = customer.name;
      _phoneController.text = customer.phone ?? '';
    });
  }

  Future<void> _createInvoice() async {
    if (_amountController.text.isEmpty) {
      _showSnackBar('يرجى إدخال المبلغ', Colors.redAccent);
      return;
    }
    if (_selectedPaymentMethod == null) {
      _showSnackBar('يرجى اختيار طريقة الدفع', Colors.redAccent);
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    final db = context.read<DatabaseService>();
    setState(() => _isLoading = true);

    try {
      User customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!;
      } else {
        final id = await db.insertUser(User(
          username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
          name: _customerSearchController.text.trim().isEmpty ? 'زبون عابر' : _customerSearchController.text.trim(),
          phone: _phoneController.text,
          role: 'customer',
          createdAt: DateTime.now().toIso8601String(),
        ), '123');
        customer = (await db.getCustomers()).firstWhere((c) => c.id == id);
      }

      final invoice = Invoice(
        userId: customer.id!,
        invoiceDate: DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now()),
        amount: amount,
        paymentStatus: (_selectedPaymentMethod!.type == 'deferred' || _selectedPaymentMethod!.type == 'unpaid') ? 'UNPAID' : 'PAID',
        paymentMethodId: _selectedPaymentMethod?.id,
        createdAt: DateTime.now().toIso8601String(),
        notes: _notesController.text,
      );

      await db.insertInvoice(invoice);
      _amountController.clear();
      _notesController.clear();
      _customerSearchController.clear();
      _phoneController.clear();
      _selectedCustomer = null;
      await _loadData();
      _showSnackBar('تم تسجيل الفاتورة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ أثناء الحفظ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isDataLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isSmall, isDark),
                const SizedBox(height: 32),
                _buildStatsRow(isSmall, isDark),
                const SizedBox(height: 32),
                _buildInvoiceForm(isSmall, isDark),
                const SizedBox(height: 48),
                _buildTodaySalesTable(isSmall, isDark),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader(bool isSmall, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('شاشة البيع الرئيسية', style: TextStyle(fontSize: isSmall ? 24 : 32, fontWeight: FontWeight.w900, color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A))),
            const SizedBox(height: 4),
            Text('إضافة فاتورة جديدة ومتابعة المبيعات اليومية', style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF64748B), fontSize: 14)),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث البيانات'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, 
            foregroundColor: isDark ? const Color(0xFF00E5FF) : Colors.blue,
            elevation: 0,
            side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.blue[100]!)
          ),
        )
      ],
    );
  }

  Widget _buildStatsRow(bool isSmall, bool isDark) {
    return Row(
      children: [
        _buildStatCard('إجمالي مبيعات اليوم', '${_todayStats['total_sales'].toStringAsFixed(2)} ₪', Icons.trending_up, Colors.blue, isDark),
        const SizedBox(width: 20),
        _buildStatCard('ديون اليوم', '${_todayStats['total_debt'].toStringAsFixed(2)} ₪', Icons.money_off, Colors.red, isDark),
        const SizedBox(width: 20),
        _buildStatCard('إجمالي الزبائن', '${_allCustomers.length}', Icons.people, Colors.green, isDark),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF64748B), fontSize: 13)),
                Text(value, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceForm(bool isSmall, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('اسم المشتري', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                    const SizedBox(height: 8),
                    CompositedTransformTarget(
                      link: _layerLink,
                      child: TextField(
                        controller: _customerSearchController,
                        onChanged: _filterCustomers,
                        style: TextStyle(fontSize: 18, color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن زبون أو أدخل اسماً جديداً...',
                          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                          prefixIcon: const Icon(Icons.person_search, color: Color(0xFF0B74FF)),
                          suffixIcon: _selectedCustomer != null ? IconButton(icon: const Icon(Icons.close), onPressed: () {
                            setState(() { _selectedCustomer = null; _customerSearchController.clear(); _phoneController.clear(); });
                          }) : null,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.transparent)),
                        ),
                      ),
                    ),
                    if (_selectedCustomer != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _selectedCustomer!.balance < 0 
                          ? 'الدين الحالي: ${_selectedCustomer!.balance.abs()} ₪' 
                          : 'الرصيد المتاح: ${_selectedCustomer!.balance} ₪',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedCustomer!.balance < 0 ? Colors.redAccent : Colors.greenAccent
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Amount Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المبلغ (شيكل)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black),
                      onChanged: (val) {
                        setState(() {}); // Trigger UI update for final amount
                      },
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        prefixIcon: const Icon(Icons.payments, color: Colors.greenAccent),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.transparent)),
                      ),
                    ),
                    if (_selectedCustomer != null && _amountController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          double am = double.tryParse(_amountController.text) ?? 0;
                          double finalBal = _selectedCustomer!.balance - am;
                          return Text(
                            finalBal < 0 ? 'الرصيد المتوقع: ${finalBal.abs()} ₪ (دين)' : 'الرصيد المتوقع: $finalBal ₪ (فائض)',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                          );
                        }
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Phone Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رقم الجوال (اختياري)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: '05X XXX XXXX',
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        prefixIcon: const Icon(Icons.phone_android, color: Colors.orangeAccent),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.transparent)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Payment Method Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                    const SizedBox(height: 8),
                    _paymentMethods.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red[900]?.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Text('⚠️ لم يتم تحميل طرق الدفع - يرجى التحديث', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        )
                      : DropdownButtonFormField<PaymentMethod>(
                          value: _selectedPaymentMethod,
                          dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black),
                          items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                          onChanged: (v) => setState(() => _selectedPaymentMethod = v),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.wallet, color: Color(0xFF0B74FF)),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.transparent)),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('ملاحظات إضافية', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 2,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'اكتب أي تفاصيل هنا...',
              hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
              filled: true,
              fillColor: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.transparent)),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createInvoice,
              icon: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Icon(Icons.check_circle, color: Colors.white),
              label: Text(
                _isLoading ? 'جاري الحفظ...' : 'حفظ الفاتورة وتأكيد العملية', 
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B74FF), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySalesTable(bool isSmall, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('سجل العمليات الأخيرة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A))),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white, 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: isDark ? Colors.white10 : Colors.black12),
            child: DataTable(
              horizontalMargin: 24,
              columnSpacing: 24,
              headingRowHeight: 60,
              columns: [
                DataColumn(label: Text('المشتري', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
                DataColumn(label: Text('المبلغ', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
                DataColumn(label: Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
                DataColumn(label: Text('ملاحظات', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
              ],
              rows: _invoices.map((inv) => DataRow(cells: [
                DataCell(Text(inv.customerName ?? 'عابر', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
                DataCell(Text('${inv.amount} ₪', style: const TextStyle(color: Color(0xFF0B74FF), fontWeight: FontWeight.w900))),
                DataCell(Text(inv.methodName ?? '-', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
                DataCell(Text(inv.notes ?? '-', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87), overflow: TextOverflow.ellipsis)),
              ])).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
