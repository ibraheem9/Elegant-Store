import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// TimestampFormatter
/// 
/// Utility class for formatting timestamps with timezone awareness.
/// All timestamps are stored in UTC on the server.
/// This class converts them to local timezone for display.
class TimestampFormatter {
  /// Convert timestamp string to local DateTime
  /// 
  /// Input: ISO8601 timestamp string
  /// Output: DateTime in local timezone
  static DateTime toLocalDateTime(String? timestampString) {
    if (timestampString == null || timestampString.isEmpty) {
      return DateTime.now();
    }

    try {
      // Parse timestamp
      // DateTime.parse() handles both UTC (with 'Z') and local formats
      final dateTime = DateTime.parse(timestampString);
      
      // Return as-is (no forced conversion to/from UTC)
      return dateTime;
    } catch (e) {
      debugPrint('[TimestampFormatter] Error parsing timestamp: $e');
      return DateTime.now();
    }
  }

  /// Format timestamp for display (short format)
  /// 
  /// Example: "29-04-2026 3:30 م"
  static String formatShort(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Format timestamp for display (medium format)
  /// 
  /// Example: "29-04-2026 3:30:45 م"
  static String formatMedium(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy h:mm:ss a', 'ar_SA').format(localDateTime);
  }

  /// Format timestamp for display (long format with day name)
  /// 
  /// Example: "الثلاثاء 29-04-2026 3:30 م"
  static String formatLong(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE dd-MM-yyyy h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Format timestamp for display (Arabic format with day name)
  /// 
  /// Example: "الثلاثاء، 29 أبريل 2026 - 3:30 م"
  static String formatArabic(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE، d MMMM yyyy - h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Format time only (h:mm a)
  /// 
  /// Example: "3:30 م"
  static String formatTimeOnly(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Format date only (dd-MM-yyyy)
  /// 
  /// Example: "29-04-2026"
  static String formatDateOnly(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy').format(localDateTime);
  }

  /// Format date only with day name (Arabic)
  /// 
  /// Example: "الثلاثاء 29-04-2026"
  static String formatDateWithDayName(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE dd-MM-yyyy', 'ar_SA').format(localDateTime);
  }

  /// Get relative time (e.g., "2 hours ago", "3 days ago")
  /// 
  /// Example: "منذ ساعتين"
  static String formatRelative(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
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
      return formatShort(timestampString);
    }
  }

  /// Check if timestamp is today
  static bool isToday(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    final now = DateTime.now();
    return localDateTime.year == now.year &&
        localDateTime.month == now.month &&
        localDateTime.day == now.day;
  }

  /// Check if timestamp is yesterday
  static bool isYesterday(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
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

  /// Apply "end of day" rule for past dates
  /// 
  /// If [date] is before today, returns a DateTime with time set to 23:59:59.
  /// Otherwise, returns a DateTime with the current time.
  static DateTime applyPastDateRule(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDate = DateTime(date.year, date.month, date.day);

    if (inputDate.isBefore(today)) {
      // Past date: set to 23:59:59
      return DateTime(date.year, date.month, date.day, 23, 59, 59);
    } else {
      // Today or future: use current time
      return DateTime(date.year, date.month, date.day, now.hour, now.minute, now.second);
    }
  }
}

// Helper extension for easy formatting on String
extension TimestampFormatterExtension on String? {
  /// Format timestamp to local short format
  String toLocalShort() => TimestampFormatter.formatShort(this);

  /// Format timestamp to local medium format
  String toLocalMedium() => TimestampFormatter.formatMedium(this);

  /// Format timestamp to local long format
  String toLocalLong() => TimestampFormatter.formatLong(this);

  /// Format timestamp to local Arabic format
  String toLocalArabic() => TimestampFormatter.formatArabic(this);

  /// Get local DateTime from timestamp
  DateTime toLocalDateTime() => TimestampFormatter.toLocalDateTime(this);

  /// Check if timestamp is today
  bool isToday() => TimestampFormatter.isToday(this);

  /// Check if timestamp is yesterday
  bool isYesterday() => TimestampFormatter.isYesterday(this);
}
