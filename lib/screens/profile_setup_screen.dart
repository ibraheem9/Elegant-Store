import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/database_service.dart';
import '../services/license_service.dart';
import '../services/import_service.dart';
import '../widgets/whatsapp_input.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({Key? key}) : super(key: key);

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  String _selectedCountryCode = '+970';
  bool _isLoading = false;
  bool _isDataRealConfirmed = false;
  bool _isLicensed = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _ownerNameController.text = auth.currentUser?.name ?? '';
    _checkLicense();
  }

  Future<void> _checkLicense() async {
    final result = await LicenseService.instance.checkStoredLicense();
    if (mounted) {
      setState(() => _isLicensed = result.isValid);
    }
  }

  Future<void> _importData() async {
    setState(() => _isLoading = true);
    try {
      final importService = ImportService(context.read<DatabaseService>());
      final result = await importService.pickAndImport();

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Trigger a refresh of the profile completion status
          await context.read<TelemetryService>().checkProfileCompletion();
        } else if (result.message != 'لم يتم اختيار أي ملف.') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال رقم الهاتف';
    if (!RegExp(r'^05[69]\d{7}$').hasMatch(value)) {
      return 'يرجى إدخال رقم فلسطيني صحيح (059xxxxxxx)';
    }
    return null;
  }

  String? _validateWhatsapp(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال رقم واتساب';
    if (!RegExp(r'^0?\d{9}$').hasMatch(value)) {
      return 'يرجى إدخال 9 أرقام بعد رمز الدولة';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final telemetry = context.read<TelemetryService>();
      String whatsappText = _whatsappController.text.trim();
      if (whatsappText.startsWith('0')) {
        whatsappText = whatsappText.substring(1);
      }
      final fullWhatsapp = '$_selectedCountryCode$whatsappText';
      await telemetry.updateAndUploadProfile(
        storeName: _storeNameController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        whatsappNumber: fullWhatsapp,
      );
      // Navigation will be handled by main.dart because we notify listeners or state changes
      if (mounted) {
        // Trigger a refresh of the profile completion status in TelemetryService
        await telemetry.checkProfileCompletion();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.store_rounded, size: 64, color: Colors.blue),
                      const SizedBox(height: 16),
                      const Text(
                        'إعداد ملف المتجر',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'يرجى إكمال البيانات التالية لبدء استخدام النظام',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      if (_isLicensed) ...[
                        _buildImportButton(),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'أو قم بإنشاء ملف جديد',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildTextField(
                        controller: _storeNameController,
                        label: 'اسم المتجر',
                        icon: Icons.shop_two_rounded,
                        hint: 'مثال: محلات الأناقة',
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _ownerNameController,
                        label: 'اسم صاحب المتجر',
                        icon: Icons.person_rounded,
                        hint: 'الاسم الكامل',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _cityController,
                              label: 'المدينة',
                              icon: Icons.location_city_rounded,
                              hint: 'غزة، نابلس، إلخ',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _addressController,
                              label: 'العنوان',
                              icon: Icons.map_rounded,
                              hint: 'اسم الشارع',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'رقم الهاتف',
                        icon: Icons.phone_android_rounded,
                        hint: '059xxxxxxx',
                        validator: _validatePhone,
                        keyboardType: TextInputType.phone,
                        textAlign: TextAlign.left,
                      ),
                      const SizedBox(height: 16),
                      WhatsAppInput(
                        label: 'رقم الواتساب',
                        selectedCountryCode: _selectedCountryCode,
                        controller: _whatsappController,
                        onCountryCodeChanged: (v) => setState(() => _selectedCountryCode = v!),
                        validator: _validateWhatsapp,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _isDataRealConfirmed,
                              onChanged: (v) => setState(() => _isDataRealConfirmed = v ?? false),
                              activeColor: Colors.blue,
                            ),
                            const Expanded(
                              child: Text(
                                'أؤكد أن هذه البيانات حقيقية وتخص متجري. هذه البيانات مهمة جداً لضمان استمرارية عمل التطبيق والحصول على التحديثات المستقبلية.',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: (_isLoading || !_isDataRealConfirmed) ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('حفظ والانتقال للوحة التحكم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _importData,
      icon: const Icon(Icons.upload_file_rounded, color: Colors.blue),
      label: const Text(
        'استيراد البيانات من نسخة احتياطية (JSON)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: const BorderSide(color: Colors.blue, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextAlign textAlign = TextAlign.start,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator ?? (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
      keyboardType: keyboardType,
      textAlign: textAlign,
      textDirection: textAlign == TextAlign.left ? ui.TextDirection.ltr : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
