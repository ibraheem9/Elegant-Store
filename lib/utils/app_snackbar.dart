import 'package:flutter/material.dart';

/// Centralized SnackBar helper.
///
/// Rule: **Only the latest alert is shown at any time.**
/// Calling [showAppSnackBar] always removes the currently visible SnackBar
/// (if any) before displaying the new one, preventing a queue of stacked
/// alerts from obscuring the UI.
abstract final class AppSnackBar {
  /// Shows a SnackBar, immediately dismissing any previously visible one.
  ///
  /// [context] — any [BuildContext] within the widget tree.
  /// [message] — the text to display.
  /// [isError]  — red background for errors, green for success (default).
  /// [duration] — how long the SnackBar stays visible (default 3 s).
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // Dismiss any existing SnackBar immediately — no queuing.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Convenience shortcut for error messages.
  static void error(BuildContext context, String message) =>
      show(context, message, isError: true);

  /// Convenience shortcut for success messages.
  static void success(BuildContext context, String message) =>
      show(context, message);
}
