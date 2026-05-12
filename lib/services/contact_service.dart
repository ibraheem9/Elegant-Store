import 'dart:io';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/config/api_config.dart';

/// Holds the contact information shown to the user on the contact screen.
class ContactInfo {
  final String? phone;
  final String? email;
  final String? whatsapp;
  final String? address;
  final String? workingHours;

  const ContactInfo({
    this.phone,
    this.email,
    this.whatsapp,
    this.address,
    this.workingHours,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) => ContactInfo(
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        whatsapp: json['whatsapp'] as String?,
        address: json['address'] as String?,
        workingHours: json['working_hours'] as String?,
      );

  bool get isEmpty =>
      phone == null &&
      email == null &&
      whatsapp == null &&
      address == null &&
      workingHours == null;
}

/// Result of a contact form submission.
sealed class ContactSubmitResult {
  const ContactSubmitResult();
}

class ContactSubmitSuccess extends ContactSubmitResult {
  final String message;
  const ContactSubmitSuccess(this.message);
}

class ContactSubmitFailure extends ContactSubmitResult {
  final String error;
  const ContactSubmitFailure(this.error);
}

/// Service responsible for all contact-related API calls.
class ContactService {
  ContactService() : _dio = _buildDio();

  final Dio _dio;

  static Dio _buildDio() => Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'ElegantStore/1.0 (Dart/3.5; Android)',
          },
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetches the contact settings (phone, email, etc.) from the server.
  Future<ContactInfo> fetchContactInfo() async {
    final response = await _dio.get('contact/settings');
    final body = response.data;
    if (body is Map<String, dynamic>) {
      // API returns: { "success": true, "settings": { "whatsapp": "...", ... } }
      final payload = body['settings'] as Map<String, dynamic>?
          ?? body['data'] as Map<String, dynamic>?
          ?? body;
      return ContactInfo.fromJson(payload);
    }
    return const ContactInfo();
  }

  /// Submits a contact request with optional image attachments.
  Future<ContactSubmitResult> submitRequest({
    required String name,
    required String subject,
    required String message,
    String? email,
    String? phone,
    List<File> images = const [],
  }) async {
    try {
      final formData = await _buildFormData(
        name: name,
        subject: subject,
        message: message,
        email: email,
        phone: phone,
        images: images,
      );

      final response = await _dio.post(
        'contact',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final msg = (response.data['message'] as String?) ??
          'تم إرسال رسالتك بنجاح. سنتواصل معك قريباً.';
      return ContactSubmitSuccess(msg);
    } on DioException catch (e) {
      return ContactSubmitFailure(_mapDioError(e));
    } catch (e) {
      return ContactSubmitFailure('حدث خطأ غير متوقع. يرجى المحاولة مجدداً.');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<FormData> _buildFormData({
    required String name,
    required String subject,
    required String message,
    String? email,
    String? phone,
    required List<File> images,
  }) async {
    final deviceInfo = await _getDeviceInfo();

    final fields = <String, dynamic>{
      'name': name,
      'subject': subject,
      'message': message,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'device_info': deviceInfo,
    };

    final formData = FormData.fromMap(fields);

    for (final file in images) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      formData.files.add(MapEntry(
        'images[]',
        await MultipartFile.fromFile(file.path, filename: fileName),
      ));
    }

    return formData;
  }

  Future<String> _getDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return '${info.manufacturer} ${info.model} (Android ${info.version.release})';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return '${info.name} (iOS ${info.systemVersion})';
      } else if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return 'Windows ${info.displayVersion}';
      }
    } catch (_) {}
    return kIsWeb ? 'Web' : Platform.operatingSystem;
  }

  String _mapDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'انتهت مهلة الاتصال. تحقق من الإنترنت وأعد المحاولة.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت.';
    }
    final statusCode = e.response?.statusCode;
    if (statusCode == 422) {
      final errors = e.response?.data['errors'] as Map<String, dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        return (errors.values.first as List).first as String;
      }
      return e.response?.data['message'] as String? ??
          'بيانات غير صحيحة. يرجى مراجعة المدخلات.';
    }
    if (statusCode != null && statusCode >= 500) {
      return 'خطأ في السيرفر. يرجى المحاولة لاحقاً.';
    }
    return 'حدث خطأ أثناء الإرسال. يرجى المحاولة مجدداً.';
  }
}
