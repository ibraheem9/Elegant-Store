import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppThemes {
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.lightPrimary,
    colorScheme: const ColorScheme.light(
      primary: AppColors.lightPrimary,
      primaryContainer: AppColors.lightPrimaryVariant,
      secondary: AppColors.lightSecondary,
      background: AppColors.lightBackground,
      surface: AppColors.lightSurface,
      onPrimary: AppColors.lightOnPrimary,
      onSecondary: AppColors.lightOnSecondary,
      onBackground: AppColors.lightOnBackground,
      onSurface: AppColors.lightOnSurface,
      error: AppColors.lightError,
      onError: AppColors.lightOnError,
    ),
    scaffoldBackgroundColor: AppColors.lightBackground,
    appBarTheme: const AppBarTheme(
      color: AppColors.lightPrimary,
      foregroundColor: AppColors.lightOnPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.lightOnPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: AppColors.lightOnBackground, fontSize: 57, fontWeight: FontWeight.w400),
      displayMedium: TextStyle(color: AppColors.lightOnBackground, fontSize: 45, fontWeight: FontWeight.w400),
      displaySmall: TextStyle(color: AppColors.lightOnBackground, fontSize: 36, fontWeight: FontWeight.w400),
      headlineLarge: TextStyle(color: AppColors.lightOnBackground, fontSize: 32, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: AppColors.lightOnBackground, fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(color: AppColors.lightOnBackground, fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: AppColors.lightOnBackground, fontSize: 22, fontWeight: FontWeight.w500),
      titleMedium: TextStyle(color: AppColors.lightOnBackground, fontSize: 16, fontWeight: FontWeight.w400),
      titleSmall: TextStyle(color: AppColors.lightOnBackground, fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: AppColors.lightOnBackground, fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(color: AppColors.lightOnBackground, fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(color: AppColors.lightOnBackground, fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(color: AppColors.lightOnBackground, fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: AppColors.lightOnBackground, fontSize: 12, fontWeight: FontWeight.w400),
      labelSmall: TextStyle(color: AppColors.lightOnBackground, fontSize: 11, fontWeight: FontWeight.w500),
    ).apply(
      bodyColor: AppColors.lightOnBackground,
      displayColor: AppColors.lightOnBackground,
    ),
    iconTheme: const IconThemeData(
      color: AppColors.lightOnSurface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.lightPrimary,
        foregroundColor: AppColors.lightOnPrimary,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightPrimary, width: 2),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: AppColors.darkPrimary,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      primaryContainer: AppColors.darkPrimaryVariant,
      secondary: AppColors.darkSecondary,
      background: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      onPrimary: AppColors.darkOnPrimary,
      onSecondary: AppColors.darkOnSecondary,
      onBackground: AppColors.darkOnBackground,
      onSurface: AppColors.darkOnSurface,
      error: AppColors.darkError,
      onError: AppColors.darkOnError,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      color: AppColors.darkSurface,
      foregroundColor: AppColors.darkOnSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.darkOnSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: AppColors.darkOnBackground, fontSize: 57, fontWeight: FontWeight.w400),
      displayMedium: TextStyle(color: AppColors.darkOnBackground, fontSize: 45, fontWeight: FontWeight.w400),
      displaySmall: TextStyle(color: AppColors.darkOnBackground, fontSize: 36, fontWeight: FontWeight.w400),
      headlineLarge: TextStyle(color: AppColors.darkOnBackground, fontSize: 32, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: AppColors.darkOnBackground, fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(color: AppColors.darkOnBackground, fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: AppColors.darkOnBackground, fontSize: 22, fontWeight: FontWeight.w500),
      titleMedium: TextStyle(color: AppColors.darkOnBackground, fontSize: 16, fontWeight: FontWeight.w400),
      titleSmall: TextStyle(color: AppColors.darkOnBackground, fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: AppColors.darkOnBackground, fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(color: AppColors.darkOnBackground, fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(color: AppColors.darkOnBackground, fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(color: AppColors.darkOnBackground, fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: AppColors.darkOnBackground, fontSize: 12, fontWeight: FontWeight.w400),
      labelSmall: TextStyle(color: AppColors.darkOnBackground, fontSize: 11, fontWeight: FontWeight.w500),
    ).apply(
      bodyColor: AppColors.darkOnBackground,
      displayColor: AppColors.darkOnBackground,
    ),
    iconTheme: const IconThemeData(
      color: AppColors.darkOnSurface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.darkPrimary,
        foregroundColor: AppColors.darkOnPrimary,
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkPrimary, width: 2),
      ),
    ),
  );
}
