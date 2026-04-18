import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LicenseService
//
// Responsibilities:
//   1. Collect a stable hardware fingerprint from the device.
//   2. Verify an RSA-2048 / SHA-256 license signature against the embedded
//      public key.
//   3. Confirm the license was issued for THIS device (hardware ID match).
//   4. Persist the verified license in encrypted secure storage so the check
//      survives app restarts without re-entry.
//
// License format (JSON, then Base64-encoded):
//   {
//     "hardware_id": "<sha256 of device identifiers>",
//     "customer":    "<customer name>",
//     "issued_at":   "<ISO-8601 date>",
//     "expires_at":  "<ISO-8601 date | null for perpetual>"
//   }
//
// The license code the customer receives is:
//   Base64(JSON_payload) + "." + Base64(RSA_signature_of_JSON_payload)
// ─────────────────────────────────────────────────────────────────────────────

enum LicenseStatus {
  valid,
  notActivated,
  invalidSignature,
  wrongDevice,
  expired,
}

class LicenseResult {
  final LicenseStatus status;
  final String? customerName;
  final DateTime? expiresAt;

  const LicenseResult({
    required this.status,
    this.customerName,
    this.expiresAt,
  });

  bool get isValid => status == LicenseStatus.valid;
}

class LicenseService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  // ── Constants ──────────────────────────────────────────────────────────────
  static const _storageKey = 'elegant_store_license_v1';

  /// RSA-2048 public key (PEM) — private key is NEVER in the app.
  static const _publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5fwX9CrFcF/sWfuWvcHW
Obj/kyxOFgqXqlL9YyUKNFBt4tyME1Rq8oRpufOfINx4rD/uft4eg2wSrCOWedfY
oRb92cC4uFtFqBLjhOt49nF6hKwGAlxNUCQwJBuqtfKlmWMYFL8h59KHUoOx0eON
ekpGD5BF+HexFSWZNhPcfaEOtLa/xQdakLmkNaX/S13JkecYfB2/gBQsP9YlMfgX
WBshlAX0viHkWRTScxybI7BLHWuaucM/YZyGmqWb8PASFPe9CyiQ+uq/lobQz0WB
ADPDP8UcxWHP7X8DVwJeaczneyb7nqYCB4NMYOB0lrnIFjT7FIQZr5BP7WQOFXNe
JQIDAQAB
-----END PUBLIC KEY-----''';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the hardware fingerprint for this device.
  /// Show this to the customer so they can send it to you.
  Future<String> getHardwareId() async {
    return _buildHardwareId();
  }

  /// Checks the stored license (if any) and returns the result.
  Future<LicenseResult> checkStoredLicense() async {
    try {
      final stored = await _secureStorage.read(key: _storageKey);
      if (stored == null || stored.isEmpty) {
        return const LicenseResult(status: LicenseStatus.notActivated);
      }
      return _verifyLicenseCode(stored);
    } catch (_) {
      return const LicenseResult(status: LicenseStatus.notActivated);
    }
  }

  /// Validates and stores a license code entered by the user.
  Future<LicenseResult> activateLicense(String licenseCode) async {
    final result = await _verifyLicenseCode(licenseCode.trim());
    if (result.isValid) {
      await _secureStorage.write(key: _storageKey, value: licenseCode.trim());
    }
    return result;
  }

  /// Clears the stored license (for testing / reset).
  Future<void> clearLicense() async {
    await _secureStorage.delete(key: _storageKey);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<LicenseResult> _verifyLicenseCode(String code) async {
    try {
      // 1. Split payload and signature
      final parts = code.split('.');
      if (parts.length != 2) {
        return const LicenseResult(status: LicenseStatus.invalidSignature);
      }

      final payloadB64 = parts[0];
      final sigB64 = parts[1];

      final payloadBytes = base64Decode(_normalizeBase64(payloadB64));
      final sigBytes = base64Decode(_normalizeBase64(sigB64));

      // 2. Verify RSA-SHA256 signature
      if (!_verifySignature(payloadBytes, sigBytes)) {
        return const LicenseResult(status: LicenseStatus.invalidSignature);
      }

      // 3. Parse payload JSON
      final payloadJson =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;

      final licenseHardwareId = payloadJson['hardware_id'] as String? ?? '';
      final customerName = payloadJson['customer'] as String? ?? 'Unknown';
      final expiresAtStr = payloadJson['expires_at'] as String?;

      // 4. Check expiry
      DateTime? expiresAt;
      if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
        expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          return LicenseResult(
            status: LicenseStatus.expired,
            customerName: customerName,
            expiresAt: expiresAt,
          );
        }
      }

      // 5. Check hardware ID match
      final deviceHardwareId = await _buildHardwareId();
      if (licenseHardwareId != deviceHardwareId) {
        return LicenseResult(
          status: LicenseStatus.wrongDevice,
          customerName: customerName,
        );
      }

      return LicenseResult(
        status: LicenseStatus.valid,
        customerName: customerName,
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('LicenseService error: $e');
      return const LicenseResult(status: LicenseStatus.invalidSignature);
    }
  }

  bool _verifySignature(Uint8List payload, Uint8List signature) {
    try {
      final publicKey = _parsePublicKey(_publicKeyPem);
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      final rsaSig = RSASignature(signature);
      return signer.verifySignature(payload, rsaSig);
    } catch (_) {
      return false;
    }
  }

  RSAPublicKey _parsePublicKey(String pem) {
    final stripped = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .trim();
    final derBytes = base64Decode(stripped);
    final asn1Parser = ASN1Parser(Uint8List.fromList(derBytes));
    final topSeq = asn1Parser.nextObject() as ASN1Sequence;
    final bitString = topSeq.elements![1] as ASN1BitString;
    final innerParser =
        ASN1Parser(Uint8List.fromList(bitString.stringValues!));
    final innerSeq = innerParser.nextObject() as ASN1Sequence;
    final modulus =
        (innerSeq.elements![0] as ASN1Integer).integer!;
    final exponent =
        (innerSeq.elements![1] as ASN1Integer).integer!;
    return RSAPublicKey(modulus, exponent);
  }

  Future<String> _buildHardwareId() async {
    final deviceInfo = DeviceInfoPlugin();
    final parts = <String>[];

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await deviceInfo.androidInfo;
        parts.add(info.id);           // Android hardware serial
        parts.add(info.brand);
        parts.add(info.model);
        parts.add(info.hardware);
        parts.add(info.fingerprint);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await deviceInfo.iosInfo;
        parts.add(info.identifierForVendor ?? '');
        parts.add(info.model);
        parts.add(info.name);
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await deviceInfo.windowsInfo;
        parts.add(info.deviceId);
        parts.add(info.computerName);
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await deviceInfo.linuxInfo;
        parts.add(info.machineId ?? '');
        parts.add(info.name);
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await deviceInfo.macOsInfo;
        parts.add(info.systemGUID ?? '');
        parts.add(info.computerName);
      }
    } catch (e) {
      debugPrint('LicenseService: failed to read device info: $e');
    }

    final combined = parts.join('|');
    final digest = sha256.convert(utf8.encode(combined));
    return digest.toString();
  }

  String _normalizeBase64(String s) {
    // Add padding if needed
    final mod = s.length % 4;
    if (mod == 2) return '$s==';
    if (mod == 3) return '$s=';
    return s;
  }
}
