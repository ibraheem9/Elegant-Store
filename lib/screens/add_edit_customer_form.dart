import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point: call this instead of showDialog directly.
// On mobile  → pushes a full-screen page.
// On desktop → opens a modal dialog.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> showAddEditCustomerForm(
  BuildContext context, {
  User? customer,
}) async {
  final bool isMobile = MediaQuery.of(context).size.width < 700;

  if (isMobile) {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddEditCustomerPage(customer: customer),
      ),
    );
    return result ?? false;
  } else {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddEditCustomerDialog(customer: customer),
    );
    return result ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared form state
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerFormController {
  final TextEditingController name;
  final TextEditingController nickname;
  final TextEditingController phone;
  final TextEditingController transferNames;
  final TextEditingController notes;
  final TextEditingController creditLimit;
  final TextEditingController balance;

  _CustomerFormController({User? customer})
    : name = TextEditingController(text: customer?.name ?? ''),
      nickname = TextEditingController(text: customer?.nickname ?? ''),
      phone = TextEditingController(text: customer?.phone ?? ''),
      transferNames = TextEditingController(
        text: customer?.transferNames ?? '',
      ),
      notes = TextEditingController(text: customer?.notes ?? ''),
      creditLimit = TextEditingController(
        text: customer == null
            ? '100'
            : (customer.creditLimit == -1
                  ? ''
                  : customer.creditLimit?.toString() ?? '100'),
      ),
      balance = TextEditingController(
        text: customer?.balance.toString() ?? '0',
      );

  void dispose() {
    name.dispose();
    nickname.dispose();
    phone.dispose();
    transferNames.dispose();
    notes.dispose();
    creditLimit.dispose();
    balance.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The actual form widget (stateful, shared by both page and dialog)
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerFormBody extends StatefulWidget {
  final User? customer;
  final VoidCallback onCancel;
  final Future<void> Function(
    _CustomerFormController ctrl,
    bool isPermanent,
    bool isUnlimited,
  )
  onSave;

  const _CustomerFormBody({
    required this.customer,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_CustomerFormBody> createState() => _CustomerFormBodyState();
}

class _CustomerFormBodyState extends State<_CustomerFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final _CustomerFormController _ctrl;
  late bool _isPermanent;
  late bool _isUnlimited;
  bool _isSaving = false;

  // Per-field error messages
  String? _nameError;
  String? _limitError;
  String? _balanceError;

  @override
  void initState() {
    super.initState();
    _ctrl = _CustomerFormController(customer: widget.customer);
    _isPermanent = widget.customer == null
        ? true
        : (widget.customer!.isPermanentCustomer == 1);
    _isUnlimited = widget.customer?.creditLimit == -1;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Reset errors
    setState(() {
      _nameError = null;
      _limitError = null;
      _balanceError = null;
    });

    bool hasError = false;

    if (_ctrl.name.text.trim().isEmpty) {
      setState(() => _nameError = 'يرجى إدخال اسم الزبون');
      hasError = true;
    }

    if (_isPermanent && !_isUnlimited) {
      final limit = double.tryParse(_ctrl.creditLimit.text);
      if (limit == null || limit < 0) {
        setState(() => _limitError = 'يرجى إدخال سقف دين صحيح');
        hasError = true;
      }
    }

    if (widget.customer != null) {
      final bal = double.tryParse(_ctrl.balance.text);
      if (bal == null) {
        setState(() => _balanceError = 'يرجى إدخال رصيد صحيح');
        hasError = true;
      }
    }

    if (hasError) return;

    // Check for duplicate name on add
    if (widget.customer == null) {
      final db = context.read<DatabaseService>();
      final duplicates = await db.findCustomersByName(_ctrl.name.text.trim());
      if (duplicates.isNotEmpty) {
        setState(() => _nameError = 'يوجد زبون بنفس الاسم بالفعل');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      await widget.onSave(_ctrl, _isPermanent, _isUnlimited);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name ──────────────────────────────────────────────────────
            _buildField(
              label: 'الاسم الكامل *',
              controller: _ctrl.name,
              icon: Icons.person_outline,
              isDark: isDark,
              errorText: _nameError,
              onChanged: (_) => setState(() => _nameError = null),
            ),

            // ── Nickname ──────────────────────────────────────────────────
            _buildField(
              label: 'اللقب',
              controller: _ctrl.nickname,
              icon: Icons.badge_outlined,
              isDark: isDark,
            ),

            // ── Phone ─────────────────────────────────────────────────────
            _buildField(
              label: 'رقم الهاتف',
              controller: _ctrl.phone,
              icon: Icons.phone_android,
              isDark: isDark,
              keyboardType: TextInputType.phone,
            ),

            // ── Transfer names ────────────────────────────────────────────
            _buildField(
              label: 'أسماء التحويلات',
              controller: _ctrl.transferNames,
              icon: Icons.swap_horiz_rounded,
              isDark: isDark,
            ),

            // ── Notes ─────────────────────────────────────────────────────
            _buildField(
              label: 'ملاحظات إضافية',
              controller: _ctrl.notes,
              icon: Icons.note_alt_outlined,
              isDark: isDark,
              maxLines: 2,
            ),

            const SizedBox(height: 8),
            Divider(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
            const SizedBox(height: 8),

            // ── Permanent customer toggle ──────────────────────────────────
            _buildSwitch(
              title: 'زبون دائم',
              subtitle: 'يمكنه الشراء بالدين',
              value: _isPermanent,
              isDark: isDark,
              onChanged: (v) => setState(() => _isPermanent = v),
            ),

            if (_isPermanent) ...[
              const SizedBox(height: 8),

              // ── Unlimited credit checkbox ──────────────────────────────
              _buildCheckbox(
                title: 'دين غير محدود (Verified)',
                value: _isUnlimited,
                isDark: isDark,
                onChanged: (v) => setState(() => _isUnlimited = v ?? false),
              ),

              if (!_isUnlimited) ...[
                const SizedBox(height: 4),
                _buildField(
                  label: 'سقف الدين (₪)',
                  controller: _ctrl.creditLimit,
                  icon: Icons.speed,
                  isDark: isDark,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  errorText: _limitError,
                  onChanged: (_) => setState(() => _limitError = null),
                ),
              ],
            ],

            // ── Balance correction (edit only) ────────────────────────────
            // Allows positive (debtor) and negative (credit) values.
            // Negative balance means the store owes the customer.
            if (widget.customer != null) ...[
              const SizedBox(height: 8),
              _buildField(
                label: 'تصحيح الرصيد الحالي (₪)  [سالب = رصيد لديك]',
                controller: _ctrl.balance,
                icon: Icons.account_balance_wallet,
                isDark: isDark,
                // Use a plain text keyboard so the minus sign is always
                // accessible. The formatter below restricts input to a
                // valid signed decimal number.
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  // Allow: optional leading minus, digits, one decimal point
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                ],
                errorText: _balanceError,
                onChanged: (_) => setState(() => _balanceError = null),
              ),
            ],

            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.customer == null
                                ? 'إضافة الزبون'
                                : 'حفظ التعديلات',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    String? errorText,
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
              ),
              prefixIcon: Icon(icon, size: 20, color: Colors.blue),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF071028)
                  : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: errorText != null
                      ? Colors.redAccent
                      : (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0)),
                  width: errorText != null ? 1.5 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: errorText != null ? Colors.redAccent : Colors.blue,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      errorText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: SwitchListTile.adaptive(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        value: value,
        activeColor: Colors.blue,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildCheckbox({
    required String title,
    required bool value,
    required bool isDark,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071028) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: CheckboxListTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        value: value,
        activeColor: Colors.blue,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save logic (shared)
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _performSave(
  BuildContext context, {
  required User? customer,
  required _CustomerFormController ctrl,
  required bool isPermanent,
  required bool isUnlimited,
}) async {
  final db = context.read<DatabaseService>();
  final auth = context.read<AuthService>();

  final double limit = isUnlimited
      ? -1
      : (double.tryParse(ctrl.creditLimit.text) ?? 100.0);

  final userData = User(
    id: customer?.id,
    uuid: customer?.uuid ?? '',
    parentId: customer?.parentId ?? auth.currentUser?.getStoreManagerIdLocal(),
    username:
        customer?.username ?? 'cust_${DateTime.now().millisecondsSinceEpoch}',
    name: ctrl.name.text.trim(),
    nickname: ctrl.nickname.text.trim(),
    phone: ctrl.phone.text.trim(),
    role: 'CUSTOMER',
    isPermanentCustomer: isPermanent ? 1 : 0,
    creditLimit: isPermanent ? limit : 0.0,
    balance: customer != null
        ? (double.tryParse(ctrl.balance.text) ?? customer.balance)
        : 0.0,
    transferNames: ctrl.transferNames.text.trim(),
    notes: ctrl.notes.text.trim(),
    createdAt: customer?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
  );

  if (customer == null) {
    final newCustId = await db.insertUser(userData, '123');
    final _actUser = context.read<AuthService>().currentUser;
    db
        .logActivity(
          targetId: newCustId,
          targetType: 'CUSTOMER',
          action: 'CREATE',
          summary: 'إضافة زبون جديد: ${userData.name}',
          performedById: _actUser?.id,
          performedByName: _actUser?.name,
          storeManagerId: _actUser?.parentId ?? _actUser?.id,
        )
        .catchError((e) => debugPrint('logActivity failed: $e'));
  } else {
    await db.updateUser(userData, customer);
    final _actUserUpd = context.read<AuthService>().currentUser;
    db
        .logActivity(
          targetId: customer.id!,
          targetType: 'CUSTOMER',
          action: 'UPDATE',
          summary: 'تعديل بيانات الزبون: ${userData.name}',
          performedById: _actUserUpd?.id,
          performedByName: _actUserUpd?.name,
          storeManagerId: _actUserUpd?.parentId ?? _actUserUpd?.id,
        )
        .catchError((e) => debugPrint('logActivity failed: $e'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile: full-screen page
// ─────────────────────────────────────────────────────────────────────────────
class _AddEditCustomerPage extends StatelessWidget {
  final User? customer;
  const _AddEditCustomerPage({this.customer});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdding = customer == null;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF020817)
          : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          onPressed: () => Navigator.of(context).pop(false),
          tooltip: 'رجوع',
        ),
        title: Text(
          isAdding ? 'إضافة زبون جديد' : 'تعديل بيانات الزبون',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      body: _CustomerFormBody(
        customer: customer,
        onCancel: () => Navigator.of(context).pop(false),
        onSave: (ctrl, isPermanent, isUnlimited) async {
          await _performSave(
            context,
            customer: customer,
            ctrl: ctrl,
            isPermanent: isPermanent,
            isUnlimited: isUnlimited,
          );
          if (context.mounted) Navigator.of(context).pop(true);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop: modal dialog
// ─────────────────────────────────────────────────────────────────────────────
class _AddEditCustomerDialog extends StatelessWidget {
  final User? customer;
  const _AddEditCustomerDialog({this.customer});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdding = customer == null;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Dialog header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Colors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAdding ? 'إضافة زبون جديد' : 'تعديل بيانات الزبون',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),
            Divider(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),

            // ── Form body ──────────────────────────────────────────────
            Flexible(
              child: _CustomerFormBody(
                customer: customer,
                onCancel: () => Navigator.of(context).pop(false),
                onSave: (ctrl, isPermanent, isUnlimited) async {
                  await _performSave(
                    context,
                    customer: customer,
                    ctrl: ctrl,
                    isPermanent: isPermanent,
                    isUnlimited: isUnlimited,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
