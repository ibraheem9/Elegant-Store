import 'package:bcrypt/bcrypt.dart';

class PasswordUtils {
  /// Hashes a plain-text password using BCrypt.
  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  /// Verifies if a plain-text password matches a BCrypt hash.
  static bool verifyPassword(String password, String hashed) {
    try {
      // Check if it's a valid BCrypt hash
      if (!hashed.startsWith('\$2')) {
        // Fallback for plain-text if we are in transition (handled in DB service usually)
        return false;
      }
      return BCrypt.checkpw(password, hashed);
    } catch (e) {
      return false;
    }
  }

  /// Checks if a string is likely a BCrypt hash.
  static bool isHashed(String text) {
    return text.startsWith('\$2');
  }
}
