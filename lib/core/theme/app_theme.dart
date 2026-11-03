import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF146B57);
  static const Color ink = Color(0xFF18332B);
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      surface: const Color(0xFFF7FAF8),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7FAF8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7FAF8),
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
