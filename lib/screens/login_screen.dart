import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

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

  /// Returns true if this is the very first login (no previous sync has completed).
  Future<bool> _isFirstLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_sync_time') == null;
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
      final syncService = Provider.of<SyncService>(context, listen: false);

      final bool firstLogin = await _isFirstLogin();

      // Step 1: Online API authentication
      final bool success = await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
        saveSession: _keepMeLoggedIn,
      );

      if (!success) {
        _showError('خطأ في اسم المستخدم أو كلمة المرور');
        return;
      }

      // Step 2: On first login, await the initial sync so the dashboard has data
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
      bool success = await authService.authenticateWithBiometrics();
      if (!success && mounted) {
        // If it failed (user cancelled or other reason), we don't necessarily show an error 
        // because they can still type their password.
      }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
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
              padding: const EdgeInsets.all(24.0),
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
                        Image.asset(
                          'assets/logo.png',
                          height: 120,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront_rounded, size: 80, color: Colors.blue),
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
                              Text(
                                _syncStatusMessage!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF475569)),
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
