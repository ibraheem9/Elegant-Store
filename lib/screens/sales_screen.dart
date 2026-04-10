import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'customers_screen.dart';
import 'recycle_bin_screen.dart';

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
  
  DateTime? _startDate = DateTime.now();
  DateTime? _endDate = DateTime.now();
  PaymentMethod? _filterPaymentMethod;
  
  int? _sortColumnIndex;
  bool _isAscending = true;

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
    _amountController.dispose();
    _notesController.dispose();
    _customerSearchController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isDataLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final customers = await db.getCustomers();
      final methods = await db.getPaymentMethods(category: 'SALE');
      
      DateTime rangeStart = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      DateTime rangeEnd = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      
      final stats = await db.getSalesStats(start: rangeStart, end: rangeEnd);
      final invoices = await db.getInvoices(start: rangeStart, end: rangeEnd);

      if (mounted) {
        setState(() {
          _allCustomers = customers;
          _paymentMethods = methods;
          _invoices = invoices;
          _todayStats = stats;
          
          if (methods.isNotEmpty) {
            if (_selectedPaymentMethod != null) {
               bool exists = methods.any((m) => m.id == _selectedPaymentMethod!.id);
               if (!exists) {
                 _selectedPaymentMethod = methods.first;
               } else {
                 _selectedPaymentMethod = methods.firstWhere((m) => m.id == _selectedPaymentMethod!.id);
               }
            } else {
              _selectedPaymentMethod = methods.first;
            }
          }
          
          _applyClientSideFilters();
          _isDataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error loading data: $e');
        setState(() => _isDataLoading = false);
      }
    }
  }

  void _applyClientSideFilters() {
    if (_filterPaymentMethod != null) {
      _invoices = _invoices.where((inv) => inv.paymentMethodId == _filterPaymentMethod!.id).toList();
    }
    _applySort();
  }

  void _applySort() {
    if (_sortColumnIndex == null) return;
    setState(() {
      _invoices.sort((a, b) {
        dynamic aVal, bVal;
        switch (_sortColumnIndex) {
          case 0: aVal = a.customerName ?? ''; bVal = b.customerName ?? ''; break;
          case 1: aVal = a.createdAt; bVal = b.createdAt; break;
          case 2: aVal = a.amount; bVal = b.amount; break;
          case 4: aVal = a.methodName ?? ''; bVal = b.methodName ?? ''; break;
          default: return 0;
        }
        return _isAscending ? Comparable.compare(aVal, bVal) : Comparable.compare(bVal, aVal);
      });
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;
      _applySort();
    });
  }

  String _normalizeArabic(String text) {
    String normalized = text;
    normalized = normalized.replaceAll(RegExp(r'[أإآا]'), 'ا');
    normalized = normalized.replaceAll(RegExp(r'[ة]'), 'ه');
    normalized = normalized.replaceAll(RegExp(r'[ى]'), 'ي');
    return normalized.toLowerCase().trim();
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
    final size = MediaQuery.of(context).size;
    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width < 600 ? size.width - 64 : 400, 
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
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFBBDEFB)),
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
                          title: Row(
                            children: [
                              Text(c.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                              if (c.nickname != null && c.nickname!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text('(${c.nickname})', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                              ],
                            ],
                          ),
                          subtitle: Text(c.phone ?? 'بدون هاتف', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
                          trailing: Text('${c.balance} ₪', style: TextStyle(color: c.balance >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
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
    final searchNormalized = _normalizeArabic(query);
    _filteredCustomers = _allCustomers.where((c) {
      final nameNormalized = _normalizeArabic(c.name);
      final nicknameNormalized = _normalizeArabic(c.nickname ?? "");
      return nameNormalized.contains(searchNormalized) || nicknameNormalized.contains(searchNormalized);
    }).toList();

    if (_filteredCustomers.isNotEmpty) _showOverlay();
    else _hideOverlay();
    setState(() {});
  }

  void _selectCustomer(User customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerSearchController.text = customer.name;
      _phoneController.text = customer.phone ?? '';
      
      if (_paymentMethods.isNotEmpty) {
        if (customer.isPermanentCustomer == 1) {
          try { 
            _selectedPaymentMethod = _paymentMethods.firstWhere((m) => m.type == 'deferred'); 
          } catch (_) {
            _selectedPaymentMethod = _paymentMethods.first;
          }
        } else {
          try { 
            _selectedPaymentMethod = _paymentMethods.firstWhere((m) => m.type == 'unpaid'); 
          } catch (_) {
            _selectedPaymentMethod = _paymentMethods.first;
          }
        }
      }
    });
  }

  Future<void> _createInvoice() async {
    if (_amountController.text.isEmpty) { _showSnackBar('يرجى إدخال المبلغ', Colors.redAccent); return; }
    if (_selectedPaymentMethod == null) { _showSnackBar('يرجى اختيار طريقة الدفع', Colors.redAccent); return; }

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

      String status = 'PAID';
      if (_selectedPaymentMethod!.type == 'deferred' || _selectedPaymentMethod!.type == 'unpaid') {
        status = (customer.isPermanentCustomer == 1) ? 'DEFERRED' : 'UNPAID';
      }

      final invoice = Invoice(
        userId: customer.id!,
        invoiceDate: DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now()),
        amount: amount,
        paymentStatus: status,
        paymentMethodId: _selectedPaymentMethod?.id,
        createdAt: DateTime.now().toIso8601String(),
        notes: _notesController.text,
      );

      await db.insertInvoice(invoice);
      _clearFields();
      await _loadData();
      _showSnackBar('تم تسجيل الفاتورة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ أثناء الحفظ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCashWithdrawal() async {
    if (_amountController.text.isEmpty) { _showSnackBar('يرجى إدخال المبلغ المسحوب', Colors.redAccent); return; }
    final amount = double.tryParse(_amountController.text) ?? 0;
    final db = context.read<DatabaseService>();
    setState(() => _isLoading = true);
    try {
      User customer;
      if (_selectedCustomer != null) { customer = _selectedCustomer!; } else {
        final id = await db.insertUser(User(username: 'cust_${DateTime.now().millisecondsSinceEpoch}', name: _customerSearchController.text.trim().isEmpty ? 'زبون عابر' : _customerSearchController.text.trim(), phone: _phoneController.text, role: 'customer', createdAt: DateTime.now().toIso8601String()), '123');
        customer = (await db.getCustomers()).firstWhere((c) => c.id == id);
      }
      await db.recordCashWithdrawal(customer: customer, amount: amount, notes: _notesController.text, paymentMethodId: _selectedPaymentMethod?.id);
      _clearFields(); await _loadData(); _showSnackBar('تم تسجيل السحب بنجاح', Colors.orange);
    } catch (e) { _showSnackBar('خطأ: $e', Colors.red); } finally { setState(() => _isLoading = false); }
  }

  Future<void> _handleAddCredit() async {
    if (_selectedCustomer == null) { _showSnackBar('يرجى اختيار زبون مسجل أولاً', Colors.orange); return; }
    final db = context.read<DatabaseService>();
    final creditMethods = _paymentMethods.where((m) => m.type == 'cash' || m.type == 'app').toList();
    PaymentMethod? localMethod = creditMethods.isNotEmpty ? creditMethods.first : null;
    final creditAmountController = TextEditingController(text: _amountController.text);
    final creditNotesController = TextEditingController(text: _notesController.text);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إيداع رصيد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: creditAmountController, decoration: const InputDecoration(labelText: 'المبلغ المودع'), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            DropdownButtonFormField<PaymentMethod>(value: localMethod, items: creditMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(), onChanged: (v) => setDialogState(() => localMethod = v), decoration: const InputDecoration(labelText: 'طريقة الإيداع')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد'))],
        ),
      ),
    );
    if (result == true && localMethod != null) {
      final amount = double.tryParse(creditAmountController.text) ?? 0;
      setState(() => _isLoading = true);
      try { await db.addCredit(userId: _selectedCustomer!.id!, amount: amount, notes: creditNotesController.text, paymentMethodId: localMethod!.id!); _clearFields(); await _loadData(); _showSnackBar('تم الإيداع بنجاح', Colors.green); } catch (e) { _showSnackBar('خطأ: $e', Colors.red); } finally { setState(() => _isLoading = false); }
    }
  }

  void _clearFields() { 
    _amountController.clear(); 
    _notesController.clear(); 
    _customerSearchController.clear(); 
    _phoneController.clear(); 
    _selectedCustomer = null; 
    if (_paymentMethods.isNotEmpty) {
      _selectedPaymentMethod = _paymentMethods.first;
    }
  }
  void _showSnackBar(String msg, Color color) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color)); }

  void _navigateToCustomerDetails(int customerId) async {
    final db = context.read<DatabaseService>();
    final customers = await db.getCustomers();
    try {
      final customer = customers.firstWhere((c) => c.id == customerId);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer))).then((_) => _loadData());
    } catch (e) {
      debugPrint('Customer not found: $e');
    }
  }

  Future<void> _showEditInvoiceDialog(Invoice inv) async {
    final amountController = TextEditingController(text: inv.amount.toString());
    final notesController = TextEditingController(text: inv.notes);
    final reasonController = TextEditingController();
    PaymentMethod? selectedMethod = _paymentMethods.firstWhere((m) => m.id == inv.paymentMethodId, orElse: () => _paymentMethods.first);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الفاتورة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: amountController, decoration: const InputDecoration(labelText: 'المبلغ الجديد'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                value: selectedMethod,
                items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedMethod = v),
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              ),
              const SizedBox(height: 12),
              TextField(controller: notesController, decoration: const InputDecoration(labelText: 'ملاحظات')),
              const SizedBox(height: 12),
              TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'سبب التعديل (إجباري)', hintText: 'مثلاً: خطأ في إدخال المبلغ')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  _showSnackBar('يرجى ذكر سبب التعديل', Colors.orange);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('حفظ التعديلات')
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final db = context.read<DatabaseService>();
      final newAmount = double.tryParse(amountController.text) ?? inv.amount;
      final newInv = Invoice(
        id: inv.id,
        userId: inv.userId,
        invoiceDate: inv.invoiceDate,
        amount: newAmount,
        paidAmount: inv.paidAmount,
        paymentStatus: inv.paymentStatus,
        paymentMethodId: selectedMethod?.id,
        createdAt: inv.createdAt,
        notes: notesController.text,
        type: inv.type
      );

      await db.updateInvoiceWithLog(oldInv: inv, newInv: newInv, reason: reasonController.text);
      await _loadData();
      _showSnackBar('تم تعديل الفاتورة وتسجيل التغيير', Colors.blue);
    }
  }

  Future<void> _showEditHistory(int invoiceId) async {
    final db = context.read<DatabaseService>();
    final history = await db.getEditHistory(invoiceId, 'INVOICE');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تاريخ تعديلات الفاتورة'),
        content: history.isEmpty 
          ? const Text('لا يوجد تعديلات سابقة لهذه الفاتورة')
          : SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: history.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = history[index];
                  return ListTile(
                    title: Text('تغيير ${item['field_name'] == 'amount' ? 'المبلغ' : item['field_name']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('من: ${item['old_value']} إلى: ${item['new_value']}'),
                        Text('السبب: ${item['edit_reason']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('التاريخ: ${item['created_at']}', style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  );
                },
              ),
            ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
      body: _isDataLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isMobile, isDark),
                const SizedBox(height: 32),
                _buildStatsRow(isMobile, isDark),
                const SizedBox(height: 32),
                _buildInvoiceForm(isMobile, isDark),
                const SizedBox(height: 48),
                _buildTodaySalesTable(isMobile, isDark),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader(bool isMobile, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('شاشة البيع', style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
        ]),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
      ],
    );
  }

  Widget _buildStatsRow(bool isMobile, bool isDark) {
    if (isMobile) {
      return Column(children: [
        _buildStatCard('إجمالي مبيعات الفترة', '${_todayStats['total_sales'].toStringAsFixed(2)} ₪', Icons.trending_up, Colors.blue, isDark),
        const SizedBox(height: 16),
        _buildStatCard('إجمالي الزبائن', '${_allCustomers.length}', Icons.people, Colors.green, isDark),
      ]);
    }
    return Row(children: [
      Expanded(child: _buildStatCard('إجمالي مبيعات الفترة', '${_todayStats['total_sales'].toStringAsFixed(2)} ₪', Icons.trending_up, Colors.blue, isDark)),
      const SizedBox(width: 20),
      Expanded(child: _buildStatCard('إجمالي الزبائن', '${_allCustomers.length}', Icons.people, Colors.green, isDark)),
    ]);
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 22, fontWeight: FontWeight.w900)),
        ])),
      ]),
    );
  }

  Widget _buildInvoiceForm(bool isMobile, bool isDark) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: TextField(controller: _customerSearchController, onChanged: _filterCustomers, decoration: const InputDecoration(labelText: 'اسم المشتري', prefixIcon: Icon(Icons.person))),
        ),
        const SizedBox(height: 16),
        TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (₪)', prefixIcon: Icon(Icons.payments))),
        const SizedBox(height: 16),
        DropdownButtonFormField<PaymentMethod>(
          value: (_paymentMethods.contains(_selectedPaymentMethod)) ? _selectedPaymentMethod : null, 
          items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(), 
          onChanged: (v) => setState(() => _selectedPaymentMethod = v), 
          decoration: const InputDecoration(labelText: 'طريقة الدفع', prefixIcon: Icon(Icons.wallet)),
          validator: (value) => value == null ? 'يرجى اختيار طريقة دفع' : null,
        ),
        const SizedBox(height: 16),
        TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.note))),
        const SizedBox(height: 32),
        _buildActionButtons(isMobile),
      ]),
    );
  }

  Widget _buildActionButtons(bool isMobile) {
    return Column(children: [
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _createInvoice, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B74FF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ الفاتورة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: SizedBox(height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _handleCashWithdrawal, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('سحب (دين)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _handleAddCredit, style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('إيداع رصيد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
      ]),
    ]);
  }

  Widget _buildTodaySalesTable(bool isMobile, bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('آخر العمليات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('المشتري')),
              DataColumn(label: Text('المبلغ')),
              DataColumn(label: Text('النوع')),
              DataColumn(label: Text('طريقة الدفع')),
              DataColumn(label: Text('الإجراءات')),
            ],
            rows: _invoices.map((inv) {
              return DataRow(cells: [
                DataCell(
                  InkWell(
                    onTap: () => _navigateToCustomerDetails(inv.userId),
                    child: Text(inv.customerName ?? 'عابر', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                  )
                ),
                DataCell(Text('${inv.amount} ₪')),
                DataCell(Text(inv.type == 'SALE' ? 'بيع' : 'سحب')),
                DataCell(Text(inv.methodName ?? '-')),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.history, color: Colors.grey, size: 18), onPressed: () => _showEditHistory(inv.id!)),
                    IconButton(icon: const Icon(Icons.edit, color: Colors.orange, size: 18), onPressed: () => _showEditInvoiceDialog(inv)),
                  ],
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    ]);
  }
}
