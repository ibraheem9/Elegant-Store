import '../utils/timestamp_formatter.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../widgets/shimmer_loading.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../core/constants/app_colors.dart';
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
  String _invoiceDateFilter = 'day'; // 'day', 'week', 'month', 'custom'
  
  int? _sortColumnIndex = 1; // Default to Date
  bool _isAscending = false; // Newest first

  Map<String, dynamic> _todayStats = {'total_sales': 0.0, 'total_debt': 0.0, 'buyers_count': 0};
  bool _isLoading = false;
  bool _isDataLoading = true;

  // ── Invoice table pagination ─────────────────────────────────────────────
  static const int _invoicePageSize = 20;
  int _invoiceDisplayCount = _invoicePageSize;

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

  /// Lightweight reload: only refreshes invoices + stats, no full-page spinner.
  /// Used when the user changes date filter tabs — avoids rebuilding the form.
  Future<void> _loadInvoicesOnly() async {
    if (!mounted) return;
    try {
      final db = context.read<DatabaseService>();
      DateTime rangeStart = DateTime(_startDate.year, _startDate.month, _startDate.day);
      DateTime rangeEnd = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      final stats = await db.getSalesStats(start: rangeStart, end: rangeEnd);
      final invoices = await db.getInvoices(start: rangeStart, end: rangeEnd);
      if (mounted) {
        setState(() {
          _invoices = invoices;
          _todayStats = stats;
          _applyTableFilter();
        });
      }
    } catch (e) {
      debugPrint('Error loading invoices: $e');
    }
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
      // Reset pagination when filter changes
      _invoiceDisplayCount = _invoicePageSize;
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
                          trailing: Text('${c.balance.toStringAsFixed(2)} NIS', style: TextStyle(color: c.balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
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
    // If the typed text no longer exactly matches the selected customer's name,
    // clear the selection so the balance preview resets to zero.
    if (_selectedCustomer != null &&
        query.trim() != _selectedCustomer!.name) {
      _selectedCustomer = null;
      _selectedCustomerBalance = null;
    }

    if (query.trim().isEmpty) {
      _filteredCustomers = [];
      _hideOverlay();
      setState(() {});
      return;
    }
    final searchNormalized = _normalizeArabic(query);
    _filteredCustomers = _allCustomers.where((c) {
      final nameNormalized = _normalizeArabic(c.name);
      final nicknameNormalized = _normalizeArabic(c.nickname ?? '');
      return nameNormalized.contains(searchNormalized) ||
          nicknameNormalized.contains(searchNormalized);
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
    if (_amountController.text.isEmpty) {
      _showSnackBar('يرجى إدخال المبلغ', Colors.redAccent);
      return;
    }
    if (_selectedPaymentMethod == null) {
      _showSnackBar('يرجى اختيار طريقة الدفع', Colors.redAccent);
      return;
    }
    if (_selectedCustomer == null && _customerSearchController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسم المشتري', Colors.redAccent);
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      _showSnackBar('يرجى إدخال مبلغ صحيح أكبر من صفر', Colors.redAccent);
      return;
    }
    final db = context.read<DatabaseService>();

    setState(() {
      _isLoading = true;
    });

    try {
      User customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!;
      } else {
        // Auto-create as non-permanent customer
        final name = _customerSearchController.text.trim();
        final newUser = User(
          username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
          name: name.isEmpty ? 'زبون عابر' : name,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          role: 'CUSTOMER',
          isPermanentCustomer: 0,
          createdAt: TimestampFormatter.nowUtc(),
        );
        final id = await db.insertUser(newUser, '123');
        customer = (await db.getCustomers()).firstWhere((c) => c.id == id);
      }

      String status = 'PAID';
      if (_selectedPaymentMethod!.type == 'deferred' || _selectedPaymentMethod!.type == 'unpaid') {
        status = (customer.isPermanentCustomer == 1) ? 'DEFERRED' : 'UNPAID';
      }

      final combinedDateTimeUtc = TimestampFormatter.applyPastDateRuleUtc(_selectedInvoiceDate);

      final invoice = Invoice(
        userId: customer.id!,
        invoiceDate: combinedDateTimeUtc,
        amount: amount,
        paymentStatus: status,
        paymentMethodId: _selectedPaymentMethod?.id,
        createdAt: combinedDateTimeUtc,
        notes: _notesController.text,
      );

      final invoiceId = await db.insertInvoice(invoice);
      // Always recalculate after insert to ensure balance reflects the new invoice correctly
      await db.recalculateUserBalance(invoice.userId);
      final _actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: invoiceId,
        targetType: 'INVOICE',
        action: 'CREATE',
        summary: 'فاتورة جديدة للزبون ${customer.name} بمبلغ ${amount.toStringAsFixed(2)} NIS - الحالة: ${_translateHistoryValue('payment_status', status)}',
        performedById: _actUser?.id,
        performedByName: _actUser?.username ?? _actUser?.name, // Prefer username (e.g. i7) for identity
        storeManagerId: _actUser?.parentId ?? _actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      _clearFields();
      await _loadData();
      _showSnackBar('تم تسجيل الفاتورة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ أثناء الحفظ: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleCashWithdrawal() async {
    if (_amountController.text.isEmpty) {
      _showSnackBar('يرجى إدخال المبلغ المسحوب', Colors.redAccent);
      return;
    }
    if (_selectedCustomer == null && _customerSearchController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسم المشتري', Colors.redAccent);
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      _showSnackBar('يرجى إدخل مبلغ صحيح أكبر من صفر', Colors.redAccent);
      return;
    }
    final db = context.read<DatabaseService>();

    setState(() {
      _isLoading = true;
    });

    try {
      User customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!;
      } else {
        // Auto-create as non-permanent customer
        final name = _customerSearchController.text.trim();
        final newUser = User(
          username: 'cust_${DateTime.now().millisecondsSinceEpoch}',
          name: name.isEmpty ? 'زبون عابر' : name,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          role: 'CUSTOMER',
          isPermanentCustomer: 0,
          createdAt: TimestampFormatter.nowUtc(),
        );
        final id = await db.insertUser(newUser, '123');
        customer = (await db.getCustomers()).firstWhere((c) => c.id == id);
      }
      await db.recordCashWithdrawal(
        customer: customer,
        amount: amount,
        notes: _notesController.text,
        paymentMethodId: _selectedPaymentMethod?.id,
        date: TimestampFormatter.applyPastDateRule(_selectedInvoiceDate),
      );
      _clearFields();
      await _loadData();
      _showSnackBar('تم تسجيل السحب بنجاح', Colors.orange);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _handleAddCredit() async {
    if (_selectedCustomer == null) {
      _showSnackBar('يرجى اختيار زبون مسجل أولاً', Colors.orange);
      return;
    }
    if (_amountController.text.isEmpty) {
      _showSnackBar('يرجى إدخال مبلغ الدفعة', Colors.orange);
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      _showSnackBar('يرجى إدخال مبلغ صحيح أكبر من صفر', Colors.orange);
      return;
    }
    if (_selectedPaymentMethod == null) {
      _showSnackBar('يرجى اختيار طريقة الدفع', Colors.orange);
      return;
    }

    // Validate payment method type
    if (_selectedPaymentMethod!.type == 'deferred' || _selectedPaymentMethod!.type == 'unpaid') {
      _showSnackBar('لا يسمح ان تكون دفعة السداد بطريقة دفع دين أو غير مدفوع', Colors.red);
      return;
    }

    final db = context.read<DatabaseService>();
    setState(() => _isLoading = true);
    try {
      final combinedDateTime = TimestampFormatter.applyPastDateRule(_selectedInvoiceDate);
      await db.addCredit(
        userId: _selectedCustomer!.id!,
        amount: amount,
        notes: _notesController.text,
        paymentMethodId: _selectedPaymentMethod!.id!,
        date: combinedDateTime,
      );
      _clearFields();
      await _loadData();
      _showSnackBar('تم تسجيل الدفعة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
  void _showSnackBar(String msg, Color color) { ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color)); }

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
    // Parse existing createdAt (stored as UTC) and convert to local for date picker
    DateTime editSelectedDate = inv.createdAt.toLocalDateTime();

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
              // Date picker for invoice date
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: editSelectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) {
                    setDialogState(() => editSelectedDate = DateTime(
                      picked.year, picked.month, picked.day,
                      editSelectedDate.hour, editSelectedDate.minute, editSelectedDate.second,
                    ));
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الفاتورة',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(DateFormat('yyyy/MM/dd').format(editSelectedDate)),
                ),
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
      // Build new createdAt from the selected date (apply past date rule)
      final newCreatedAt = TimestampFormatter.applyPastDateRuleUtc(editSelectedDate);
      // Update invoice_date to match createdAt exactly (UTC ISO8601)
      final newInvoiceDate = newCreatedAt;
      final newInv = Invoice(
        id: inv.id,
        uuid: inv.uuid,
        userId: inv.userId,
        invoiceDate: newInvoiceDate,
        amount: newAmount,
        paidAmount: inv.paidAmount,
        paymentStatus: inv.paymentStatus,
        paymentMethodId: selectedMethod?.id,
        createdAt: newCreatedAt,
        notes: notesController.text,
        type: inv.type,
        version: inv.version,
        isSynced: 0,
      );

      final _actUser = context.read<AuthService>().currentUser;
      await db.updateInvoiceWithLog(
        oldInv: inv,
        newInv: newInv,
        reason: reasonController.text,
        performedById: _actUser?.id,
        performedByName: _actUser?.username ?? _actUser?.name,
        storeManagerId: _actUser?.parentId ?? _actUser?.id,
      );
      // Recalculate balance in case amount or payment_status changed
      await db.recalculateUserBalance(inv.userId);
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
                  // Resolve field label
                  final rawField = item['field_name'] as String?;
                  final fieldLabel = rawField == 'amount'
                      ? 'المبلغ'
                      : rawField == 'payment_status'
                          ? 'حالة الدفع'
                          : rawField == 'notes'
                              ? 'الملاحظات'
                              : rawField == 'payment_method_id'
                                  ? 'طريقة الدفع'
                                  : rawField == 'created_at'
                                      ? 'تاريخ الفاتورة'
                                      : rawField ?? 'بيانات الفاتورة';
                  // Resolve summary (action label)
                  final action = item['action'] as String? ?? 'UPDATE';
                  // Translate status values in summary text (handles old stored English values too)
                  final String? summary = _translateSummary(item['summary'] as String?).isNotEmpty
                      ? _translateSummary(item['summary'] as String?)
                      : null;
                  final editorName = item['edited_by_name'] as String?;
                  final rawOldVal = item['old_value'] as String?;
                  final rawNewVal = item['new_value'] as String?;
                  // Translate status values and format dates in old/new values
                  final oldVal = _translateHistoryValue(rawField ?? '', rawOldVal);
                  final newVal = _translateHistoryValue(rawField ?? '', rawNewVal);
                  final reason = item['edit_reason'] as String?;
                  // Format date
                  String dateStr = item['created_at'] as String? ?? '';
                  try {
                    final dt = DateTime.parse(dateStr);
                    dateStr = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
                  } catch (_) {}
                  // Action badge color
                  final badgeColor = action == 'CREATE'
                      ? Colors.green
                      : action == 'DELETE'
                          ? Colors.red
                          : Colors.orange;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: badgeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        action == 'CREATE' ? 'إضافة' : action == 'DELETE' ? 'حذف' : 'تعديل',
                        style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      summary ?? 'تغيير $fieldLabel',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (oldVal != null && newVal != null)
                          Text('من: $oldVal  ←  إلى: $newVal', style: const TextStyle(fontSize: 12)),
                        if (reason != null && reason.isNotEmpty)
                          Text('السبب: $reason', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            if (editorName != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    action == 'CREATE' ? Icons.person_add_rounded : Icons.person_rounded,
                                    size: 12,
                                    color: badgeColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      action == 'CREATE'
                                          ? 'أُنشئت بواسطة: $editorName'
                                          : action == 'DELETE'
                                              ? 'حُذفت بواسطة: $editorName'
                                              : 'عُدّلت بواسطة: $editorName',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 12),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    dateStr,
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
        content: Text('هل أنت متأكد من نقل الفاتورة (مبلغ: ${inv.amount.toStringAsFixed(2)} NIS) إلى سلة المحذوفات؟'),
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
      final _actUser = context.read<AuthService>().currentUser;
      db.logActivity(
        targetId: inv.id!,
        targetType: 'INVOICE',
        action: 'DELETE',
        summary: 'حذف فاتورة بمبلغ ${inv.amount.toStringAsFixed(2)} NIS - الحالة: ${_translateHistoryValue('payment_status', inv.paymentStatus)}',
        performedById: _actUser?.id,
        performedByName: _actUser?.username ?? _actUser?.name,
        storeManagerId: _actUser?.parentId ?? _actUser?.id,
      ).catchError((e) => debugPrint('logActivity failed: $e'));
      await _loadData();
      _showSnackBar('تم نقل الفاتورة لسلة المحذوفات', Colors.redAccent);
    }
  }

  /// Translates raw DB values to Arabic for display in edit history.
  String _translateHistoryValue(String field, String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return '-';
    // Translate payment status
    if (field == 'payment_status') {
      switch (raw.toUpperCase()) {
        case 'DEFERRED': return 'دين';
        case 'PAID':     return 'مدفوع';
        case 'UNPAID':   return 'غير مدفوع';
        case 'PARTIAL':  return 'مدفوع جزئياً';
      }
    }
    // Translate invoice type
    if (field == 'type') {
      switch (raw.toUpperCase()) {
        case 'SALE':       return 'بيع';
        case 'WITHDRAWAL': return 'سحب';
        case 'DEPOSIT':    return 'سداد';
      }
    }
    // Format ISO date strings to readable local time
    if (field == 'created_at' || raw.contains('T') || raw.contains('Z')) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        final local = dt;
        return DateFormat('yyyy/MM/dd  HH:mm').format(local);
      }
    }
    return raw;
  }

  /// Translates English status keywords in any summary string to Arabic.
  /// IMPORTANT: 'UNPAID' must be replaced before 'PAID' to avoid partial match.
  /// Also fixes legacy broken values like 'UNمدفوع' that were stored incorrectly.
  String _translateSummary(String? text) {
    if (text == null) return '';
    return text
        .replaceAll('DEFERRED', 'دين')
        .replaceAll('UNPAID', 'غير مدفوع')
        .replaceAll('UNمدفوع', 'غير مدفوع')  // fix legacy broken value
        .replaceAll('PAID', 'مدفوع');
  }

  void _applyDateFilter(String mode) {
    final now = DateTime.now();
    setState(() {
      _invoiceDateFilter = mode;
      switch (mode) {
        case 'day':
          _startDate = now;
          _endDate = now;
          break;
        case 'week':
          // Last 7 days (today + 6 previous days)
          _startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
          _endDate = now;
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        // 'custom' is handled by _selectFilterDateRange
      }
    });
    // Only reload invoices/stats — no full-page spinner
    _loadInvoicesOnly();
  }

  String _buildDateFilterLabel() {
    final fmt = DateFormat('dd/MM/yyyy');
    switch (_invoiceDateFilter) {
      case 'day':
        return fmt.format(_startDate);
      case 'week':
        return '${fmt.format(_startDate)} - ${fmt.format(_endDate)}';
      case 'month':
        return DateFormat('MMMM yyyy', 'ar').format(_startDate);
      case 'custom':
        if (_startDate == _endDate) return fmt.format(_startDate);
        return '${fmt.format(_startDate)} - ${fmt.format(_endDate)}';
      default:
        return fmt.format(_startDate);
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
        _invoiceDateFilter = 'custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      // Only reload invoices/stats — no full-page spinner
      _loadInvoicesOnly();
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
        ? ShimmerLoading(isDark: isDark, itemCount: 6)
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 16 : 32, isMobile ? 16 : 32, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInvoiceForm(isMobile, isDark),
                const SizedBox(height: 32),
                _buildInvoiceSection(isMobile, isDark),
              ],
            ),
          ),
    );
  }

  Widget _buildInvoiceForm(bool isMobile, bool isDark) {
    final formFields = [
      Expanded(flex: isMobile ? 0 : 2, child: _buildCustomerField()),
      if (isMobile) const SizedBox(height: 16),
      if (!isMobile) const SizedBox(width: 16),
      Expanded(flex: isMobile ? 0 : 1, child: _buildAmountField()),
      if (isMobile) const SizedBox(height: 16),
      if (!isMobile) const SizedBox(width: 16),
      Expanded(flex: isMobile ? 0 : 1, child: _buildPaymentMethodField()),
      if (isMobile) const SizedBox(height: 16),
      if (!isMobile) const SizedBox(width: 16),
      Expanded(flex: isMobile ? 0 : 1, child: _buildDateField()),
    ];

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
          if (isMobile) 
            ...formFields.map((e) => e is Expanded ? e.child : e).toList()
          else 
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: formFields),
          const SizedBox(height: 8),
          _buildBalancePreview(),
          const SizedBox(height: 16),
          _buildNotesField(),
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
    // PAID methods (cash/app) do not affect customer balance — only unpaid/deferred/credit do
    final isPaidMethod = _selectedPaymentMethod?.type == 'cash' || _selectedPaymentMethod?.type == 'app';
    final effectiveDebt = isPaidMethod ? 0.0 : enteredAmount;
    final projectedBalance = currentBalance + effectiveDebt;
    final isDebt = projectedBalance > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDebt ? Colors.red.withOpacity(0.07) : Colors.green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDebt ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رصيد الزبون الحالي
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('رصيد الزبون الحالي', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(
                currentBalance > 0
                    ? '+${currentBalance.toStringAsFixed(2)} NIS (دين عليه)'
                    : currentBalance < 0
                        ? '-${currentBalance.abs().toStringAsFixed(2)} NIS (رصيد له)'
                        : '0.00 NIS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: currentBalance > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          // بعد الفاتورة
          if (enteredAmount > 0) ...[
            const Divider(height: 14, thickness: 0.6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('بعد الفاتورة', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  projectedBalance > 0
                      ? '+${projectedBalance.toStringAsFixed(2)} NIS (دين عليه)'
                      : projectedBalance < 0
                          ? '-${projectedBalance.abs().toStringAsFixed(2)} NIS (رصيد له)'
                          : '0.00 NIS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
        labelText: 'المبلغ (NIS)',
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
        Expanded(child: SizedBox(height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _handleCashWithdrawal, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('دين نقدي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _handleAddCredit, style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('دفعة (سداد)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
      ]),
    ]);
  }

  Widget _buildInvoiceSection(bool isMobile, bool isDark) {
    final totalCount = _filteredInvoices.length;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final textColor = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: title + date label ──────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'سجل العمليات',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _buildDateFilterLabel(),
                style: TextStyle(fontSize: 11, color: labelColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ── Row 2: date dropdown | sort button | invoice count ─────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Date filter dropdown
            _buildDateDropdown(isDark),
            const SizedBox(width: 8),
            // Sort button
            _buildSortButton(isDark),
            const Spacer(),
            // Invoice count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded, color: Colors.blue, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    totalCount.toString(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(width: 3),
                  Text('فاتورة', style: TextStyle(fontSize: 10, color: labelColor)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Search bar (full width) ─────────────────────────────────────────────────────────────────
        _buildTableSearchBar(isDark, isMobile),
        const SizedBox(height: 14),

        // ── Invoice list ────────────────────────────────────────────────────────────────────
        isMobile ? _buildInvoiceCards(isDark) : _buildTodaySalesTable(isDark),
      ],
    );
  }

  /// Compact dropdown button that replaces the 4-tab date filter bar.
  Widget _buildDateDropdown(bool isDark) {
    // Label shown on the button itself
    final Map<String, String> modeLabels = {
      'day': 'يوم',
      'week': 'أسبوع',
      'month': 'شهر',
      'custom': 'تاريخ',
    };
    final currentLabel = modeLabels[_invoiceDateFilter] ?? 'يوم';

    return PopupMenuButton<String>(
      tooltip: 'فلتر التاريخ',
      onSelected: (value) {
        if (value == 'custom') {
          _selectFilterDateRange(context);
        } else {
          _applyDateFilter(value);
        }
      },
      itemBuilder: (context) => [
        _buildDateMenuItem('day', 'اليوم', Icons.today_rounded),
        _buildDateMenuItem('week', 'آخر 7 أيام', Icons.date_range_rounded),
        _buildDateMenuItem('month', 'هذا الشهر', Icons.calendar_month_rounded),
        _buildDateMenuItem('custom', 'تاريخ محدد', Icons.edit_calendar_rounded),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, color: Colors.blue, size: 15),
            const SizedBox(width: 5),
            Text(
              currentLabel,
              style: const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down_rounded, color: Colors.blue, size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildDateMenuItem(String value, String label, IconData icon) {
    final isSelected = _invoiceDateFilter == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17, color: isSelected ? Colors.blue : Colors.grey[600]),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue : null,
            ),
          ),
          const Spacer(),
          if (isSelected) const Icon(Icons.check_rounded, size: 16, color: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildCountCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortMenu(bool isDark) {
    return _buildSortButton(isDark);
  }

  Widget _buildSortButton(bool isDark) {
    return PopupMenuButton<int>(
      tooltip: 'ترتيب حسب',
      onSelected: _onSort,
      itemBuilder: (context) => [
        _buildSortItem(1, 'التاريخ'),
        _buildSortItem(0, 'اسم المشتري'),
        _buildSortItem(3, 'طريقة الدفع'),
        _buildSortItem(2, 'المبلغ'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, color: Colors.blue, size: 18),
            const SizedBox(width: 5),
            Text('ترتيب', style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
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
    if (_filteredInvoices.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('لا يوجد نتائج')));
    }
    final displayedInvoices = _filteredInvoices.take(_invoiceDisplayCount).toList();
    final hasMore = _filteredInvoices.length > _invoiceDisplayCount;
    return Column(
      children: [
        ...displayedInvoices.map((inv) => _buildSingleInvoiceCard(inv, isDark)),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _invoiceDisplayCount += _invoicePageSize),
              icon: const Icon(Icons.expand_more_rounded, color: Colors.blue),
              label: Text(
                'تحميل المزيد (متبقي ${_filteredInvoices.length - _invoiceDisplayCount})',
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleInvoiceCard(Invoice inv, bool isDark) {
    final isDeposit    = inv.type == 'DEPOSIT';
    final isWithdrawal = inv.type == 'WITHDRAWAL';
    // Unified color system:
    //   DEPOSIT    → green  (customer paying us back)
    //   WITHDRAWAL → orange (cash withdrawal from register)
    //   SALE+PAID  → blue   (paid invoice)
    //   SALE+UNPAID/DEFERRED → red (debt)
    final Color cardColor;
    final Color borderColor;
    final Color nameColor;
    final Color statusChipColor;

    if (isDeposit) {
      cardColor       = AppColors.invoiceDepositBackground;
      borderColor     = AppColors.invoiceDepositBorder;
      nameColor       = AppColors.invoiceDeposit;
      statusChipColor = AppColors.invoiceDeposit;
    } else if (isWithdrawal) {
      cardColor       = const Color(0xFFFFF7ED); // orange-50
      borderColor     = const Color(0xFFFED7AA); // orange-200
      nameColor       = const Color(0xFFEA580C); // orange-600
      statusChipColor = const Color(0xFFEA580C);
    } else {
      // SALE — color by payment status
      cardColor       = AppColors.invoiceStatusBackground(inv.paymentStatus);
      borderColor     = AppColors.invoiceStatusBorder(inv.paymentStatus);
      nameColor       = AppColors.invoiceStatusColor(inv.paymentStatus);
      statusChipColor = AppColors.invoiceStatusColor(inv.paymentStatus);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: (isDeposit || isWithdrawal) ? 1.5 : 1),
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
                      if (isDeposit) 
                        Text('دفعة سداد ديون', style: TextStyle(color: nameColor.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold))
                      else if (isWithdrawal) 
                        Row(children: [
                          Icon(Icons.account_balance_wallet, size: 11, color: nameColor.withOpacity(0.8)),
                          const SizedBox(width: 3),
                          Flexible(child: Text('سحب نقدي من الصندوق', style: TextStyle(color: nameColor.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                        ])
                      else
                        Text(
                          inv.paymentStatus == 'PAID' ? 'فاتورة بيع (نقدي)' : 'فاتورة بيع (دين)',
                          style: TextStyle(color: nameColor.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
              Text('${inv.amount.toStringAsFixed(2)} NIS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: nameColor)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(inv.createdAt.toLocalMedium(), style: TextStyle(color: nameColor.withOpacity(0.6), fontSize: 12)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusChipColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isWithdrawal ? 'سحب نقدي' : (inv.methodName ?? '-'),
                  style: TextStyle(fontSize: 10, color: statusChipColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          // Last editor — own line to avoid overflow
          if (inv.lastEditedBy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note_rounded, size: 13, color: Colors.blueGrey[400]),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      inv.lastEditedBy!,
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey[500], fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // Action buttons row — aligned to end
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(Icons.history, color: statusChipColor.withOpacity(0.7), size: 20),
                tooltip: 'سجل التعديلات',
                onPressed: () => _showEditHistory(inv.id!),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: statusChipColor, size: 20),
                tooltip: 'تعديل',
                onPressed: () => _showEditInvoiceDialog(inv),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'حذف',
                onPressed: () => _deleteInvoice(inv),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySalesTable(bool isDark) {
    final displayedInvoices = _filteredInvoices.take(_invoiceDisplayCount).toList();
    final hasMore = _filteredInvoices.length > _invoiceDisplayCount;
    return Column(
      children: [
        Container(
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
            rows: displayedInvoices.map((inv) {
          final isDeposit    = inv.type == 'DEPOSIT';
          final isWithdrawal = inv.type == 'WITHDRAWAL';
          // Unified color system per invoice type/status
          final Color rowColor;
          final Color rowNameColor;
          if (isDeposit) {
            rowColor     = AppColors.invoiceDepositBackground;
            rowNameColor = AppColors.invoiceDeposit;
          } else if (isWithdrawal) {
            rowColor     = const Color(0xFFFFF7ED);
            rowNameColor = const Color(0xFFEA580C);
          } else {
            rowColor     = AppColors.invoiceStatusBackground(inv.paymentStatus);
            rowNameColor = AppColors.invoiceStatusColor(inv.paymentStatus);
          }
          return DataRow(
            color: WidgetStateProperty.all(rowColor.withOpacity(0.5)),
            cells: [
              DataCell(
                InkWell(
                  onTap: () => _navigateToCustomerDetails(inv.userId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(inv.customerName ?? 'عابر', style: TextStyle(color: rowNameColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                      Text(
                        '${_translateHistoryValue('type', inv.type)} (${_translateHistoryValue('payment_status', inv.paymentStatus)})',
                        style: TextStyle(color: rowNameColor.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              ),
              DataCell(Text(inv.createdAt.toLocalMedium(), style: TextStyle(color: rowNameColor.withOpacity(0.7), fontSize: 12))),
              DataCell(Text('${inv.amount.toStringAsFixed(2)} NIS', style: TextStyle(color: rowNameColor, fontWeight: FontWeight.bold))),
              DataCell(Text(isWithdrawal ? 'سحب نقدي' : (inv.methodName ?? '-'), style: TextStyle(color: rowNameColor.withOpacity(0.8)))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inv.lastEditedBy != null) ...[  
                    Icon(Icons.edit_note_rounded, size: 12, color: Colors.blueGrey[400]),
                    const SizedBox(width: 2),
                    Text(inv.lastEditedBy!, style: TextStyle(fontSize: 10, color: Colors.blueGrey[500], fontStyle: FontStyle.italic)),
                    const SizedBox(width: 4),
                  ],
                  IconButton(icon: Icon(Icons.history, color: rowNameColor.withOpacity(0.7), size: 18), onPressed: () => _showEditHistory(inv.id!)),
                  IconButton(icon: Icon(Icons.edit, color: rowNameColor, size: 18), onPressed: () => _showEditInvoiceDialog(inv)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () => _deleteInvoice(inv)),
                ],
              )),
            ]
          );
        }).toList(),
          ),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _invoiceDisplayCount += _invoicePageSize),
              icon: const Icon(Icons.expand_more_rounded, color: Colors.blue),
              label: Text(
                'تحميل المزيد (متبقي ${_filteredInvoices.length - _invoiceDisplayCount})',
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
