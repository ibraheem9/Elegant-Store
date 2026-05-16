import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/telemetry_service.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _ownerNameController.text = auth.currentUser?.name ?? '';
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
    if (!RegExp(r'^\+(970|972)\d{9}$').hasMatch(value)) {
      return 'يرجى البدء بـ +970 أو +972 متبوعاً بـ 9 أرقام';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final telemetry = context.read<TelemetryService>();
      await telemetry.updateAndUploadProfile(
        storeName: _storeNameController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        whatsappNumber: _whatsappController.text.trim(),
      );
      // Navigation will be handled by main.dart because we notify listeners or state changes
      if (mounted) {
        // Just trigger a rebuild of the app home
        setState(() {});
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
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _whatsappController,
                        label: 'رقم الواتساب',
                        icon: Icons.chat_rounded,
                        hint: '+970xxxxxxxxx',
                        validator: _validateWhatsapp,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator ?? (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
      keyboardType: keyboardType,
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
