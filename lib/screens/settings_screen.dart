import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../models/models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;
  bool _canCheckBiometrics = false;
  bool _isExporting = false;
  bool _isImporting = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final auth = context.read<AuthService>();
    _nameController.text = auth.currentUser?.name ?? '';
    _usernameController.text = auth.currentUser?.username ?? '';

    final prefs = await SharedPreferences.getInstance();
    final canBio = await auth.canCheckBiometrics();
    final bioEnabled = await auth.isBiometricEnabled;

    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _biometricEnabled = bioEnabled;
      _canCheckBiometrics = canBio;
      String? timeStr = prefs.getString('notification_time');
      if (timeStr != null) {
        final parts = timeStr.split(':');
        _notificationTime = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    });
  }

  Future<void> _updateProfile() async {
    final auth = context.read<AuthService>();
    final success = await auth.updateProfile(
        _nameController.text, _usernameController.text);
    if (success) {
      _showSnackBar('تم تحديث الملف الشخصي بنجاح', Colors.green);
    } else {
      _showSnackBar(
          'فشل تحديث الملف الشخصي. تأكد من الاتصال بالإنترنت.', Colors.red);
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text.length < 3) {
      _showSnackBar('كلمة المرور قصيرة جداً', Colors.red);
      return;
    }
    final auth = context.read<AuthService>();
    final success = await auth.changePassword(
        _currentPasswordController.text, _newPasswordController.text);
    if (success) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _showSnackBar('تم تغيير كلمة المرور بنجاح', Colors.green);
    } else {
      _showSnackBar(
          'فشل تغيير كلمة المرور. تأكد من كلمة المرور الحالية والاتصال.',
          Colors.red);
    }
  }

  Future<void> _saveNotificationSettings(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
    await prefs.setString('notification_time',
        "${_notificationTime.hour}:${_notificationTime.minute}");
    setState(() => _notificationsEnabled = enabled);

    if (enabled) {
      NotificationService.scheduleDailyCheck(context.read<DatabaseService>());
    }
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final auth = context.read<AuthService>();
    if (enabled) {
      final LoginResult result = await auth.authenticateWithBiometrics();
      if (result == LoginResult.success) {
        await auth.setBiometricEnabled(true);
        setState(() => _biometricEnabled = true);
        _showSnackBar('تم تفعيل الدخول بالبصمة بنجاح', Colors.green);
      } else {
        _showSnackBar(
            'فشل التحقق من البصمة. يرجى تسجيل الدخول أولاً.', Colors.red);
      }
    } else {
      await auth.setBiometricEnabled(false);
      setState(() => _biometricEnabled = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT / IMPORT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final db = context.read<DatabaseService>();
      final exportService = ExportService(db);
      final String? filePath = await exportService.exportAndShare();
      if (!mounted) return;
      if (filePath == null) {
        // User cancelled the Save-As dialog (Windows) — no feedback needed.
        return;
      }
      _showSnackBar('تم تصدير البيانات بنجاح ✓', Colors.green);
    } catch (e) {
      if (mounted) {
        _showSnackBar('فشل التصدير: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('استيراد البيانات', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.upload_file_rounded, color: Colors.orange),
          ],
        ),
        content: const Text(
          'سيتم دمج البيانات الواردة مع قاعدة البيانات الحالية.\n\nالسجلات الموجودة ستُحدَّث فقط إذا كان الملف أحدث منها.\n\nهل تريد المتابعة؟',
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.start,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('استيراد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);
    try {
      final db = context.read<DatabaseService>();
      final importService = ImportService(db);
      final result = await importService.pickAndImport();
      if (!mounted) return;
      if (!result.success) {
        _showSnackBar(result.message, Colors.red);
        return;
      }
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                result.errors.isEmpty ? 'تم الاستيراد بنجاح ✓' : 'اكتمل الاستيراد مع تحذيرات',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: result.errors.isEmpty ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                result.errors.isEmpty ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: result.errors.isEmpty ? Colors.green : Colors.orange,
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(result.message, textAlign: TextAlign.right),
                const SizedBox(height: 12),
                const Divider(),
                const Text('السجلات المُعالَجة:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...result.upsertedCounts.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B74FF))),
                      Text(e.key),
                    ],
                  ),
                )),
                if (result.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text('التحذيرات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 6),
                  ...result.errors.take(5).map((e) => Text('• $e', style: const TextStyle(fontSize: 12, color: Colors.red))),
                  if (result.errors.length > 5)
                    Text('... و${result.errors.length - 5} تحذيرات أخرى', style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _showSnackBar('فشل الاستيراد: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final isDark = themeNotifier.themeMode == ThemeMode.dark;
    final auth = context.read<AuthService>();
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 16 : 32, isMobile ? 16 : 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإعدادات والتحكم',
              style: TextStyle(
                fontSize: isMobile ? 24 : 32,
                fontWeight: FontWeight.w900,
                color: isDark
                    ? const Color(0xFFDCEFFF)
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 32),

            // ── Profile ───────────────────────────────────────────────────
            _buildSection('الملف الشخصي', isDark, [
              _buildResponsiveInputs(isMobile, isDark, [
                _buildTextField('الاسم الكامل', _nameController,
                    Icons.person, isDark),
                _buildTextField('اسم المستخدم', _usernameController,
                    Icons.alternate_email, isDark),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B74FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('تحديث البيانات',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),

            const SizedBox(height: 32),

            // ── Change Password ───────────────────────────────────────────
            _buildSection('تغيير كلمة المرور', isDark, [
              _buildResponsiveInputs(isMobile, isDark, [
                _buildTextField('كلمة المرور الحالية',
                    _currentPasswordController, Icons.lock_outline, isDark,
                    obscure: true),
                _buildTextField('كلمة المرور الجديدة',
                    _newPasswordController, Icons.lock_reset, isDark,
                    obscure: true),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('تغيير كلمة المرور',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),

            const SizedBox(height: 32),

            // ── Security ──────────────────────────────────────────────────
            _buildSection('الحماية والأمان', isDark, [
              if (_canCheckBiometrics)
                SwitchListTile(
                  title: const Text('تفعيل الدخول ببصمة الإصبع',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'استخدم البصمة لتسجيل الدخول السريع بدلاً من كلمة المرور'),
                  value: _biometricEnabled,
                  onChanged: _toggleBiometric,
                  activeColor: Colors.green,
                  secondary:
                      const Icon(Icons.fingerprint, color: Colors.green),
                )
              else
                const ListTile(
                  title: Text('البصمة غير مدعومة'),
                  subtitle: Text(
                      'جهازك لا يدعم المصادقة الحيوية أو لم يتم إعدادها'),
                  leading: Icon(Icons.fingerprint, color: Colors.grey),
                ),
            ]),

            const SizedBox(height: 32),

            // ── System & Notifications ────────────────────────────────────
            _buildSection('النظام والتنبيهات', isDark, [
              SwitchListTile(
                title: Text(
                  'الوضع الداكن (Dark Mode)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black),
                ),
                value: isDark,
                onChanged: (val) => themeNotifier.toggleTheme(val),
                secondary: Icon(Icons.dark_mode,
                    color: isDark
                        ? const Color(0xFF00E5FF)
                        : Colors.grey),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('تفعيل تنبيهات الديون والتحصيل',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                value: _notificationsEnabled,
                onChanged: _saveNotificationSettings,
                activeColor: const Color(0xFF0B74FF),
              ),
            ]),

            const SizedBox(height: 32),

            // ── Data Export / Import ──────────────────────────────────
            _buildSection('النسخ الاحتياطي والاستعادة', isDark, [
              ListTile(
                leading: _isExporting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded,
                        color: Color(0xFF0B74FF), size: 28),
                title: const Text(
                  'تصدير قاعدة البيانات (JSON)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'تصدير جميع البيانات (مستخدمون، فواتير، معاملات، مشتريات، إحصائيات) كملف JSON مترابط يمكن استخدامه لاستعادة أي قاعدة بيانات.',
                ),
                onTap: _isExporting ? null : _exportData,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: _isImporting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                      )
                    : const Icon(Icons.upload_file_rounded,
                        color: Colors.orange, size: 28),
                title: const Text(
                  'استيراد من ملف JSON',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'استعادة أو دمج البيانات من ملف نسخة احتياطية. السجلات الأحدث تُحدِّث القديمة (last-write-wins).',
                ),
                onTap: _isImporting ? null : _importData,
              ),
            ]),

            // ── Developer Tools ───────────────────────────────────────────
            if (auth.isDeveloper()) ...[
              const SizedBox(height: 32),
              _buildSection('إدارة متقدمة (للمطور)', isDark, [
                ListTile(
                  title: const Text('إعادة ضبط حالة المزامنة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  leading:
                      const Icon(Icons.sync_problem, color: Colors.blue),
                  onTap: () async {
                    await context
                        .read<DatabaseService>()
                        .resetSyncStatus();
                    _showSnackBar(
                        'تمت إعادة ضبط المزامنة', Colors.blue);
                  },
                ),
              ]),
            ],

            const SizedBox(height: 48),
            Center(
              child: TextButton.icon(
                onPressed: () => auth.logout(),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('تسجيل الخروج',
                    style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ),
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildResponsiveInputs(
      bool isMobile, bool isDark, List<Widget> children) {
    if (isMobile) {
      return Column(
        children: children
            .expand((w) => [w, const SizedBox(height: 16)])
            .toList()
          ..removeLast(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .expand(
              (w) => [Expanded(child: w), const SizedBox(width: 16)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _buildSection(
      String title, bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B74FF))),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      IconData icon, bool isDark,
      {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: isDark ? Colors.grey : Colors.black54),
        prefixIcon: Icon(icon, color: const Color(0xFF0B74FF)),
        filled: true,
        fillColor:
            isDark ? const Color(0xFF071028) : Colors.transparent,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}
