import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final db = context.read<DatabaseService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('التنبيهات والديون', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchNotificationsData(db),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }

          final debtCustomers = snapshot.data!['debtCustomers'] as List<Map<String, dynamic>>;
          final unpaidInvoices = snapshot.data!['unpaidInvoices'] as List<Invoice>;

          if (debtCustomers.isEmpty && unpaidInvoices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('لا توجد تنبيهات حالياً', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (debtCustomers.isNotEmpty) ...[
                _buildSectionHeader(context, 'ديون زبائن (تأخير في السداد)', Icons.warning_amber_rounded, Colors.orange),
                const SizedBox(height: 8),
                ...debtCustomers.map((data) => _buildSimpleDebtCard(context, data, isDark)),
                const SizedBox(height: 24),
              ],
              if (unpaidInvoices.isNotEmpty) ...[
                _buildSectionHeader(context, 'فواتير غير مسددة بالكامل', Icons.receipt_long_rounded, Colors.redAccent),
                const SizedBox(height: 8),
                ...unpaidInvoices.map((inv) => _buildInvoiceCard(context, inv, isDark)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchNotificationsData(DatabaseService db) async {
    final allCustomers = await db.getCustomers();
    final now = DateTime.now();
    
    List<Map<String, dynamic>> debtAlerts = [];
    
    for (var u in allCustomers) {
      if (u.balance > 0) {
        // Get the last invoice or transaction for this user to see since when they haven't paid
        final invoices = await db.getCustomerInvoices(u.id!);
        if (invoices.isNotEmpty) {
          final lastInvoice = invoices.last;
          final lastDate = DateTime.tryParse(lastInvoice.createdAt) ?? now;
          final daysPassed = now.difference(lastDate).inDays;
          
          if (daysPassed >= 2) {
             debtAlerts.add({
               'user': u,
               'days': daysPassed,
               'amount': u.balance,
             });
          }
        }
      }
    }
    
    final allInvoices = await db.getInvoices();
    final unpaidInvoices = allInvoices.where((inv) => inv.paymentStatus == 'UNPAID').toList();

    return {
      'debtCustomers': debtAlerts,
      'unpaidInvoices': unpaidInvoices,
    };
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSimpleDebtCard(BuildContext context, Map<String, dynamic> data, bool isDark) {
    final User user = data['user'];
    final int days = data['days'];
    final double amount = data['amount'];
    
    String timeMsg = days >= 7 ? 'أسبوع' : '$days يوم';
    if (days >= 30) timeMsg = 'شهر';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.withOpacity(0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.1), child: const Icon(Icons.person, color: Colors.orange)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('عليه دين بقيمة $amount ₪', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  Text('لم يتم التسديد منذ $timeMsg', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(BuildContext context, Invoice inv, bool isDark) {
    final remaining = inv.amount - inv.paidAmount;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.redAccent.withOpacity(0.1),
          child: const Icon(Icons.receipt, color: Colors.redAccent),
        ),
        title: Text(inv.customerName ?? 'زبون غير معروف', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('فاتورة #${inv.id} - ${inv.invoiceDate}'),
            Text('المتبقي: ${remaining.toStringAsFixed(2)} ₪', 
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }
}
