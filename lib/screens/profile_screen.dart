import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/device_sync_service.dart';
import '../services/auth_service.dart';
import '../models/models.dart';
import '../utils/timestamp_formatter.dart';
import '../services/theme_service.dart';
import '../services/customer_tracking_service.dart';
import '../widgets/whatsapp_input.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _mobileController = TextEditingController();
  final _whatsappController = TextEditingController();
  String _whatsappCountryCode = '+970';

  bool _isLoading = true;
  StoreProfile? _profile;
  DeviceInfoModel? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _mobileController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final authService = context.read<AuthService>();
      final deviceSync = context.read<DeviceSyncService>();
      final deviceId = await deviceSync.getDeviceId();

      // Ensure metrics are up to date
      await db.updateStoreProfileMetrics(deviceId);

      _profile = await db.getStoreProfile(deviceId);
      _deviceInfo = await db.getDeviceInfo(deviceId);

      if (_deviceInfo == null) {
        final name = await deviceSync.getDeviceName();
        _deviceInfo = DeviceInfoModel(
          deviceId: deviceId,
          deviceName: name,
          deviceModel: name,
          locationLat: 0.0,
          locationLong: 0.0,
        );
        await db.saveDeviceInfo(_deviceInfo!);
      }

      if (_profile != null) {
        _storeNameController.text = _profile!.storeName ?? '';
        _ownerNameController.text = _profile!.ownerName ?? '';
        _addressController.text = _profile!.address ?? '';
        _cityController.text = _profile!.city ?? '';
        _mobileController.text = _profile!.mobile ?? '';
        
        final String whatsapp = _profile!.whatsapp ?? '';
        if (whatsapp.startsWith('+972')) {
          _whatsappCountryCode = '+972';
          _whatsappController.text = whatsapp.substring(4);
        } else if (whatsapp.startsWith('+970')) {
          _whatsappCountryCode = '+970';
          _whatsappController.text = whatsapp.substring(4);
        } else {
          _whatsappController.text = whatsapp;
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final authService = context.read<AuthService>();
      final deviceSync = context.read<DeviceSyncService>();
      final deviceId = await deviceSync.getDeviceId();

      String whatsappText = _whatsappController.text.trim();
      if (whatsappText.startsWith('0')) {
        whatsappText = whatsappText.substring(1);
      }
      final fullWhatsapp = '$_whatsappCountryCode$whatsappText';

      final newProfile = (_profile ?? StoreProfile(deviceId: deviceId)).copyWith(
        storeName: _storeNameController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        mobile: _mobileController.text.trim(),
        whatsapp: fullWhatsapp,
        lastActiveTime: TimestampFormatter.nowUtc(),
      );

      await db.saveStoreProfile(newProfile);
      _profile = newProfile;

      // Save to SharedPreferences so CustomerTrackingService can find it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('settings_store_name', _storeNameController.text.trim());
      await prefs.setString('settings_owner_name', _ownerNameController.text.trim());
      await prefs.setString('settings_address', _addressController.text.trim());
      await prefs.setString('settings_city', _cityController.text.trim());
      await prefs.setString('settings_phone', _mobileController.text.trim());
      await prefs.setString('settings_whatsapp', fullWhatsapp);

      // Trigger immediate sync to server
      // ignore: unawaited_futures
      CustomerTrackingService.instance.syncCustomerData(
        recoveryToken: authService.currentUser?.uuid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ البيانات بنجاح وتمت المزامنة')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final authService = context.watch<AuthService>();
    final isManager = authService.isManager();
    // Allow both Manager and Accountant to edit the profile info
    final canEdit = isManager || authService.currentUser?.role == 'ACCOUNTANT';
    final isDark = themeNotifier.themeMode == ThemeMode.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: _isLoading && _profile == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 16 : 32, isMobile ? 16 : 32, 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الملف الشخصي للمتجر',
                        style: TextStyle(
                          fontSize: isMobile ? 24 : 32,
                          fontWeight: FontWeight.w900,
                          color: isDark ? const Color(0xFFDCEFFF) : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Store Information ──────────────────────────────────────────
                      _buildSection('معلومات المتجر', isDark, [
                        _buildResponsiveInputs(isMobile, isDark, [
                          _buildTextField(
                            'اسم المتجر',
                            _storeNameController,
                            Icons.store_rounded,
                            isDark,
                            enabled: canEdit,
                            validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المتجر' : null,
                          ),
                          _buildTextField(
                            'اسم المالك',
                            _ownerNameController,
                            Icons.person_rounded,
                            isDark,
                            enabled: canEdit,
                            validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المالك' : null,
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildResponsiveInputs(isMobile, isDark, [
                          _buildTextField(
                            'العنوان',
                            _addressController,
                            Icons.location_on_rounded,
                            isDark,
                            enabled: canEdit,
                            validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال العنوان' : null,
                          ),
                          _buildTextField(
                            'المدينة',
                            _cityController,
                            Icons.location_city_rounded,
                            isDark,
                            enabled: canEdit,
                            validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال المدينة' : null,
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildResponsiveInputs(isMobile, isDark, [
                          _buildTextField(
                            'رقم الهاتف (جوال)',
                            _mobileController,
                            Icons.phone_android_rounded,
                            isDark,
                            keyboardType: TextInputType.phone,
                            enabled: canEdit,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'يرجى إدخال رقم الجوال';
                              final clean = v.trim();
                              if (!RegExp(r'^(059|056)[0-9]{7}$').hasMatch(clean)) {
                                return 'رقم غير صحيح (يجب أن يبدأ بـ 059 أو 056 ويتكون من 10 أرقام)';
                              }
                              return null;
                            },
                          ),
                          WhatsAppInput(
                            label: 'واتساب (WhatsApp)',
                            selectedCountryCode: _whatsappCountryCode,
                            controller: _whatsappController,
                            onCountryCodeChanged: (v) => setState(() => _whatsappCountryCode = v!),
                            isDark: isDark,
                            enabled: canEdit,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'يرجى إدخال رقم الواتساب';
                              final clean = v.trim();
                              if (!RegExp(r'^0?5[69][0-9]{7}$').hasMatch(clean)) {
                                return 'رقم غير صحيح (يجب أن يتكون من 9 أرقام بعد رمز الدولة)';
                              }
                              return null;
                            },
                          ),
                        ]),
                      ]),

                      const SizedBox(height: 32),

                      if (canEdit)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveProfile,
                            icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, color: Colors.white),
                            label: const Text('حفظ التغييرات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0B74FF),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0B74FF))),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildResponsiveInputs(bool isMobile, bool isDark, List<Widget> children) {
    if (isMobile) {
      return Column(children: children.expand((w) => [w, const SizedBox(height: 16)]).toList()..removeLast());
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children.expand((w) => [Expanded(child: w), const SizedBox(width: 16)]).toList()..removeLast());
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, bool isDark, {TextInputType? keyboardType, bool enabled = true, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      validator: validator,
      style: TextStyle(color: isDark ? Colors.white : (enabled ? Colors.black : Colors.black54)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.black54),
        prefixIcon: Icon(icon, color: const Color(0xFF0B74FF), size: 20),
        filled: true,
        fillColor: isDark ? const Color(0xFF071028) : Colors.grey[50],
        errorStyle: const TextStyle(fontSize: 10, color: Colors.red),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0B74FF), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.grey : Colors.black54, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
