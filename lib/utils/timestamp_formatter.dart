import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// TimestampFormatter
///
/// Unified UTC timestamp utility for the Elegant Store app.
///
/// STORAGE CONTRACT (enforced everywhere in the codebase):
///   • ALL timestamps (created_at, updated_at, deleted_at, invoice_date) are
///     stored as ISO-8601 UTC strings ending with 'Z'.
///     Example: "2026-05-04T12:30:00.000Z"
///   • The server (Laravel, config timezone = UTC) already stores UTC.
///   • The Flutter app MUST call [nowUtc] / [toUtcString] before every DB write.
///
/// DISPLAY CONTRACT:
///   • NEVER display a raw timestamp string to the user.
///   • Always call one of the format* helpers below, which convert UTC → local.
class TimestampFormatter {
  // ---------------------------------------------------------------------------
  // UTC STORAGE HELPERS  (use these when writing to the database)
  // ---------------------------------------------------------------------------

  /// Returns the current moment as a UTC ISO-8601 string ending with 'Z'.
  /// Use this instead of `DateTime.now().toIso8601String()` everywhere.
  ///
  /// Example output: "2026-05-04T12:30:00.000Z"
  static String nowUtc() => DateTime.now().toUtc().toIso8601String();

  /// Converts any [DateTime] to a UTC ISO-8601 string ending with 'Z'.
  /// Safe to call on both local and UTC DateTime objects.
  static String toUtcString(DateTime dt) => dt.toUtc().toIso8601String();

  /// Applies the "end-of-day" rule for past dates, then returns a UTC string.
  ///
  /// Rule:
  ///   • If [date] is before today (local) → set time to 23:59:59 local, then convert to UTC.
  ///   • If [date] is today or in the future → use current local time, then convert to UTC.
  ///
  /// This is the canonical function to call when the user picks a date for an invoice.
  static String applyPastDateRuleUtc(DateTime date) {
    final now = DateTime.now();
    final todayLocal = DateTime(now.year, now.month, now.day);
    final inputLocal = DateTime(date.year, date.month, date.day);

    DateTime localResult;
    if (inputLocal.isBefore(todayLocal)) {
      // Past date: treat as end-of-business-day in local time
      localResult = DateTime(date.year, date.month, date.day, 23, 59, 59);
    } else {
      // Today or future: use the current clock time
      localResult = DateTime(
          date.year, date.month, date.day, now.hour, now.minute, now.second);
    }
    return localResult.toUtc().toIso8601String();
  }

  /// Legacy helper kept for backward compatibility with screens that still
  /// use [applyPastDateRule] directly. Prefer [applyPastDateRuleUtc] for new code.
  static DateTime applyPastDateRule(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDate = DateTime(date.year, date.month, date.day);
    if (inputDate.isBefore(today)) {
      return DateTime(date.year, date.month, date.day, 23, 59, 59);
    } else {
      return DateTime(
          date.year, date.month, date.day, now.hour, now.minute, now.second);
    }
  }

  // ---------------------------------------------------------------------------
  // PARSING  (always produces a LOCAL DateTime for display)
  // ---------------------------------------------------------------------------

  /// Parses a timestamp string and returns a LOCAL DateTime for display.
  ///
  /// Handles all formats that may exist in the database:
  ///   1. UTC with 'Z'         → "2026-05-04T12:30:00.000Z"   (new format)
  ///   2. UTC with offset      → "2026-05-04T12:30:00+00:00"
  ///   3. Local without offset → "2026-05-04T15:30:00.000"    (legacy local)
  ///   4. Date only            → "2026-05-04"
  ///
  /// For case 3 (legacy local strings without timezone info), DateTime.parse
  /// returns a local DateTime, so .toLocal() is a no-op — correct behaviour.
  static DateTime toLocalDateTime(String? timestampString) {
    if (timestampString == null || timestampString.isEmpty) {
      return DateTime.now();
    }
    try {
      // DateTime.parse returns UTC if string ends with 'Z' or has offset;
      // returns local if no timezone indicator. .toLocal() is safe in both cases.
      return DateTime.parse(timestampString).toLocal();
    } catch (e) {
      debugPrint(
          '[TimestampFormatter] Error parsing timestamp "$timestampString": $e');
      return DateTime.now();
    }
  }

