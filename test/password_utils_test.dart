import 'package:flutter_test/flutter_test.dart';
import 'package:abd_elhadi_store/utils/password_utils.dart';

void main() {
  group('PasswordUtils Tests', () {
    test('hashPassword should return a valid BCrypt hash', () {
      const password = 'mySecurePassword123';
      final hash = PasswordUtils.hashPassword(password);
      
      expect(hash, startsWith('\$2'));
      expect(hash.length, greaterThan(20));
    });

    test('verifyPassword should return true for correct password', () {
      const password = 'mySecurePassword123';
      final hash = PasswordUtils.hashPassword(password);
      
      expect(PasswordUtils.verifyPassword(password, hash), isTrue);
    });

    test('verifyPassword should return false for incorrect password', () {
      const password = 'mySecurePassword123';
      const wrongPassword = 'wrongPassword';
      final hash = PasswordUtils.hashPassword(password);
      
      expect(PasswordUtils.verifyPassword(wrongPassword, hash), isFalse);
    });

    test('isHashed should correctly identify BCrypt hashes', () {
      const password = 'mySecurePassword123';
      final hash = PasswordUtils.hashPassword(password);
      
      expect(PasswordUtils.isHashed(hash), isTrue);
      expect(PasswordUtils.isHashed(password), isFalse);
    });

    test('verifyPassword should handle non-hash strings gracefully', () {
      expect(PasswordUtils.verifyPassword('password', 'not-a-hash'), isFalse);
    });
  });
}
