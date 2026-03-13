import 'package:flutter/material.dart';

/// Centralized text styles for the MyParivaar app.
/// Provides a consistent TextTheme using the Inter font family.
class AppTextStyles {
  /// Base font family (Inter - bundled locally)
  static const String fontFamily = 'Inter';
  
  /// Font weights
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  
  /// Get complete TextTheme for Material3 with Inter font
  static TextTheme getTextTheme(ColorScheme colorScheme) {
    return TextTheme(
      // ── Display Styles ────────────────────────────────────────────────────
      displayLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 57,
        fontWeight: regular,
        letterSpacing: -0.25,
        color: colorScheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 45,
        fontWeight: regular,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 36,
        fontWeight: regular,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      
      // ── Headline Styles ───────────────────────────────────────────────────
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 32,
        fontWeight: semiBold,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: semiBold,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 24,
        fontWeight: semiBold,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      
      // ── Title Styles ──────────────────────────────────────────────────────
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: bold,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: semiBold,
        letterSpacing: 0.15,
        color: colorScheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: medium,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ),
      
      // ── Body Styles ───────────────────────────────────────────────────────
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: regular,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: regular,
        letterSpacing: 0.25,
        color: colorScheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: regular,
        letterSpacing: 0.4,
        color: colorScheme.onSurface,
      ),
      
      // ── Label Styles ──────────────────────────────────────────────────────
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: medium,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: medium,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: medium,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ),
    );
  }
  
  // ── Custom Utility Styles ───────────────────────────────────────────────────
  
  /// Large balance amount text (e.g., ₹45,234.50)
  static TextStyle balanceAmount(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 36,
        fontWeight: bold,
        color: color,
        letterSpacing: -0.5,
      );
  
  /// Card title text
  static TextStyle cardTitle(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: semiBold,
        color: color,
        letterSpacing: 0,
      );
  
  /// Card subtitle text
  static TextStyle cardSubtitle(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: regular,
        color: color,
        letterSpacing: 0.25,
      );
  
  /// Small hint text
  static TextStyle hint(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: regular,
        color: color.withOpacity(0.6),
        letterSpacing: 0.4,
      );
  
  /// Button text
  static TextStyle button(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: semiBold,
        color: color,
        letterSpacing: 0.1,
      );
}
