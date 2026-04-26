import 'package:flutter/material.dart';

class AppColors {
  // Light Theme Colors
  static const Color lightPrimary = Color(0xFF1976D2); // Blue 700
  static const Color lightPrimaryVariant = Color(0xFF1565C0); // Blue 800
  static const Color lightSecondary = Color(0xFFD32F2F); // Red 700
  static const Color lightBackground = Color(0xFFFFFFFF); // White
  static const Color lightSurface = Color(0xFFF5F5F5); // Grey 100
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnBackground = Color(0xFF212121); // Grey 900
  static const Color lightOnSurface = Color(0xFF212121); // Grey 900
  static const Color lightError = Color(0xFFB00020); // Red
  static const Color lightOnError = Color(0xFFFFFFFF); // White

  // Dark Theme Colors
  static const Color darkPrimary = Color(0xFF90CAF9); // Blue 200
  static const Color darkPrimaryVariant = Color(0xFF64B5F6); // Blue 300
  static const Color darkSecondary = Color(0xFFEF9A9A); // Red 200
  static const Color darkBackground = Color(0xFF121212); // Dark Grey
  static const Color darkSurface = Color(0xFF1E1E1E); // Darker Grey
  static const Color darkOnPrimary = Color(0xFF000000); // Black
  static const Color darkOnSecondary = Color(0xFF000000); // Black
  static const Color darkOnBackground = Color(0xFFFFFFFF); // White
  static const Color darkOnSurface = Color(0xFFFFFFFF); // White
  static const Color darkError = Color(0xFFCF6679); // Red
  static const Color darkOnError = Color(0xFF000000); // Black

  // Common Colors
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color warning = Color(0xFFFFC107); // Amber
  static const Color info = Color(0xFF2196F3); // Blue

  // ── Customer Balance Color System ─────────────────────────────────────────
  // Green  → customer has credit with us (positive balance = we owe them)
  // Red    → customer is a debtor (positive balance in DB = they owe us)
  // Blue   → paid invoice
  // Grey   → zero balance (settled)

  /// Customer card / row background — debtor (balance > 0, owes us)
  static const Color debtorBackground = Color(0xFFFFF5F5);
  static const Color debtorBackgroundDark = Color(0xFF2E0A0A);
  static const Color debtorBorder = Color(0xFFFFCDD2);
  static const Color debtorBorderDark = Color(0xFF7F1D1D);
  static const Color debtorText = Color(0xFFD32F2F); // Red 700
  static const Color debtorBadge = Color(0xFFEF5350); // Red 400

  /// Customer card / row background — has credit (balance < 0, we owe them)
  static const Color creditBackground = Color(0xFFF0FDF4);
  static const Color creditBackgroundDark = Color(0xFF0A2E1A);
  static const Color creditBorder = Color(0xFF86EFAC);
  static const Color creditBorderDark = Color(0xFF166534);
  static const Color creditText = Color(0xFF16A34A); // Green 600
  static const Color creditBadge = Color(0xFF22C55E); // Green 500

  /// Customer card / row background — zero balance (settled)
  static const Color zeroBackground = Color(0xFFF8FAFC);
  static const Color zeroBackgroundDark = Color(0xFF1E293B);
  static const Color zeroBorder = Color(0xFFE2E8F0);
  static const Color zeroBorderDark = Color(0xFF334155);
  static const Color zeroText = Color(0xFF94A3B8); // Slate 400
  static const Color zeroBadge = Color(0xFF64748B); // Slate 500

  /// Invoice status colors
  static const Color invoicePaid = Color(0xFF1D4ED8); // Blue 700
  static const Color invoicePaidBackground = Color(0xFFEFF6FF); // Blue 50
  static const Color invoicePaidBorder = Color(0xFFBFDBFE); // Blue 200
  static const Color invoiceUnpaid = Color(0xFFDC2626); // Red 600
  static const Color invoiceUnpaidBackground = Color(0xFFFEF2F2); // Red 50
  static const Color invoiceUnpaidBorder = Color(0xFFFECACA); // Red 200
  static const Color invoiceDeferred = Color(0xFFD97706); // Amber 600
  static const Color invoiceDeferredBackground = Color(0xFFFFFBEB); // Amber 50
  static const Color invoiceDeferredBorder = Color(0xFFFDE68A); // Amber 200
  static const Color invoiceDeposit = Color(0xFF16A34A); // Green 600
  static const Color invoiceDepositBackground = Color(0xFFF0FDF4); // Green 50
  static const Color invoiceDepositBorder = Color(0xFFBBF7D0); // Green 200

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the balance text color based on the customer's balance value.
  /// balance > 0 → debtor (red), balance < 0 → has credit (green), 0 → grey
  static Color balanceTextColor(double balance) {
    if (balance > 0) return debtorText;
    if (balance < 0) return creditText;
    return zeroText;
  }

  /// Returns the card background color for a customer card.
  static Color customerCardBackground(double balance, {bool isDark = false}) {
    if (balance > 0) return isDark ? debtorBackgroundDark : debtorBackground;
    if (balance < 0) return isDark ? creditBackgroundDark : creditBackground;
    return isDark ? zeroBackgroundDark : zeroBackground;
  }

  /// Returns the card border color for a customer card.
  static Color customerCardBorder(double balance, {bool isDark = false}) {
    if (balance > 0) return isDark ? debtorBorderDark : debtorBorder;
    if (balance < 0) return isDark ? creditBorderDark : creditBorder;
    return isDark ? zeroBorderDark : zeroBorder;
  }

  /// Returns the invoice status color (text/icon) based on payment_status.
  static Color invoiceStatusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':
        return invoicePaid;
      case 'UNPAID':
        return invoiceUnpaid;
      case 'DEFERRED':
        return invoiceDeferred;
      default:
        return zeroText;
    }
  }

  /// Returns the invoice status background color.
  static Color invoiceStatusBackground(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':
        return invoicePaidBackground;
      case 'UNPAID':
        return invoiceUnpaidBackground;
      case 'DEFERRED':
        return invoiceDeferredBackground;
      default:
        return zeroBackground;
    }
  }

  /// Returns the invoice status border color.
  static Color invoiceStatusBorder(String? status) {
    switch (status?.toUpperCase()) {
      case 'PAID':
        return invoicePaidBorder;
      case 'UNPAID':
        return invoiceUnpaidBorder;
      case 'DEFERRED':
        return invoiceDeferredBorder;
      default:
        return zeroBorder;
    }
  }
}