  // ---------------------------------------------------------------------------
  // DISPLAY FORMATTERS  (all produce Arabic-localised strings)
  // ---------------------------------------------------------------------------

  /// Short format: "04-05-2026 3:30 م"
  static String formatShort(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Medium format: "04-05-2026 3:30:45 م"
  static String formatMedium(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy h:mm:ss a', 'ar_SA').format(localDateTime);
  }

  /// Long format with day name: "الاثنين 04-05-2026 3:30 م"
  static String formatLong(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE dd-MM-yyyy h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Arabic format with day name: "الاثنين، 4 مايو 2026 - 3:30 م"
  static String formatArabic(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE، d MMMM yyyy - h:mm a', 'ar_SA')
        .format(localDateTime);
  }

  /// Time only: "3:30 م"
  static String formatTimeOnly(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('h:mm a', 'ar_SA').format(localDateTime);
  }

  /// Date only: "04-05-2026"
  static String formatDateOnly(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('dd-MM-yyyy').format(localDateTime);
  }

  /// Date with day name: "الاثنين 04-05-2026"
  static String formatDateWithDayName(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    return DateFormat('EEEE dd-MM-yyyy', 'ar_SA').format(localDateTime);
  }

  /// Relative time: "منذ ساعتين", "منذ 3 أيام", etc.
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

  // ---------------------------------------------------------------------------
  // UTILITY CHECKS
  // ---------------------------------------------------------------------------

  /// Returns true if the timestamp falls on today (local time).
  static bool isToday(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    final now = DateTime.now();
    return localDateTime.year == now.year &&
        localDateTime.month == now.month &&
        localDateTime.day == now.day;
  }

  /// Returns true if the timestamp falls on yesterday (local time).
  static bool isYesterday(String? timestampString) {
    final localDateTime = toLocalDateTime(timestampString);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return localDateTime.year == yesterday.year &&
        localDateTime.month == yesterday.month &&
        localDateTime.day == yesterday.day;
  }

  /// Returns the device's UTC offset string, e.g. "+03:00".
  static String getTimezoneOffset() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final hours = offset.inHours;
    final minutes = offset.inMinutes.remainder(60);
    return '${hours >= 0 ? '+' : ''}'
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.abs().toString().padLeft(2, '0')}';
  }

  /// Returns the device's timezone name, e.g. "Asia/Baghdad".
  static String getTimezoneNameFromDateTime() {
    return DateTime.now().timeZoneName;
  }
}

// ---------------------------------------------------------------------------
// EXTENSION  (convenience methods on nullable String)
// ---------------------------------------------------------------------------

extension TimestampFormatterExtension on String? {
  /// Converts UTC timestamp to local short display format.
  String toLocalShort() => TimestampFormatter.formatShort(this);

  /// Converts UTC timestamp to local medium display format.
  String toLocalMedium() => TimestampFormatter.formatMedium(this);

  /// Converts UTC timestamp to local long display format.
  String toLocalLong() => TimestampFormatter.formatLong(this);

  /// Converts UTC timestamp to local Arabic display format.
  String toLocalArabic() => TimestampFormatter.formatArabic(this);

  /// Converts UTC timestamp to local date-only display format.
  String toLocalDateOnly() => TimestampFormatter.formatDateOnly(this);

  /// Parses the string and returns a local DateTime.
  DateTime toLocalDateTime() => TimestampFormatter.toLocalDateTime(this);

  /// Returns true if the timestamp is today (local time).
  bool isToday() => TimestampFormatter.isToday(this);

  /// Returns true if the timestamp is yesterday (local time).
  bool isYesterday() => TimestampFormatter.isYesterday(this);
}
