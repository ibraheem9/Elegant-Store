import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/contact_service.dart';

/// Maximum number of images allowed per request.
const int _kMaxImages = 3;

/// Maximum file size per image in bytes (2 MB).
const int _kMaxImageBytes = 2 * 1024 * 1024;

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  final _contactService = ContactService();
  final _picker = ImagePicker();

  ContactInfo? _contactInfo;
  bool _loadingInfo = true;
  bool _submitting = false;
  bool _submitted = false;
  String? _submitError;

  final List<File> _images = [];

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadContactInfo() async {
    try {
      final info = await _contactService.fetchContactInfo();
      if (mounted) setState(() { _contactInfo = info; _loadingInfo = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  // ── Internet check ────────────────────────────────────────────────────────

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((c) => c != ConnectivityResult.none);
  }

  // ── Image handling ────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    if (_images.length >= _kMaxImages) {
      _showSnack('الحد الأقصى ${_kMaxImages} صور فقط', isError: true);
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final file = File(picked.path);
    final size = await file.length();
    if (size > _kMaxImageBytes) {
      _showSnack('حجم الصورة يجب أن يكون أقل من 2 ميغابايت', isError: true);
      return;
    }

    setState(() => _images.add(file));
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  // ── Form submission ───────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final online = await _hasInternet();
    if (!online) {
      _showSnack('لا يوجد اتصال بالإنترنت. هذه الصفحة تتطلب اتصالاً نشطاً.', isError: true);
      return;
    }

    setState(() { _submitting = true; _submitError = null; });

    final result = await _contactService.submitRequest(
      name: _nameCtrl.text.trim(),
      subject: _subjectCtrl.text.trim(),
      message: _messageCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      images: List.unmodifiable(_images),
    );

    if (!mounted) return;

    switch (result) {
      case ContactSubmitSuccess(:final message):
        setState(() { _submitting = false; _submitted = true; });
        _showSnack(message);
      case ContactSubmitFailure(:final error):
        setState(() { _submitting = false; _submitError = error; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: _submitted ? _buildSuccessState(theme) : _buildForm(theme, isDark),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WhatsApp Button (Replaces the old info banner)
          const _WhatsAppButton(),

          const SizedBox(height: 20),

          // Internet notice
          _InternetNotice(isDark: isDark),

          const SizedBox(height: 20),

          // Form card
          Card(
            elevation: 0,
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(title: 'بيانات التواصل', icon: Icons.person_outline_rounded),
                    const SizedBox(height: 16),

                    // Name
                    _FormField(
                      controller: _nameCtrl,
                      label: 'الاسم الكامل *',
                      icon: Icons.person_rounded,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                    ),
                    const SizedBox(height: 12),

                    // Email + Phone row
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            controller: _emailCtrl,
                            label: 'البريد الإلكتروني',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                              return emailRegex.hasMatch(v.trim()) ? null : 'بريد غير صحيح';
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FormField(
                            controller: _phoneCtrl,
                            label: 'رقم الهاتف',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _SectionTitle(title: 'تفاصيل الرسالة', icon: Icons.message_outlined),
                    const SizedBox(height: 16),

                    // Subject
                    _FormField(
                      controller: _subjectCtrl,
                      label: 'الموضوع *',
                      icon: Icons.subject_rounded,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'الموضوع مطلوب' : null,
                    ),
                    const SizedBox(height: 12),

                    // Message
                    _FormField(
                      controller: _messageCtrl,
                      label: 'الرسالة *',
                      icon: Icons.chat_bubble_outline_rounded,
                      maxLines: 5,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'الرسالة مطلوبة';
                        if (v.trim().length < 10) return 'الرسالة قصيرة جداً (10 أحرف على الأقل)';
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),
                    _SectionTitle(
                      title: 'الصور المرفقة (اختياري)',
                      icon: Icons.image_outlined,
                      subtitle: 'حتى $_kMaxImages صور، كل صورة أقل من 2 ميغابايت',
                    ),
                    const SizedBox(height: 12),

                    // Image picker
                    _ImagePickerRow(
                      images: _images,
                      onAdd: _pickImage,
                      onRemove: _removeImage,
                      maxImages: _kMaxImages,
                    ),

                    // Error message
                    if (_submitError != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _submitError!),
                    ],

                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_submitting ? 'جاري الإرسال...' : 'إرسال الرسالة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
            ),
            const SizedBox(height: 24),
            Text('تم الإرسال بنجاح!',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'شكراً لتواصلك معنا.\nسنقوم بمراجعة رسالتك والرد عليك في أقرب وقت ممكن.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _submitted = false;
                _nameCtrl.clear();
                _emailCtrl.clear();
                _phoneCtrl.clear();
                _subjectCtrl.clear();
                _messageCtrl.clear();
                _images.clear();
              }),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إرسال رسالة أخرى'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon, this.subtitle});
  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({
    required this.images,
    required this.onAdd,
    required this.onRemove,
    required this.maxImages,
  });

  final List<File> images;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  final int maxImages;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...images.asMap().entries.map((e) => _ImageThumb(
              file: e.value,
              onRemove: () => onRemove(e.key),
            )),
        if (images.length < maxImages)
          _AddImageButton(onTap: onAdd),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.file, required this.onRemove});
  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file, width: 90, height: 90, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2, right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                color: isDark ? Colors.white54 : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text('إضافة',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton();
  final String phone = "970567228380";

  Future<void> _launchWhatsApp() async {
    final Uri url = Uri.parse("https://wa.me/$phone");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366).withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF25D366).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text(
            'للحصول على دعم فني مباشر وسريع',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _launchWhatsApp,
              icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
              label: const Text(
                'تواصل معنا عبر واتساب',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InternetNotice extends StatelessWidget {
  const _InternetNotice({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_rounded, color: Colors.orange, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذه الصفحة تتطلب اتصالاً بالإنترنت لإرسال رسالتك.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }
}

class _InfoShimmer extends StatelessWidget {
  const _InfoShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
