import 'package:intl/intl.dart';

/// TimestampFormatter
/// 
/// Utility class for formatting timestamps with timezone awareness.
/// All timestamps are stored in UTC on the server.
/// This class converts them to local timezone for display.
class TimestampFormatter {
  /// Convert UTC timestamp string to local DateTime
  /// 
  /// Input: "2026-04-29T15:30:00.000Z" (UTC)
  /// Output: DateTime in local timezone
  static DateTime toLocalDateTime(String? utcTimestampString) {
    if (utcTimestampString == null || utcTimestampString.isEmpty) {
      return DateTime.now();
    }

    try {
      // Parse UTC timestamp
      final utcDateTime = DateTime.parse(utcTimestampString);
      
      // Convert to local timezone
      // Note: DateTime.parse() already handles UTC if string ends with 'Z'
      // toLocal() converts to device's local timezone
      return utcDateTime.toLocal();
    } catch (e) {
      debugPrint('[TimestampFormatter] Error parsing timestamp: $e');
      return DateTime.now();
    }
  }

  /// Format timestamp for display (short format)
  /// 
  /// Example: "29-04-2026 15:30"
  static String formatShort(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('dd-MM-yyyy HH:mm').format(localDateTime);
  }

  /// Format timestamp for display (medium format)
  /// 
  /// Example: "29-04-2026 15:30:45"
  static String formatMedium(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(localDateTime);
  }

  /// Format timestamp for display (long format with day name)
  /// 
  /// Example: "الثلاثاء 29-04-2026 15:30"
  static String formatLong(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('EEEE dd-MM-yyyy HH:mm', 'ar_SA').format(localDateTime);
  }

  /// Format timestamp for display (Arabic format with day name)
  /// 
  /// Example: "الثلاثاء، 29 أبريل 2026 - 15:30"
  static String formatArabic(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('EEEE، d MMMM yyyy - HH:mm', 'ar_SA').format(localDateTime);
  }

  /// Format time only (HH:mm)
  /// 
  /// Example: "15:30"
  static String formatTimeOnly(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('HH:mm').format(localDateTime);
  }

  /// Format date only (dd-MM-yyyy)
  /// 
  /// Example: "29-04-2026"
  static String formatDateOnly(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('dd-MM-yyyy').format(localDateTime);
  }

  /// Format date only with day name (Arabic)
  /// 
  /// Example: "الثلاثاء 29-04-2026"
  static String formatDateWithDayName(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    return DateFormat('EEEE dd-MM-yyyy', 'ar_SA').format(localDateTime);
  }

  /// Get relative time (e.g., "2 hours ago", "3 days ago")
  /// 
  /// Example: "منذ ساعتين"
  static String formatRelative(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    final now = DateTime.now();
    final difference = now.difference(localDateTime);

    if (difference.inSeconds < 60) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} أيام';
    } else {
      return formatShort(utcTimestampString);
    }
  }

  /// Check if timestamp is today
  static bool isToday(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    final now = DateTime.now();
    return localDateTime.year == now.year &&
        localDateTime.month == now.month &&
        localDateTime.day == now.day;
  }

  /// Check if timestamp is yesterday
  static bool isYesterday(String? utcTimestampString) {
    final localDateTime = toLocalDateTime(utcTimestampString);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return localDateTime.year == yesterday.year &&
        localDateTime.month == yesterday.month &&
        localDateTime.day == yesterday.day;
  }

  /// Get timezone offset from UTC
  /// 
  /// Example: "+03:00" for GMT+3
  static String getTimezoneOffset() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final hours = offset.inHours;
    final minutes = offset.inMinutes.remainder(60);
    return '${hours >= 0 ? '+' : ''}'
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// Get device timezone name
  /// 
  /// Example: "Asia/Baghdad"
  static String getTimezoneNameFromDateTime() {
    return DateTime.now().timeZoneName;
  }
}

// Helper extension for easy formatting on String
extension TimestampFormatterExtension on String? {
  /// Format UTC timestamp to local short format
  String toLocalShort() => TimestampFormatter.formatShort(this);

  /// Format UTC timestamp to local medium format
  String toLocalMedium() => TimestampFormatter.formatMedium(this);

  /// Format UTC timestamp to local long format
  String toLocalLong() => TimestampFormatter.formatLong(this);

  /// Format UTC timestamp to local Arabic format
  String toLocalArabic() => TimestampFormatter.formatArabic(this);

  /// Get local DateTime from UTC timestamp
  DateTime toLocalDateTime() => TimestampFormatter.toLocalDateTime(this);

  /// Check if timestamp is today
  bool isToday() => TimestampFormatter.isToday(this);

  /// Check if timestamp is yesterday
  bool isYesterday() => TimestampFormatter.isYesterday(this);
}
