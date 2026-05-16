import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/telemetry_service.dart';
import '../models/models.dart';

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({Key? key}) : super(key: key);

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final profile = await db.getOwnerProfile();
    if (profile != null) {
      _storeNameController.text = profile.storeName;
      _ownerNameController.text = profile.ownerName;
      _addressController.text = profile.address;
      _cityController.text = profile.city;
      _phoneController.text = profile.phoneNumber;
      _whatsappController.text = profile.whatsappNumber;
    }
    if (mounted) setState(() => _isLoading = false);
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

    setState(() => _isSaving = true);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث بيانات المتجر بنجاح ✓'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ملف المتجر والمالك',
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.w900,
              color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildResponsiveRow(isMobile, [
                    _buildTextField('اسم المتجر', _storeNameController, Icons.shop_two_rounded),
                    _buildTextField('اسم صاحب المتجر', _ownerNameController, Icons.person_pin_rounded),
                  ]),
                  const SizedBox(height: 16),
                  _buildResponsiveRow(isMobile, [
                    _buildTextField('المدينة', _cityController, Icons.location_city_rounded),
                    _buildTextField('العنوان', _addressController, Icons.map_rounded),
                  ]),
                  const SizedBox(height: 16),
                  _buildResponsiveRow(isMobile, [
                    _buildTextField('رقم الهاتف', _phoneController, Icons.phone_android_rounded, validator: _validatePhone),
                    _buildTextField('رقم الواتساب', _whatsappController, Icons.chat_rounded, validator: _validateWhatsapp),
                  ]),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, color: Colors.white),
                      label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ التعديلات', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children: children.expand((w) => [w, const SizedBox(height: 16)]).toList()..removeLast(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.expand((w) => [Expanded(child: w), const SizedBox(width: 16)]).toList()..removeLast(),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      validator: validator ?? (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
