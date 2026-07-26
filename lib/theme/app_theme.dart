import 'package:flutter/material.dart';

class AppTheme {
  // ── Traverse City Palette ──────────────────
  static const Color red       = Color(0xFFC41E3A);
  static const Color redDark   = Color(0xFF8B1428);
  static const Color redLight  = Color(0xFFE8475F);
  static const Color white     = Color(0xFFFFFFFF);
  static const Color whiteDark = Color(0xFFF5F5F5);
  static const Color gold      = Color(0xFFF8D49B);
  static const Color goldDark  = Color(0xFFE8B96A);
  static const Color cream     = Color(0xFFF8E6CB);
  static const Color creamLight= Color(0xFFFDF3E4);

  // ── Semantic ───────────────────────────────
  static const Color success = redLight;
  static const Color warning = goldDark;
  static const Color danger  = Color(0xFFD65E5E);
  static const Color bgApp   = Color(0xFFF0E8D8);
  static const Color bgCard  = Colors.white;
  static const Color textPrimary   = Color(0xFF2B3A4A);
  static const Color textSecondary = Color(0xFF4E6272);
  static const Color textMuted     = Color(0xFF7FA3B5);

  // ── Gradient ───────────────────────────────
  static const LinearGradient headerGradient = LinearGradient(
    colors: [red, redLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [red, redLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Inter font helper ─────────────────────
  static const String _fontFamily = 'Inter';

  static TextStyle _inter({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // ── ThemeData ──────────────────────────────
  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: red,
        primary: red,
        secondary: redLight,
        surface: creamLight,
        error: danger,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: bgApp,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
        fontFamily: _fontFamily,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: red,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _inter(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 2,
        shadowColor: red.withOpacity(0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: red.withOpacity(0.10)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: red.withOpacity(0.35),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _inter(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: creamLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: red.withOpacity(0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: red.withOpacity(0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: red, width: 1.8),
        ),
        labelStyle: _inter(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary),
        hintStyle: _inter(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgCard,
        selectedColor: red,
        labelStyle: _inter(fontSize: 12, fontWeight: FontWeight.w700),
        side: BorderSide(color: red.withOpacity(0.18)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: red.withOpacity(0.12), thickness: 1),
    );
  }
}
