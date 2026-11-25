import 'package:flutter/material.dart';

/// Dark theme: deep wine-red and purple gradients with light text.
/// Scaffolds are transparent so the app-wide gradient (painted once in
/// MaterialApp.builder) shows through every page.
class AppTheme {
  static const crimson = Color(0xFFE04560); // accents: buttons, sliders, icons
  static const purple = Color(0xFFB57BE6);

  /// Page background: dark wine -> dark magenta -> deep purple.
  static const backgroundGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A0A18), Color(0xFF521032), Color(0xFF2A1055)]);

  /// Mini player card: crimson -> purple.
  static const accentGradient = LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF8E1B3A), Color(0xFF5B2A9A)]);

  /// Shadow under floating cards.
  static const shadow = Colors.black;

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF9E1B32), brightness: Brightness.dark).copyWith(
      primary: crimson,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF6E1630),
      onPrimaryContainer: const Color(0xFFFFD9DF),
      secondary: purple,
      onSecondary: const Color(0xFF2A0B47),
      secondaryContainer: const Color(0xFF47207A),
      onSecondaryContainer: const Color(0xFFEBD7FF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
      ),
    );
  }
}
