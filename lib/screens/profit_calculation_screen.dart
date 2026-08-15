import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class ProfitCalculationScreen extends StatefulWidget {
  const ProfitCalculationScreen({super.key});

  @override
  State<ProfitCalculationScreen> createState() => _ProfitCalculationScreenState();
}

class _ProfitCalculationScreenState extends State<ProfitCalculationScreen> {
  int _currentStep = 0;
  final TextEditingController _inventoryController = TextEditingController();
  
  // Data State
  double _appSales = 0.0;
  double _appPurchases = 0.0;
  double _outstandingDebts = 0.0;
  double _latestBox = 0.0;
  List<Partner> _partners = [];
  List<PaymentMethod> _allMethods = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedInventory = prefs.getString('last_inventory_value') ?? '';
    if (savedInventory.isNotEmpty) {
      _inventoryController.text = savedInventory;
    }

    final db = context.read<DatabaseService>();
    
    // 1. All-time stats (for Capital calculation)
    final start = DateTime(2020, 1, 1);
    final end = DateTime.now().add(const Duration(days: 365));
    final stats = await db.getDetailedStatsByRange(start: start, end: end);
    
    // 2. Outstanding Debts
    final globalStats = await db.getGlobalStats();
    
    // 3. Latest Box Value (from most recent daily statistics)
    final db_conn = await db.database;
    final boxResult = await db_conn.query(
      'daily_statistics', 
      columns: ['today_cash_in_box'], 
      orderBy: 'statistic_date DESC', 
      limit: 1
    );
    final boxValue = boxResult.isNotEmpty ? (boxResult.first['today_cash_in_box'] as num).toDouble() : 0.0;

    // 4. Partners & Methods
    final partners = await db.getPartners();
    final allMethods = await db.getAllPaymentMethods();

