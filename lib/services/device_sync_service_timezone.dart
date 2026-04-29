import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:async';

/// TimezoneService
///
/// Handles device timezone detection and conversion
class TimezoneService {
  /// Get device timezone identifier (e.g., 'Asia/Baghdad')
  static String getDeviceTimezone() {
    try {
      // Get local timezone
      final now = DateTime.now();
      final offset = now.timeZoneOffset;

      // Try to get timezone name from system
      // Note: This is a simplified approach
      // For production, consider using timezone package
      return _getTimezoneFromOffset(offset);
    } catch (e) {
      debugPrint('[Timezone] Error getting device timezone: $e');
      return 'UTC';
    }
  }

  /// Get timezone offset in milliseconds
  static int getTimezoneOffsetMs() {
    final now = DateTime.now();
    return now.timeZoneOffset.inMilliseconds;
  }

  /// Get timezone offset string (e.g., '+03:00')
  static String getTimezoneOffsetString() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;

    final hours = offset.inHours;
    final minutes = (offset.inMinutes % 60).abs();

    return '${hours >= 0 ? '+' : ''}${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  /// Convert UTC timestamp to local timezone
  static DateTime convertFromUtc(int timestampMs) {
    final utcDateTime =
        DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
    return utcDateTime.toLocal();
  }

  /// Convert local time to UTC timestamp
  static int convertToUtc(DateTime localDateTime) {
    // Convert local to UTC
    final utcDateTime = localDateTime.toUtc();
    return utcDateTime.millisecondsSinceEpoch;
  }

  /// Format datetime for display with timezone
  static String formatWithTimezone(DateTime dateTime) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return '${formatter.format(dateTime)} ${getTimezoneOffsetString()}';
  }

  /// Get start of day in local timezone
  static DateTime getStartOfDayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Get end of day in local timezone
  static DateTime getEndOfDayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  /// Check if timestamp is today in local timezone
  static bool isToday(int timestampMs) {
    final dateTime = convertFromUtc(timestampMs);
    final now = DateTime.now();

    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }

  /// Get timezone name from offset (simplified)
  static String _getTimezoneFromOffset(Duration offset) {
    final hours = offset.inHours;
    final minutes = (offset.inMinutes % 60).abs();

    // Common timezone mappings
    final timezoneMap = {
      '3:0': 'Asia/Baghdad', // Iraq
      '2:0': 'Africa/Cairo', // Egypt
      '1:0': 'Europe/London', // UK
      '0:0': 'UTC',
      '-5:0': 'America/New_York',
      '-8:0': 'America/Los_Angeles',
      '5:30': 'Asia/Kolkata', // India
      '8:0': 'Asia/Shanghai', // China
      '9:0': 'Asia/Tokyo', // Japan
    };

    final key = '$hours:$minutes';
    return timezoneMap[key] ?? 'UTC';
  }
}
