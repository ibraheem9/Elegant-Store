import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  List<Invoice> _pendingInvoices = [];
  List<PaymentMethod> _appMethods = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _endDate = DateTime.now();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();

    // Load app payment methods for the dropdown
    final methods = await db.getPaymentMethods();

    // Fetch all invoices for the period
    final allInvoices = await db.getInvoices(start: _startDate, end: _endDate);

    setState(() {
      _appMethods = methods.where((m) => m.type == 'app' || m.type == 'cash').toList();

      // Filter for reconciliation: Unpaid invoices OR invoices that were paid via APP but might need review
      // The blueprint says: "List of invoices with payment_method as APP or UNPAID"
      _pendingInvoices = allInvoices.where((inv) =>
        inv.paymentStatus == 'pending' ||
        (inv.methodName != null && _appMethods.any((m) => m.name == inv.methodName))
      ).toList();

      _isLoading = false;
    });
  }

  Future<void> _confirmPayment(Invoice inv, PaymentMethod selectedMethod) async {
    final db = context.read<DatabaseService>();

    final updatedInvoice = Invoice(
      id: inv.id,
      userId: inv.userId,
      invoiceDate: inv.invoiceDate,
      amount: inv.amount,
      notes: inv.notes,
      paymentStatus: 'paid', // Confirming sets it to PAID
      paymentMethodId: selectedMethod.id,
      createdAt: inv.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    );

    await db.updateInvoice(updatedInvoice);
    _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تأكيد دفع مبلغ ${inv.amount} ₪ عبر ${selectedMethod.name}'), backgroundColor: Colors.green)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تسوية ومعالجة المدفوعات', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('تأكيد الدفع للفواتير المعلقة أو التحويلات البنكية', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
                _buildDateFilter(),
              ],
            ),
            const SizedBox(height: 32),
            if (_isLoading)
               const Center(child: CircularProgressIndicator())
            else
               _buildPendingPaymentsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          initialDateRange: DateTimeRange(start: _startDate!, end: _endDate!),
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
        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[100]!)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              "${DateFormat('yyyy-MM-dd').format(_startDate!)} - ${DateFormat('yyyy-MM-dd').format(_endDate!)}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingPaymentsList() {
    if (_pendingInvoices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(60),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.green[200]),
            const SizedBox(height: 16),
            const Text('لا توجد فواتير معلقة بحاجة لتسوية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _pendingInvoices.length,
      itemBuilder: (context, index) {
        final inv = _pendingInvoices[index];
        return _buildReconciliationCard(inv);
      },
    );
  }

  Widget _buildReconciliationCard(Invoice inv) {
    PaymentMethod? localSelectedMethod;
    // Try to pre-select current method if it's already an app method
    if (inv.methodName != null) {
      try {
        localSelectedMethod = _appMethods.firstWhere((m) => m.name == inv.methodName);
      } catch (_) {}
    }

    return StatefulBuilder(
      builder: (context, setState) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: inv.paymentStatus == 'pending' ? Colors.orange[200]! : Colors.blue[100]!),
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
                      Text(inv.customerName ?? 'زبون عابر', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 12),
                      _buildStatusBadge(inv.paymentStatus),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('التاريخ: ${inv.invoiceDate} | الوقت: ${inv.createdAt.split('T').last.substring(0, 5)}', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  if (inv.notes != null) Text('ملاحظات: ${inv.notes}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text('${inv.amount} ₪', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
            ),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<PaymentMethod>(
                value: localSelectedMethod,
                decoration: const InputDecoration(labelText: 'وسيلة الدفع', border: OutlineInputBorder()),
                items: _appMethods.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
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
    bool isPending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPending ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isPending ? Colors.orange[200]! : Colors.green[200]!),
      ),
      child: Text(
        isPending ? 'بانتظار الدفع' : 'مدفوع',
        style: TextStyle(color: isPending ? Colors.orange[800] : Colors.green[800], fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
