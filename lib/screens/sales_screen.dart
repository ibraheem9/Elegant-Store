import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _dateController = TextEditingController();
  final _tableFilterController = TextEditingController();

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<User> _allCustomers = [];
  List<User> _filteredCustomers = [];
  User? _selectedCustomer;
  // Live balance preview
  double? _selectedCustomerBalance;

  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedPaymentMethod;
  List<Invoice> _invoices = [];
  List<Invoice> _filteredInvoices = [];
  
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  DateTime _selectedInvoiceDate = DateTime.now();
  
  int? _sortColumnIndex = 1; // Default to Date
  bool _isAscending = false; // Newest first

  Map<String, dynamic> _todayStats = {'total_sales': 0.0, 'total_debt': 0.0, 'buyers_count': 0};
  bool _isLoading = false;
  bool _isDataLoading = true;

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate);
    _loadData();
    _amountController.addListener(_updateLiveBalance);
  }

  void _updateLiveBalance() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideOverlay();
    _amountController.removeListener(_updateLiveBalance);
    _amountController.dispose();
    _notesController.dispose();
    _customerSearchController.dispose();
    _phoneController.dispose();
    _dateController.dispose();
    _tableFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isDataLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final customers = await db.getCustomers();
      final rawMethods = await db.getPaymentMethods(category: 'SALE');
      final seenIds = <int?>{};
      final methods = rawMethods.where((m) => seenIds.add(m.id)).toList();

      DateTime rangeStart = DateTime(_startDate.year, _startDate.month, _startDate.day);
      DateTime rangeEnd = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      
      final stats = await db.getSalesStats(start: rangeStart, end: rangeEnd);
      final invoices = await db.getInvoices(start: rangeStart, end: rangeEnd);

      if (mounted) {
        setState(() {
          _allCustomers = customers;
          _paymentMethods = methods;
          _invoices = invoices;
          _todayStats = stats;

          // Refresh selected customer balance if one is selected
          if (_selectedCustomer != null) {
            try {
              final updated = customers.firstWhere((c) => c.id == _selectedCustomer!.id);
              _selectedCustomer = updated;
              _selectedCustomerBalance = updated.balance;
            } catch (_) {}
          }

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
          
          _applyTableFilter();
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

  void _applyTableFilter() {
    String query = _normalizeArabic(_tableFilterController.text);
    setState(() {
      _filteredInvoices = _invoices.where((inv) {
        bool matchesName = _normalizeArabic(inv.customerName ?? '').contains(query);
        bool matchesAmount = inv.amount.toString().contains(query);
        bool matchesMethod = _normalizeArabic(inv.methodName ?? '').contains(query);
        return matchesName || matchesAmount || matchesMethod;
      }).toList();
      _applySort();
    });
  }

  void _applySort() {
    if (_sortColumnIndex == null) return;
    _filteredInvoices.sort((a, b) {
      dynamic aVal, bVal;
      switch (_sortColumnIndex) {
        case 0: aVal = a.customerName ?? ''; bVal = b.customerName ?? ''; break;
        case 1: aVal = a.createdAt; bVal = b.createdAt; break;
        case 2: aVal = a.amount; bVal = b.amount; break;
        case 3: aVal = a.methodName ?? ''; bVal = b.methodName ?? ''; break;
        default: return 0;
      }
      return _isAscending ? Comparable.compare(aVal, bVal) : Comparable.compare(bVal, aVal);
    });
  }

  void _onSort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _isAscending = !_isAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      }
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
                          trailing: Text('${c.balance} ₪', style: TextStyle(color: c.balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
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
      _selectedCustomerBalance = customer.balance;
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedInvoiceDate) {
      setState(() {
        _selectedInvoiceDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate);
      });
    }
  }

  Future<void> _createInvoice() async {
    if (_amountController.text.isEmpty) { _showSnackBar('يرجى إدخال المبلغ', Colors.redAccent); return; }
    if (_selectedPaymentMethod == null) { _showSnackBar('يرجى اختيار طريقة الدفع', Colors.redAccent); return; }
    if (_selectedCustomer == null && _customerSearchController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسم المشتري', Colors.redAccent);
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) { _showSnackBar('يرجى إدخال مبلغ صحيح أكبر من صفر', Colors.redAccent); return; }
    final db = context.read<DatabaseService>();

    setState(() => _isLoading = true);
    try {
      User customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!;
      } else {
        // Auto-create as non-permanent customer
        final name = _customerSearchController.text.trim();
        final id = await db.insertUser(User(
          username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
          name: name.isEmpty ? 'زبون عابر' : name,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          role: 'CUSTOMER',
          isPermanentCustomer: 0,
          createdAt: DateTime.now().toIso8601String(),
        ), '123');
        customer = (await db.getCustomers()).firstWhere((c) => c.id == id);
      }

      String status = 'PAID';
      if (_selectedPaymentMethod!.type == 'deferred' || _selectedPaymentMethod!.type == 'unpaid') {
        status = (customer.isPermanentCustomer == 1) ? 'DEFERRED' : 'UNPAID';
      }

      final now = DateTime.now();
      final combinedDateTime = DateTime(
        _selectedInvoiceDate.year,
        _selectedInvoiceDate.month,
        _selectedInvoiceDate.day,
        now.hour,
        now.minute,
        now.second,
      );

      final invoice = Invoice(
        userId: customer.id!,
        invoiceDate: DateFormat('dd-MM-yyyy EEEE', 'ar').format(combinedDateTime),
        amount: amount,
        paymentStatus: status,
        paymentMethodId: _selectedPaymentMethod?.id,
        createdAt: combinedDateTime.toIso8601String(),
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
    if (_selectedCustomer == null && _customerSearchController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسم المشتري', Colors.redAccent);
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) { _showSnackBar('يرجى إدخال مبلغ صحيح أكبر من صفر', Colors.redAccent); return; }
    final db = context.read<DatabaseService>();
    setState(() => _isLoading = true);
    try {
      User customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!;
      } else {
        // Auto-create as non-permanent customer
        final name = _customerSearchController.text.trim();
        final id = await db.insertUser(User(
          username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
          name: name.isEmpty ? 'زبون عابر' : name,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          role: 'CUSTOMER',
          isPermanentCustomer: 0,
          createdAt: DateTime.now().toIso8601String(),
        ), '123');
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
    _selectedCustomerBalance = null;
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
    PaymentMethod? selectedMethod;
    try {
      selectedMethod = _paymentMethods.firstWhere((m) => m.id == inv.paymentMethodId);
    } catch (_) {
      selectedMethod = _paymentMethods.isNotEmpty ? _paymentMethods.first : null;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الفاتورة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'المبلغ الجديد'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              ),
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
        uuid: inv.uuid,
        userId: inv.userId,
        invoiceDate: inv.invoiceDate,
        amount: newAmount,
        paidAmount: inv.paidAmount,
        paymentStatus: inv.paymentStatus,
        paymentMethodId: selectedMethod?.id,
        createdAt: inv.createdAt,
        notes: notesController.text,
        type: inv.type,
        version: inv.version,
        isSynced: 0,
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
      ),
    );
  }

  Future<void> _deleteInvoice(Invoice inv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من نقل الفاتورة (مبلغ: ${inv.amount} ₪) إلى سلة المحذوفات؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('حذف', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = context.read<DatabaseService>();
      await db.softDeleteInvoice(inv);
      await _loadData();
      _showSnackBar('تم نقل الفاتورة لسلة المحذوفات', Colors.redAccent);
    }
  }

  Future<void> _selectFilterDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 900;

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
                _buildInvoiceSection(isMobile, isDark),
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
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => _selectFilterDateRange(context),
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(DateFormat('MM/dd').format(_startDate) + ' - ' + DateFormat('MM/dd').format(_endDate)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                foregroundColor: isDark ? Colors.white : Colors.black87,
                elevation: 0,
                side: BorderSide(color: isDark ? Colors.white10 : Colors.black12)
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ],
        ),
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark, {bool tappable = false}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tappable ? color.withOpacity(0.4) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: tappable ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 22, fontWeight: FontWeight.w900)),
        ])),
        if (tappable) Icon(Icons.arrow_forward_ios, size: 14, color: color.withOpacity(0.6)),
      ]),
    );
  }

  Widget _buildInvoiceForm(bool isMobile, bool isDark) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          const Text('إدخال فاتورة جديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 24),
          if (isMobile) ...[
            _buildCustomerField(),
            const SizedBox(height: 8),
            _buildBalancePreview(),
            const SizedBox(height: 16),
            _buildAmountField(),
            const SizedBox(height: 16),
            _buildPaymentMethodField(),
            const SizedBox(height: 16),
            _buildDateField(),
            const SizedBox(height: 16),
            _buildNotesField(),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCustomerField()),
                const SizedBox(width: 16),
                Expanded(child: _buildAmountField()),
                const SizedBox(width: 16),
                Expanded(child: _buildPaymentMethodField()),
                const SizedBox(width: 16),
                Expanded(child: _buildDateField()),
              ],
            ),
            const SizedBox(height: 8),
            _buildBalancePreview(),
            const SizedBox(height: 16),
            _buildNotesField(),
          ],
          const SizedBox(height: 32),
          _buildActionButtons(isMobile),
        ],
      ),
    );
  }

  Widget _buildCustomerField() {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _customerSearchController,
        onChanged: _filterCustomers,
        decoration: const InputDecoration(
          labelText: 'اسم المشتري',
          prefixIcon: Icon(Icons.person, color: Colors.blue),
          hintText: 'ابحث عن زبون أو اكتب اسم جديد',
        ),
      ),
    );
  }

  Widget _buildBalancePreview() {
    if (_selectedCustomer == null || _selectedCustomerBalance == null) return const SizedBox.shrink();
    final enteredAmount = double.tryParse(_amountController.text) ?? 0.0;
    final currentBalance = _selectedCustomerBalance!;
    final projectedBalance = currentBalance + enteredAmount;
    final isDebt = projectedBalance > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDebt ? Colors.red.withOpacity(0.07) : Colors.green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDebt ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('رصيد الزبون الحالي', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(
                currentBalance > 0
                    ? '+${currentBalance.toStringAsFixed(2)} ₪  (دين عليه)'
                    : currentBalance < 0
                        ? '-${currentBalance.abs().toStringAsFixed(2)} ₪  (رصيد له)'
                        : '0.00 ₪',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: currentBalance > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          if (enteredAmount > 0) ...[
            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('بعد الفاتورة', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  projectedBalance > 0
                      ? '+${projectedBalance.toStringAsFixed(2)} ₪  (دين عليه)'
                      : projectedBalance < 0
                          ? '-${projectedBalance.abs().toStringAsFixed(2)} ₪  (رصيد له)'
                          : '0.00 ₪',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDebt ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    return TextField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      decoration: const InputDecoration(
        labelText: 'المبلغ (₪)',
        prefixIcon: Icon(Icons.payments, color: Colors.green),
      ),
    );
  }

  Widget _buildPaymentMethodField() {
    return DropdownButtonFormField<PaymentMethod>(
      value: (_paymentMethods.contains(_selectedPaymentMethod)) ? _selectedPaymentMethod : null, 
      items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(), 
      onChanged: (v) => setState(() => _selectedPaymentMethod = v), 
      decoration: const InputDecoration(labelText: 'طريقة الدفع', prefixIcon: Icon(Icons.wallet, color: Colors.purple)),
    );
  }

  Widget _buildDateField() {
    return TextField(
      controller: _dateController,
      readOnly: true,
      onTap: () => _selectDate(context),
      decoration: const InputDecoration(
        labelText: 'تاريخ الفاتورة',
        prefixIcon: Icon(Icons.calendar_today, color: Colors.orange),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController, 
      decoration: const InputDecoration(
        labelText: 'ملاحظات إضافية', 
        prefixIcon: Icon(Icons.note, color: Colors.blueGrey)
      )
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

  Widget _buildInvoiceSection(bool isMobile, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('سجل العمليات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            _buildSortMenu(isDark),
          ],
        ),
        const SizedBox(height: 16),
        _buildTableSearchBar(isDark, isMobile),
        const SizedBox(height: 16),
        isMobile ? _buildInvoiceCards(isDark) : _buildTodaySalesTable(isDark),
      ],
    );
  }

  Widget _buildSortMenu(bool isDark) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.sort_rounded, color: Colors.blue),
      tooltip: 'ترتيب حسب',
      onSelected: _onSort,
      itemBuilder: (context) => [
        _buildSortItem(1, 'التاريخ'),
        _buildSortItem(0, 'اسم المشتري'),
        _buildSortItem(3, 'طريقة الدفع'),
        _buildSortItem(2, 'المبلغ'),
      ],
    );
  }

  PopupMenuItem<int> _buildSortItem(int value, String label) {
    bool isSelected = _sortColumnIndex == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blue : null)),
          const Spacer(),
          if (isSelected) Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildTableSearchBar(bool isDark, bool isMobile) {
    return Container(
      width: double.infinity,
      height: 48,
      child: TextField(
        controller: _tableFilterController,
        onChanged: (_) => _applyTableFilter(),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'بحث في السجل بالاسم، المبلغ، أو طريقة الدفع...',
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.blue),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
        ),
      ),
    );
  }

  Widget _buildInvoiceCards(bool isDark) {
    if (_filteredInvoices.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('لا يوجد نتائج')));
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredInvoices.length,
      itemBuilder: (context, index) {
        final inv = _filteredInvoices[index];
        bool isDeposit = inv.type == 'DEPOSIT';
        bool isWithdrawal = inv.type == 'WITHDRAWAL';
        Color cardColor = isDeposit
            ? Colors.green.withOpacity(0.1)
            : isWithdrawal
                ? Colors.orange.withOpacity(0.08)
                : (isDark ? const Color(0xFF0F172A) : Colors.white);
        Color borderColor = isDeposit
            ? Colors.green.withOpacity(0.3)
            : isWithdrawal
                ? Colors.orange.withOpacity(0.4)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
        Color nameColor = isDeposit ? Colors.green[800]! : isWithdrawal ? Colors.orange[800]! : Colors.blue;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: (isDeposit || isWithdrawal) ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _navigateToCustomerDetails(inv.userId),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inv.customerName ?? 'عابر', style: TextStyle(color: nameColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          if (isDeposit) Text('فاتورة تسديد ديون', style: TextStyle(color: Colors.green[700], fontSize: 10, fontWeight: FontWeight.bold)),
                          if (isWithdrawal) Row(children: [
                            Icon(Icons.account_balance_wallet, size: 11, color: Colors.orange[700]),
                            const SizedBox(width: 3),
                            Text('سحب كاش من الصندوق', style: TextStyle(color: Colors.orange[700], fontSize: 10, fontWeight: FontWeight.bold)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  Text('${inv.amount} ₪', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: nameColor)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(inv.invoiceDate, style: TextStyle(color: isDeposit ? Colors.green[700]!.withOpacity(0.7) : isWithdrawal ? Colors.orange[700]!.withOpacity(0.7) : Colors.grey[500], fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isDeposit ? Colors.green : isWithdrawal ? Colors.orange : Colors.blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isWithdrawal ? 'سحب نقدي' : (inv.methodName ?? '-'),
                      style: TextStyle(fontSize: 10, color: isDeposit ? Colors.green[800] : isWithdrawal ? Colors.orange[800] : Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(icon: Icon(Icons.history, color: isDeposit ? Colors.green[700] : isWithdrawal ? Colors.orange[700] : Colors.grey, size: 20), onPressed: () => _showEditHistory(inv.id!)),
                  IconButton(icon: Icon(Icons.edit, color: isDeposit ? Colors.green : isWithdrawal ? Colors.orange : Colors.orange, size: 20), onPressed: () => _showEditInvoiceDialog(inv)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => _deleteInvoice(inv)),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildTodaySalesTable(bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
      child: DataTable(
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _isAscending,
        columns: [
          DataColumn(label: const Text('المشتري'), onSort: (i, _) => _onSort(i)),
          DataColumn(label: const Text('التاريخ'), onSort: (i, _) => _onSort(i)),
          DataColumn(label: const Text('المبلغ'), onSort: (i, _) => _onSort(i)),
          DataColumn(label: const Text('طريقة الدفع'), onSort: (i, _) => _onSort(i)),
          const DataColumn(label: Text('الإجراءات')),
        ],
        rows: _filteredInvoices.map((inv) {
          bool isDeposit = inv.type == 'DEPOSIT';
          bool isWithdrawal = inv.type == 'WITHDRAWAL';
          Color rowNameColor = isDeposit ? Colors.green[800]! : isWithdrawal ? Colors.orange[800]! : Colors.blue;
          return DataRow(
            color: isDeposit
                ? MaterialStateProperty.all(Colors.green.withOpacity(0.05))
                : isWithdrawal
                    ? MaterialStateProperty.all(Colors.orange.withOpacity(0.05))
                    : null,
            cells: [
              DataCell(
                InkWell(
                  onTap: () => _navigateToCustomerDetails(inv.userId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(inv.customerName ?? 'عابر', style: TextStyle(color: rowNameColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                      if (isDeposit) Text('فاتورة تسديد ديون', style: TextStyle(color: Colors.green[700], fontSize: 9, fontWeight: FontWeight.bold)),
                      if (isWithdrawal) Text('سحب كاش من الصندوق', style: TextStyle(color: Colors.orange[700], fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ),
              DataCell(Text(inv.invoiceDate, style: TextStyle(color: isDeposit ? Colors.green[800] : isWithdrawal ? Colors.orange[800] : null))),
              DataCell(Text('${inv.amount} ₪', style: TextStyle(color: rowNameColor, fontWeight: (isDeposit || isWithdrawal) ? FontWeight.bold : null))),
              DataCell(Text(isWithdrawal ? 'سحب نقدي' : (inv.methodName ?? '-'), style: TextStyle(color: isDeposit ? Colors.green[800] : isWithdrawal ? Colors.orange[800] : null))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: Icon(Icons.history, color: isDeposit ? Colors.green[700] : isWithdrawal ? Colors.orange[700] : Colors.grey, size: 18), onPressed: () => _showEditHistory(inv.id!)),
                  IconButton(icon: Icon(Icons.edit, color: isDeposit ? Colors.green : Colors.orange, size: 18), onPressed: () => _showEditInvoiceDialog(inv)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () => _deleteInvoice(inv)),
                ],
              )),
            ]
          );
        }).toList(),
      ),
    );
  }
}
