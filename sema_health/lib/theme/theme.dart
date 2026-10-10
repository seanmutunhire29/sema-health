import 'package:flutter/material.dart';
import 'tokens.dart';

class SemaTheme {
  SemaTheme._();

  /// Type ramp mirrors the reference mockup:
  /// • Plus Jakarta Sans — bundled OFL, ships offline (no runtime fetch).
  /// • Display sizes ride on tight negative tracking and a w700 base, with
  ///   w800 reserved for in-sentence emphasis (e.g. "your needs").
  /// • Eyebrow labels are uppercase-ish, w500, muted ink.
  static const _family = 'Plus Jakarta Sans';
  static const _ink = SemaColors.ink;
  static const _mid = SemaColors.inkMid;
  static const _muted = SemaColors.inkMuted;

  static const TextTheme _text = TextTheme(
    // Hero numerals like the "89%" stat.
    displayLarge: TextStyle(
      fontFamily: _family,
      fontSize: 56, height: 1.0,
      fontWeight: FontWeight.w800, letterSpacing: -2.0, color: _ink,
    ),
    // Primary screen headlines — "How do you feel about your current emotions?"
    displayMedium: TextStyle(
      fontFamily: _family,
      fontSize: 30, height: 1.12,
      fontWeight: FontWeight.w700, letterSpacing: -1.0, color: _ink,
    ),
    // Secondary hero — "Based on your surveys"
    displaySmall: TextStyle(
      fontFamily: _family,
      fontSize: 26, height: 1.15,
      fontWeight: FontWeight.w700, letterSpacing: -0.7, color: _ink,
    ),
    headlineLarge: TextStyle(
      fontFamily: _family,
      fontSize: 22, height: 1.2,
      fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: _family,
      fontSize: 18, height: 1.25,
      fontWeight: FontWeight.w700, letterSpacing: -0.3, color: _ink,
    ),
    titleLarge: TextStyle(
      fontFamily: _family,
      fontSize: 16, height: 1.3,
      fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _ink,
    ),
    titleMedium: TextStyle(
      fontFamily: _family,
      fontSize: 14, height: 1.35,
      fontWeight: FontWeight.w600, letterSpacing: -0.1, color: _ink,
    ),
    titleSmall: TextStyle(
      fontFamily: _family,
      fontSize: 12.5, height: 1.35,
      fontWeight: FontWeight.w600, letterSpacing: 0.0, color: _ink,
    ),
    bodyLarge: TextStyle(
      fontFamily: _family,
      fontSize: 15, height: 1.5,
      fontWeight: FontWeight.w400, letterSpacing: -0.1, color: _ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: _family,
      fontSize: 13.5, height: 1.5,
      fontWeight: FontWeight.w400, letterSpacing: -0.05, color: _mid,
    ),
    bodySmall: TextStyle(
      fontFamily: _family,
      fontSize: 12, height: 1.45,
      fontWeight: FontWeight.w400, letterSpacing: 0.0, color: _muted,
    ),
    labelLarge: TextStyle(
      fontFamily: _family,
      fontSize: 14, height: 1.2,
      fontWeight: FontWeight.w600, letterSpacing: -0.1, color: _ink,
    ),
    // Eyebrows — "Practices", "Daily reflection", "Statistics".
    labelMedium: TextStyle(
      fontFamily: _family,
      fontSize: 11.5, height: 1.2,
      fontWeight: FontWeight.w500, letterSpacing: 0.4, color: _muted,
    ),
    labelSmall: TextStyle(
      fontFamily: _family,
      fontSize: 10.5, height: 1.2,
      fontWeight: FontWeight.w500, letterSpacing: 0.6, color: _muted,
    ),
  );

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _family,
      scaffoldBackgroundColor: SemaColors.bg,
      colorScheme: const ColorScheme.light(
        primary: SemaColors.forest,
        onPrimary: Colors.white,
        secondary: SemaColors.coffee,
        onSecondary: Colors.white,
        surface: SemaColors.bg,
        onSurface: SemaColors.ink,
        error: SemaColors.danger,
      ),
      textTheme: _text,
      primaryTextTheme: _text,
      iconTheme: const IconThemeData(color: SemaColors.ink, size: 22),
      dividerTheme: const DividerThemeData(
        color: SemaColors.hairline, thickness: 1, space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS:   CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: SemaColors.cardSoft,
    );
  }
}
