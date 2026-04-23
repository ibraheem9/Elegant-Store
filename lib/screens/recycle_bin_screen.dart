import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<Invoice> _deletedInvoices = [];
  List<Invoice> _filteredInvoices = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadDeletedInvoices();
  }

  Future<void> _loadDeletedInvoices() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final invoices = await db.getInvoices(deleted: true);
    setState(() {
      _deletedInvoices = invoices;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredInvoices = _deletedInvoices.where((inv) {
        bool matchesSearch = (inv.customerName?.toLowerCase().contains(query) ?? false) ||
            (inv.notes?.toLowerCase().contains(query) ?? false) ||
            (inv.amount.toString().contains(query));

        bool matchesDate = true;
        if (_selectedDateRange != null) {
          DateTime invDate = DateTime.parse(inv.createdAt);
          matchesDate = invDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
              invDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
        }

        return matchesSearch && matchesDate;
      }).toList();
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _applyFilters();
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedDateRange = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeNotifier>().themeMode == ThemeMode.dark;
    final backgroundColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('سلة المحذوفات (الفواتير)', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.blue[300] : Colors.blue[800], size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'رجوع',
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(isDark, cardColor),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredInvoices.isEmpty
                    ? _buildEmptyState()
                    : _buildInvoicesList(isDark, cardColor),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark, Color cardColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الزبون أو المبلغ أو الملاحظات...',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.blue[300] : Colors.blue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[100],
                  ),
                  onChanged: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: _selectDateRange,
                style: IconButton.styleFrom(backgroundColor: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05)),
                icon: Icon(Icons.calendar_today, color: _selectedDateRange != null ? Colors.blue : (isDark ? Colors.white70 : Colors.black54)),
                tooltip: 'فلترة حسب التاريخ',
              ),
              if (_selectedDateRange != null || _searchController.text.isNotEmpty)
                IconButton.filledTonal(
                  onPressed: _clearFilters,
                  style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1)),
                  icon: const Icon(Icons.clear_all, color: Colors.red),
                  tooltip: 'مسح الفلاتر',
                ),
            ],
          ),
          if (_selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'الفترة: ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.blue[300] : Colors.blue[800]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInvoicesList(bool isDark, Color cardColor) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredInvoices.length,
      itemBuilder: (context, index) {
        final inv = _filteredInvoices[index];
        return Card(
          color: cardColor,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.red),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv.customerName ?? 'زبون عابر',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${inv.amount.toStringAsFixed(2)} ₪ - ${inv.invoiceDate}',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w500),
                      ),
                      if (inv.notes != null && inv.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'ملاحظات: ${inv.notes}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _restoreInvoice(inv),
                      icon: const Icon(Icons.restore_page, size: 18),
                      label: const Text('استعادة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(inv),
                      icon: const Icon(Icons.delete_forever, size: 18, color: Colors.red),
                      label: const Text('حذف نهائي', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_sweep_outlined, size: 80, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'لا توجد فواتير محذوفة تطابق البحث',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreInvoice(Invoice inv) async {
    final db = context.read<DatabaseService>();
    await db.restoreInvoice(inv);
    _loadDeletedInvoices();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم استعادة الفاتورة بنجاح'), backgroundColor: Colors.green),
    );
  }

  Future<void> _confirmDelete(Invoice inv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نهائي'),
        content: const Text('تحذير: الحذف النهائي لا يمكن التراجع عنه. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف للأبد'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = context.read<DatabaseService>();
      // SAFE-HOUSE: Mark as unsynced so the next push sends the deleted_at
      // tombstone to the server (server will soft-delete, never hard-delete).
      await db.markInvoiceUnsyncedBeforePermanentDelete(inv.id!);
      // Push the tombstone immediately if online.
      try {
        final sync = context.read<SyncService>();
        await sync.performFullSync();
      } catch (_) {
        // Non-fatal: tombstone will be pushed on next successful sync.
      }
      // Hard-delete locally only after the server has the soft-delete record.
      await db.permanentDeleteInvoice(inv.id!);
      _loadDeletedInvoices();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الفاتورة نهائياً'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
