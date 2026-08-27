import 'package:flutter/material.dart';

/// High-contrast, large-touch-target theme.
///
/// The citizen audience skews toward first-time smartphone users
/// unfamiliar with crypto UX conventions, so accessibility (WCAG AA+
/// contrast, large tap targets, immediate visual feedback) is a first-class
/// requirement here, not a polish pass.
class AppTheme {
  const AppTheme._();

  static const Color _green = Color(0xFF1B7A3D);
  static const Color _greenDark = Color(0xFF0F5C2A);
  static const Color _amber = Color(0xFFB86E00);
  static const Color _red = Color(0xFFB3261E);

  static const Color success = _green;
  static const Color warning = _amber;
  static const Color error = _red;
  static const Color greenDark = _greenDark;

  /// Minimum recommended touch target size (dp) used across custom widgets.
  static const double minTouchTarget = 56;

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _green,
      brightness: Brightness.light,
      primary: _green,
      error: _red,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: _textTheme(Colors.black87),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          side: const BorderSide(width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        labelStyle: const TextStyle(fontSize: 18),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
    );
  }

  static TextTheme _textTheme(Color color) {
    return TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: color,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: color,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: TextStyle(fontSize: 18, color: color),
      bodyMedium: TextStyle(fontSize: 16, color: color),
      labelLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}
