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

class _PaymentsScreenState extends State<PaymentsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  List<Invoice> _pendingInvoices = [];
  List<PaymentMethod> _allMethods = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // إعداد الفلترة لتبدأ من بداية اليوم الحالي
    _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _endDate = DateTime.now().add(const Duration(days: 1)); // لنضمن شمول فواتير اليوم بالكامل
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    // جلب جميع طرق الدفع بدون تصفية
    final methods = await db.getPaymentMethods();

    // جلب الفواتير في النطاق الزمني
    final allInvoices = await db.getInvoices(start: _startDate, end: _endDate);

    setState(() {
      _allMethods = methods;

      // عرض الفواتير التي تحتاج مراجعة أو تسوية
      // تشمل الفواتير "غير المدفوعة" أو التي لها وسيلة دفع تحتاج تأكيد
      _pendingInvoices = allInvoices.where((inv) =>
        inv.paymentStatus == 'pending' || 
        inv.paymentStatus == 'UNPAID' ||
        inv.paymentMethodId == null ||
        // أو إظهار الجميع لمنح إمكانية تعديل طريقة الدفع كما طلب المستخدم
        true 
      ).toList();

      _isLoading = false;
    });
  }

  Future<void> _confirmPayment(Invoice inv, PaymentMethod selectedMethod) async {
    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    final currentUser = auth.currentUser;

    String timestamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    String editLog = "\n[تمت التسوية: $timestamp بواسطة ${currentUser?.name ?? 'نظام'}]";
    
    // الاحتفاظ بالملاحظات القديمة وإضافة سجل التعديل
    String currentNotes = inv.notes ?? "";
    if (currentNotes.contains("[تمت التسوية:")) {
      // إذا كانت مسواة سابقاً، نستبدل السجل القديم بالجديد أو نضيفه
      currentNotes = currentNotes.split("[تمت التسوية:").first.trim();
    }
    String updatedNotes = currentNotes + editLog;

    final updatedInvoice = Invoice(
      id: inv.id,
      userId: inv.userId,
      invoiceDate: inv.invoiceDate,
      amount: inv.amount,
      notes: updatedNotes,
      paymentStatus: (selectedMethod.type == 'deferred' || selectedMethod.type == 'unpaid') ? 'UNPAID' : 'paid',
      paymentMethodId: selectedMethod.id,
      createdAt: inv.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    );

    await db.updateInvoice(updatedInvoice);
    
    // تسجيل العملية في سجل التعديلات العام
    await db.logEdit(
      inv.id!, 
      'INVOICE', 
      'طريقة الدفع', 
      inv.methodName ?? 'غير محدد', 
      selectedMethod.name
    );

    _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ تسوية الفاتورة (الطريقة: ${selectedMethod.name})'), backgroundColor: Colors.blue)
      );
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
          Padding(
            padding: const EdgeInsets.all(32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تسوية ومعالجة المدفوعات', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('تأكيد وتعديل طرق دفع الفواتير', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600])),
                  ],
                ),
                _buildDateFilter(isDark),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
               ? const Center(child: CircularProgressIndicator())
               : _buildPendingPaymentsList(isDark),
          ),
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

  Widget _buildPendingPaymentsList(bool isDark) {
    if (_pendingInvoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: isDark ? Colors.white10 : Colors.grey[200]),
            const SizedBox(height: 16),
            const Text('لا توجد فواتير في هذه الفترة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: _pendingInvoices.length,
      itemBuilder: (context, index) {
        final inv = _pendingInvoices[index];
        return _buildReconciliationCard(inv, isDark);
      },
    );
  }

  Widget _buildReconciliationCard(Invoice inv, bool isDark) {
    PaymentMethod? localSelectedMethod;
    // محاولة تحديد القيمة الحالية للفاتورة في القائمة المنسدلة
    try {
      if (inv.paymentMethodId != null) {
        localSelectedMethod = _allMethods.firstWhere((m) => m.id == inv.paymentMethodId);
      } else if (inv.methodName != null) {
        localSelectedMethod = _allMethods.firstWhere((m) => m.name == inv.methodName);
      }
    } catch (_) {}

    return StatefulBuilder(
      builder: (context, setState) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(inv.customerName ?? 'زبون عابر', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(width: 12),
                      _buildStatusBadge(inv.paymentStatus),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'التاريخ: ${inv.invoiceDate} | الوقت: ${inv.createdAt.split('T').last.substring(0, 5)}', 
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 14)
                  ),
                  if (inv.notes != null && inv.notes!.isNotEmpty) 
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('ملاحظات: ${inv.notes}', style: TextStyle(color: isDark ? Colors.blue[200] : Colors.blue[700], fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text('${inv.amount} ₪', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0B74FF))),
            ),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<PaymentMethod>(
                value: localSelectedMethod,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'وسيلة الدفع', 
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                ),
                items: _allMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (val) => setState(() => localSelectedMethod = val),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: localSelectedMethod == null ? null : () => _confirmPayment(inv, localSelectedMethod!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('تأكيد التسوية', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    bool isUnpaid = status == 'pending' || status == 'UNPAID';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isUnpaid ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isUnpaid ? Colors.orange[200]! : Colors.green[200]!),
      ),
      child: Text(
        isUnpaid ? 'غير مدفوع' : 'مدفوع',
        style: TextStyle(color: isUnpaid ? Colors.orange[800] : Colors.green[800], fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