    if (mounted) {
      setState(() {
        _appSales = stats['app_sales'] ?? 0.0;
        _appPurchases = stats['app_purchases'] ?? 0.0;
        _outstandingDebts = globalStats['total_debts'] ?? 0.0;
        _latestBox = boxValue;
        _partners = partners;
        _allMethods = allMethods;
        _isLoading = false;
      });
    }
  }

  // --- Logic Helpers ---

  double _totalPartnerSales = 0.0;
  double _totalPartnerPurchases = 0.0;

  Future<void> _calculatePartnerTotals() async {
    final partnerMethodIds = _allMethods
        .where((m) => m.partnerId != null)
        .map((m) => m.id!)
        .toList();
    
    if (partnerMethodIds.isEmpty) {
      _totalPartnerSales = 0.0;
      _totalPartnerPurchases = 0.0;
      return;
    }

    final db = context.read<DatabaseService>();
    final stats = await db.getStatsByMethodIds(partnerMethodIds);
    
    setState(() {
      _totalPartnerSales = stats['sales'] ?? 0.0;
      _totalPartnerPurchases = stats['purchases'] ?? 0.0;
    });
  }

  double get _totalCapital => _totalPartnerPurchases - _totalPartnerSales;

  double get _netProfit {
    final inventory = double.tryParse(_inventoryController.text) ?? 0.0;
    return (_outstandingDebts + inventory + _latestBox) - _totalCapital;
  }

  Future<Map<String, double>> _getPartnerStats(int partnerId) async {
    final db = context.read<DatabaseService>();
    final methodIds = _allMethods
        .where((m) => m.partnerId == partnerId)
        .map((m) => m.id!)
        .toList();
    return await db.getStatsByMethodIds(methodIds);
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Text(_getStepTitle(), style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: _currentStep > 0 ? IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => setState(() => _currentStep--)) : null,
      ),
      body: _buildStepContent(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'بيانات المتجر الأساسية';
      case 1: return 'إدارة الشركاء';
      case 2: return 'النتيجة النهائية للربح';
      default: return '';
    }
  }

  Widget _buildStepContent() {
    return IndexedStack(
      index: _currentStep,
      children: [
        _buildStep1(),
        _buildStep2(),
        _buildStep3(),
      ],
    );
  }

  // --- STEP 1: Main Parameters ---
  Widget _buildStep1() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoCard('آخر قيمة للصندوق', '${_latestBox.toStringAsFixed(2)} ₪', Icons.account_balance_wallet_rounded, Colors.green),
          const SizedBox(height: 12),
          _buildInfoCard('إجمالي الديون القائمة', '${_outstandingDebts.toStringAsFixed(2)} ₪', Icons.money_off_rounded, Colors.orange),
          const SizedBox(height: 32),
          const Text('أدخل قيمة البضاعة الحالية (المخزون)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right),
          const SizedBox(height: 12),
          TextField(
            controller: _inventoryController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0.00',
              suffixText: '₪',
              filled: true,
              fillColor: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onChanged: (val) async {
              setState(() {});
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('last_inventory_value', val);
            },
          ),
          const SizedBox(height: 40),
          const Text(
            'سيتم استخدام هذه البيانات لحساب صافي الربح ورأس المال في الخطوات التالية.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // --- STEP 2: Partner Management ---
  Widget _buildStep2() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('قائمة الشركاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ElevatedButton.icon(
                onPressed: _showAddPartnerDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة شريك'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: _partners.isEmpty 
            ? const Center(child: Text('لا يوجد شركاء حالياً. يمكنك الضغط على "التالي" للمتابعة بدون شركاء.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _partners.length,
                itemBuilder: (ctx, i) => _buildPartnerTile(_partners[i]),
              ),
        ),
      ],
    );
  }

  Widget _buildPartnerTile(Partner partner) {
    final assignedMethods = _allMethods.where((m) => m.partnerId == partner.id).toList();
    final saleMethods = _allMethods.where((m) => m.category == 'SALE').toList();
    final purchaseMethods = _allMethods.where((m) => m.category == 'PURCHASE').toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: Text(partner.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('وسائل دفع مرتبطة: ${assignedMethods.length}', style: const TextStyle(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMethodSelector(partner, 'وسائل دفع المبيعات', saleMethods, Colors.green),
                const SizedBox(height: 20),
                _buildMethodSelector(partner, 'وسائل دفع المشتريات', purchaseMethods, Colors.orange),
                const Divider(height: 32),
                TextButton.icon(
                  onPressed: () => _deletePartner(partner.id!),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  label: const Text('حذف الشريك', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSelector(Partner partner, String title, List<PaymentMethod> methods, Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: themeColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.map((m) {
            final isAssignedToThis = m.partnerId == partner.id;
            final isAssignedToOther = m.partnerId != null && m.partnerId != partner.id;
            
            return FilterChip(
              label: Text(m.name, style: TextStyle(fontSize: 12, color: isAssignedToOther ? Colors.grey : null)),
              selected: isAssignedToThis,
              onSelected: isAssignedToOther ? null : (selected) async {
                final db = context.read<DatabaseService>();
                await db.assignMethodToPartner(m.id!, selected ? partner.id : null);
                await _loadInitialData(); // Refresh list
              },
              selectedColor: themeColor.withValues(alpha: 0.2),
              checkmarkColor: themeColor,
              disabledColor: Colors.grey.withValues(alpha: 0.05),
              side: isAssignedToOther ? BorderSide(color: Colors.grey.withValues(alpha: 0.2)) : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- STEP 3: Final Results ---
  Widget _buildStep3() {
    return FutureBuilder(
      future: _calculatePartnerTotals(),
      builder: (ctx, snap) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResultSection(
                'رأس المال المجمع للشركاء', 
                _totalCapital, 
                Colors.purple, 
                'مشتريات الشركاء (${_totalPartnerPurchases.toStringAsFixed(0)}) – مقبوضات الشركاء* (${_totalPartnerSales.toStringAsFixed(0)})'
              ),
              const SizedBox(height: 24),
              _buildResultSection(
                'صافي الربح النهائي', 
                _netProfit, 
                Colors.blue,
                '(الديون + المخزون + الصندوق) – رأس مال الشركاء'
              ),
              const SizedBox(height: 32),
              if (_partners.isNotEmpty) ...[
                const Text('توزيع رأس مال الشركاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.right),
                const SizedBox(height: 12),
                ..._partners.map((p) => _buildPartnerCapitalCard(p)),
              ],
              const SizedBox(height: 40),
          _buildDetailedStatistics(),
          const SizedBox(height: 12),
          Text(
            '* مقبوضات الشركاء تشمل كلاً من فواتير البيع وسداد الديون التي تمت عبر وسائلهم المحددة فقط.',
            style: TextStyle(color: Colors.grey[600], fontSize: 10),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 24),
          _buildSaveButton(),
          if (_allMethods.any((m) => m.partnerId == null))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '* ملاحظة: توجد وسائل دفع غير مرتبطة بأي شريك، تم استبعاد مبالغها من الحسبة أعلاه.',
                    style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      }
    );
  }

  bool _isSaving = false;
  Future<void> _handleSaveProfit() async {
    setState(() => _isSaving = true);
    try {
      final db = context.read<DatabaseService>();
      final inventory = double.tryParse(_inventoryController.text) ?? 0.0;
      
      // Prepare details for auditing if needed
      final details = {
        'outstanding_debts': _outstandingDebts,
        'latest_box': _latestBox,
        'app_sales': _appSales,
        'app_purchases': _appPurchases,
        'total_partner_sales': _totalPartnerSales,
        'total_partner_purchases': _totalPartnerPurchases,
      };

      await db.saveProfitRecord(
        inventory: inventory,
        capital: _totalCapital,
        profit: _netProfit,
        detailsJson: jsonEncode(details),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سجل الربح بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSaveButton() {
    return ElevatedButton.icon(
      onPressed: _isSaving ? null : _handleSaveProfit,
      icon: _isSaving 
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.save_rounded),
      label: const Text('حفظ نتيجة الربح والتاريخ', style: TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildResultSection(String title, double value, Color color, String formula) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('${value.toStringAsFixed(2)} ₪', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 16),
          Text('المعادلة: $formula', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPartnerCapitalCard(Partner partner) {
    return FutureBuilder<Map<String, double>>(
      future: _getPartnerStats(partner.id!),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox();
        final sales = snap.data!['sales'] ?? 0.0;
        final purchases = snap.data!['purchases'] ?? 0.0;
        final capital = purchases - sales;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(partner.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${capital.toStringAsFixed(2)} ₪', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('رأس مال الشريك', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(),
                Text('المعادلة: مشترياته (${purchases.toStringAsFixed(0)}) - مبيعاته (${sales.toStringAsFixed(0)})', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildDetailedStatistics() {
    final inventory = double.tryParse(_inventoryController.text) ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Text('ملخص كافة الإحصائيات', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _row('إجمالي المبيعات (تطبيق)', _appSales),
          _row('إجمالي المشتريات (تطبيق)', _appPurchases),
          _row('إجمالي الديون القائمة', _outstandingDebts),
          _row('قيمة الصندوق الحالية', _latestBox),
          _row('قيمة المخزون المدخلة', inventory),
        ],
      ),
    );
  }

  Widget _row(String label, double val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${val.toStringAsFixed(2)} ₪', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  // --- Step Navigation ---

  Widget _buildBottomNav() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () {
            if (_currentStep < 2) {
              setState(() => _currentStep++);
            } else {
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(_currentStep < 2 ? 'التالي' : 'إغلاق', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  // --- Dialogs ---

  void _showAddPartnerDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة شريك جديد', textAlign: TextAlign.right),
        content: TextField(controller: controller, textAlign: TextAlign.right, decoration: const InputDecoration(hintText: 'اسم الشريك')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              final db = context.read<DatabaseService>();
              await db.upsertPartner(controller.text.trim());
              await _loadInitialData();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePartner(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الشريك'),
        content: const Text('هل أنت متأكد من حذف هذا الشريك؟ سيتم فك ارتباط وسائل الدفع الخاصة به.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final db = context.read<DatabaseService>();
      await db.deletePartner(id);
      await _loadInitialData();
    }
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(width: 12),
              Icon(icon, color: color),
            ],
          ),
        ],
      ),
    );
  }
}
