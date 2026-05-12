import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/license_service.dart';
import '../services/contact_service.dart';

/// Cache key for the persisted WhatsApp number.
const _kWhatsappCacheKey = 'cached_whatsapp_number';

/// Shown when the app has no valid license.
/// The user must enter a license code to proceed.
class LicenseGateScreen extends StatefulWidget {
  final VoidCallback onLicenseActivated;

  const LicenseGateScreen({Key? key, required this.onLicenseActivated})
      : super(key: key);

  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  final _codeController = TextEditingController();

  bool _isLoading         = false;
  bool _isLoadingDeviceId = true;
  bool _isSendingWhatsApp = false;
  String _deviceId        = '';
  String? _errorMessage;
  bool _showCode          = false;

  /// WhatsApp number — loaded from cache first, then refreshed from API.
  String? _whatsappNumber;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    _loadWhatsappNumber();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Device ID ──────────────────────────────────────────────────────────────

  Future<void> _loadDeviceId() async {
    final id = await LicenseService.instance.getHardwareId();
    if (mounted) {
      setState(() {
        _deviceId = id;
        _isLoadingDeviceId = false;
      });
    }
  }

  // ── WhatsApp number: cache-first, then refresh from API ───────────────────

  Future<void> _loadWhatsappNumber() async {
    // 1. Load cached value immediately so the button is usable offline.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kWhatsappCacheKey);
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() => _whatsappNumber = cached);
    }

    // 2. Try to refresh from the API in the background.
    try {
      final online = await _hasInternet();
      if (!online) return;

      final contactService = ContactService();
      final info = await contactService.fetchContactInfo();
      final fresh = info.whatsapp;

      if (fresh != null && fresh.isNotEmpty) {
        // Persist for future offline use.
        await prefs.setString(_kWhatsappCacheKey, fresh);
        if (mounted) setState(() => _whatsappNumber = fresh);
      }
    } catch (_) {
      // Silently ignore — cached value is still available.
    }
  }

  // ── License activation ────────────────────────────────────────────────────

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كود الترخيص');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await LicenseService.instance.activateLicense(code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isValid) {
      widget.onLicenseActivated();
    } else {
      setState(() => _errorMessage = _statusMessage(result.status));
    }
  }

  String _statusMessage(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.invalidSignature:
        return 'كود الترخيص غير صحيح أو تالف. يرجى التواصل مع المطور.';
      case LicenseStatus.wrongDevice:
        return 'هذا الترخيص مخصص لجهاز آخر. يرجى التواصل مع المطور.';
      case LicenseStatus.expired:
        return 'انتهت صلاحية هذا الترخيص. يرجى التواصل مع المطور لتجديده.';
      default:
        return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    _showSnackBar('تم نسخ معرّف الجهاز', Colors.green);
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  // ── WhatsApp send flow ────────────────────────────────────────────────────

  Future<void> _onSendWhatsApp() async {
    if (_isLoadingDeviceId || _deviceId.isEmpty) {
      _showSnackBar('جارٍ تحميل معرّف الجهاز، يرجى الانتظار...', Colors.orange);
      return;
    }

    // Check internet connectivity.
    final online = await _hasInternet();
    if (!online) {
      _showSnackBar('لا يوجد اتصال بالإنترنت. يرجى التحقق من الاتصال.', Colors.red);
      return;
    }

    // Ensure we have a WhatsApp number (cached or fresh).
    final number = _whatsappNumber;
    if (number == null || number.isEmpty) {
      _showSnackBar('تعذر الحصول على رقم الواتساب. يرجى المحاولة لاحقاً.', Colors.red);
      return;
    }

    // Ask for user name before sending.
    final name = await _showNameDialog();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _isSendingWhatsApp = true);

    try {
      // Sanitize: remove spaces, dashes, parentheses.
      final sanitized = number.replaceAll(RegExp(r'[\s\-\(\)]'), '');

      // Single message with name on line 1 and device ID on line 2
      // so the receiver can easily copy the device ID separately.
      final combinedText = 'الاسم: ${name.trim()}\n${_deviceId}';
      final encodedMsg = Uri.encodeComponent(combinedText);
      final uri = Uri.parse('https://wa.me/$sanitized?text=$encodedMsg');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('تعذر فتح واتساب. تأكد من تثبيت التطبيق.', Colors.red);
      }
    } catch (_) {
      _showSnackBar('حدث خطأ أثناء فتح واتساب.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSendingWhatsApp = false);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: Color(0xFFD4A017), size: 24),
              const SizedBox(width: 8),
              Text(
                'أدخل اسمك',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم إرسال اسمك ومعرّف جهازك إلى المطور عبر واتساب.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'الاسم الكامل...',
                  hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: Color(0xFFD4A017)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(
                'إلغاء',
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, name);
              },
              icon: const Icon(Icons.send_rounded,
                  size: 16, color: Colors.white),
              label: const Text(
                'إرسال',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;
    final isSmall = size.width < 600;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF020817) : const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 24 : 48,
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo with black background ───────────────────────────
                Center(
                  child: Container(
                    width: isSmall ? 220 : 260,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Subtitle only (no title text) ────────────────────────
                Text(
                  'يرجى إدخال كود الترخيص لتفعيل التطبيق',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // ── Device ID card ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.fingerprint_rounded,
                              color: Colors.blue, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'معرّف جهازك (أرسله للمطور)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isLoadingDeviceId)
                        const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _showCode
                                    ? _deviceId
                                    : '${_deviceId.substring(0, 8)}••••••••••••••••••••••••',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: isDark
                                      ? Colors.white60
                                      : const Color(0xFF475569),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _showCode
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onPressed: () =>
                                  setState(() => _showCode = !_showCode),
                              tooltip: _showCode ? 'إخفاء' : 'إظهار',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded,
                                  size: 18, color: Colors.blue),
                              onPressed: _copyDeviceId,
                              tooltip: 'نسخ المعرّف',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── WhatsApp Button ──────────────────────────────────────
                ElevatedButton.icon(
                  onPressed:
                      (_isSendingWhatsApp || _isLoadingDeviceId)
                          ? null
                          : _onSendWhatsApp,
                  icon: _isSendingWhatsApp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 18, color: Colors.white),
                  label: Text(
                    _isSendingWhatsApp
                        ? 'جارٍ الفتح...'
                        : 'إرسال معرّف الجهاز عبر واتساب',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    disabledBackgroundColor:
                        const Color(0xFF25D366).withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),

                const SizedBox(height: 24),

                // ── License code input ───────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _errorMessage != null
                          ? Colors.redAccent
                          : (isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE2E8F0)),
                      width: _errorMessage != null ? 1.5 : 1,
                    ),
                  ),
                  child: TextField(
                    controller: _codeController,
                    maxLines: 4,
                    minLines: 3,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: 0.3,
                    ),
                    decoration: InputDecoration(
                      hintText: 'الصق كود الترخيص هنا...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white24 : Colors.black26,
                        fontSize: 13,
                        fontFamily: 'sans-serif',
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),
                ),

                // ── Inline error ─────────────────────────────────────────
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 15, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ── Activate button ──────────────────────────────────────
                ElevatedButton(
                  onPressed: _isLoading ? null : _activate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text(
                          'تفعيل التطبيق',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                ),

                const SizedBox(height: 16),

                // ── Contact hint ─────────────────────────────────────────
                Text(
                  'للحصول على ترخيص، أرسل معرّف جهازك للمطور عبر واتساب',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white30 : Colors.black38,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
