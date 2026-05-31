import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_snackbar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _focusNodePassword = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _keepMeLoggedIn = false;
  bool _showBiometricIcon = false;

  /// Status message shown while the initial sync runs after first login
  String? _syncStatusMessage;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isEnabled = await authService.isBiometricEnabled;
    final canCheck = await authService.canCheckBiometrics();
    if (mounted) {
      setState(() {
        _showBiometricIcon = isEnabled && canCheck;
      });
      if (_showBiometricIcon) {
        // Automatically trigger biometric login if enabled
        _loginWithBiometrics();
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _focusNodePassword.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('يرجى إدخال اسم المستخدم وكلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _syncStatusMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // Step 1: Online API authentication
      // NOTE: _isFirstLogin() is intentionally checked AFTER authService.login()
      // because login() may clear last_sync_time (e.g. when a different user or
      // store logs in). Reading it before login would cause a race condition where
      // firstLogin = false even though login() just cleared last_sync_time.
      final LoginResult result = await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
        saveSession: _keepMeLoggedIn,
      );
      switch (result) {
        case LoginResult.success:
          break; // continue to sync step below
        case LoginResult.customerNotAllowed:
          _showError('هذا الحساب لا يملك صلاحية الدخول للتطبيق');
          return;
        case LoginResult.wrongCredentials:
          _showError('خطأ في اسم المستخدم أو كلمة المرور');
          return;
        case LoginResult.networkError:
          _showError('لا يوجد اتصال بالإنترنت. يرجى الاتصال للدخول لأول مرة');
          return;
        case LoginResult.unknownError:
          final errDetail = authService.lastLoginError;
          _showError(errDetail != null && errDetail.isNotEmpty
              ? 'خطأ: $errDetail'
              : 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى');
          return;
      }

      // Step 2: Check AFTER login() — login() may have cleared last_sync_time
      // for a new user/store, so we must re-read it here, not before login().
      // final bool firstLogin = await _isFirstLogin();

      // Step 3: REMOVED automatic sync after login. 
      // Users should start the sync manually from the dashboard.
      /*
      if (firstLogin && mounted) {
        setState(() => _syncStatusMessage = 'جاري تحميل بيانات المتجر...');
        try {
          await syncService.performFullSync(isInitialSync: true).timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              debugPrint('Initial sync timed out after 60s, continuing anyway');
            },
          );
        } catch (e) {
          // Sync failure must not block login — the user can sync manually later
          debugPrint('Initial sync failed on first login: $e');
        }
      }
      */

      // Navigation is handled automatically by Consumer<AuthService> in main.dart
    } catch (e) {
      _showError('خطأ: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _syncStatusMessage = null;
        });
      }
    }
  }

  Future<void> _loginWithBiometrics() async {
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final LoginResult result = await authService.authenticateWithBiometrics();
      if (result == LoginResult.customerNotAllowed && mounted) {
        _showError('هذا الحساب لا يملك صلاحية الدخول للتطبيق');
      }
      // Other failures are silent — user can still type their password
    } catch (e) {
      // Silent fail for auto-trigger
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppSnackBar.error(context, message);
  }

  Future<void> _showForgotPasswordDialog() async {
    final usernameCtrl = TextEditingController();
    final recoveryKeyCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int step = 1;
    bool isResetting = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('استعادة كلمة المرور', style: TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: isResetting ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step == 1) ...[
                    const Text('الخطوة 1: أدخل اسم المستخدم الخاص بك'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال اسم المستخدم' : null,
                    ),
                  ] else if (step == 2) ...[
                    const Text('الخطوة 2: أدخل مفتاح الاستعادة (UUID)'),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل مفتاح الاستعادة الخاص بك لإعادة تعيين كلمة المرور.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: recoveryKeyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'مفتاح الاستعادة',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال مفتاح الاستعادة' : null,
                    ),
                  ] else if (step == 3) ...[
                    const Text('الخطوة 3: تعيين كلمة مرور جديدة'),
                    const SizedBox(height: 8),
                    const Text(
                      'يرجى كتابة كلمة المرور الجديدة مرتين والتأكد من حفظها في مكان آمن.',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newPasswordCtrl,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور الجديدة',
                        prefixIcon: const Icon(Icons.lock_reset),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 3 ? 'كلمة المرور قصيرة جداً' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmPasswordCtrl,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'يرجى تأكيد كلمة المرور';
                        if (v != newPasswordCtrl.text) return 'كلمات المرور غير متطابقة';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: newPasswordCtrl.text));
                          AppSnackBar.success(context, 'تم نسخ كلمة المرور الجديدة');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('نسخ كلمة المرور لحفظها'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (step > 1)
              TextButton(
                onPressed: isResetting ? null : () => setDialogState(() => step--),
                child: const Text('السابق'),
              ),
            ElevatedButton(
              onPressed: isResetting ? null : () async {
                if (!formKey.currentState!.validate()) return;

                if (step < 3) {
                  // Verify user exists in step 1
                  if (step == 1) {
                    setDialogState(() => isResetting = true);
                    final user = await context.read<DatabaseService>().getUserByUsername(usernameCtrl.text.trim());
                    setDialogState(() => isResetting = false);
                    if (user == null) {
                      if (context.mounted) AppSnackBar.error(context, 'اسم المستخدم غير موجود');
                      return;
                    }
                  }
                  setDialogState(() => step++);
                } else {
                  // Final step: Reset password
                  setDialogState(() => isResetting = true);
                  final success = await context.read<AuthService>().resetPassword(
                    usernameCtrl.text.trim(),
                    recoveryKeyCtrl.text.trim(),
                    newPasswordCtrl.text,
                  );
                  setDialogState(() => isResetting = false);

                  if (success) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('تم بنجاح ✓', textAlign: TextAlign.right),
                          content: const Text(
                            'تم تغيير كلمة المرور بنجاح.\n\nيرجى التأكد من حفظ كلمة المرور في مكان آمن وعدم مشاركتها مع أحد.',
                            textAlign: TextAlign.right,
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('فهمت، شكراً')),
                          ],
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) AppSnackBar.error(context, 'مفتاح الاستعادة غير صحيح لهذا المستخدم');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: isResetting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(step == 3 ? 'تعيين كلمة المرور' : 'التالي'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: size.height,
            width: size.width,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF0F172A)],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Card(
                  elevation: 25,
                  shadowColor: Colors.black.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            height: 120,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.storefront_rounded,
                                    size: 80, color: Colors.blue),
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildTextField(
                          controller: _usernameController,
                          label: 'اسم المستخدم',
                          icon: Icons.person_outline_rounded,
                          hint: 'أدخل اسم المستخدم',
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => FocusScope.of(context).requestFocus(_focusNodePassword),
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'كلمة المرور',
                          icon: Icons.lock_outline_rounded,
                          hint: 'أدخل كلمة المرور',
                          isPassword: true,
                          obscure: _obscurePassword,
                          toggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                          focusNode: _focusNodePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _keepMeLoggedIn,
                                  onChanged: (value) {
                                    setState(() {
                                      _keepMeLoggedIn = value ?? false;
                                    });
                                  },
                                  activeColor: const Color(0xFF1E3A8A),
                                ),
                                const Text(
                                  'تذكرني',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                                ),
                              ],
                            ),
                            if (_showBiometricIcon)
                              IconButton(
                                icon: const Icon(Icons.fingerprint, size: 32, color: Color(0xFF1E3A8A)),
                                onPressed: _isLoading ? null : _loginWithBiometrics,
                                tooltip: 'دخول بالبصمة',
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 5,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('دخول للنظام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _isLoading ? null : _showForgotPasswordDialog,
                          child: const Text(
                            'هل نسيت كلمة المرور؟',
                            style: TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        // Show sync progress on first login
                        if (_syncStatusMessage != null) ...[  
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1E3A8A)),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _syncStatusMessage!,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF475569)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? toggleObscure,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          focusNode: focusNode,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.blue[800]),
            suffixIcon: isPassword ? IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility), onPressed: toggleObscure) : null,
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}
