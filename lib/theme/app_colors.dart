import 'package:flutter/material.dart';

/// Centralized color palette for the MyParivaar app.
/// All color constants should be defined here to ensure consistency.
class AppColors {
  // ── Primary Colors ──────────────────────────────────────────────────────────
  
  /// Primary brand color (blue)
  static const Color primary = Color(0xFF258cf4);
  
  /// Lighter shade of primary
  static const Color primaryLight = Color(0xFF4ca5ff);
  
  /// Darker shade of primary
  static const Color primaryDark = Color(0xFF1a73e8);

  // ── Background Colors ───────────────────────────────────────────────────────
  
  /// Light mode background color
  static const Color backgroundLight = Color(0xFFFFFFFF);
  
  /// Dark mode background color
  static const Color backgroundDark = Color(0xFF101922);
  
  /// Light mode surface color
  static const Color surfaceLight = Color(0xFFFFFFFF);
  
  /// Dark mode surface color
  static const Color surfaceDark = Color(0xFF1E2836);

  // ── Gradient Colors ─────────────────────────────────────────────────────────
  
  /// Primary gradient start color
  static const Color primaryGradientStart = Color(0xFF258cf4);
  
  /// Primary gradient middle color
  static const Color primaryGradientMiddle = Color(0xFF4ca5ff);
  
  /// Primary gradient end color
  static const Color primaryGradientEnd = Color(0xFF1a73e8);
  
  /// Primary gradient (for use in Container decoration)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGradientStart, primaryGradientMiddle, primaryGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Semantic Colors ─────────────────────────────────────────────────────────
  
  /// Success color (green)
  static const Color success = Color(0xFF4CAF50);
  
  /// Success light variant
  static const Color successLight = Color(0xFFC8E6C9);
  
  /// Success dark variant
  static const Color successDark = Color(0xFF1B5E20);
  
  /// Warning color (orange)
  static const Color warning = Color(0xFFFF9800);
  
  /// Warning light variant
  static const Color warningLight = Color(0xFFFFE0B2);
  
  /// Warning dark variant
  static const Color warningDark = Color(0xFFE65100);
  
  /// Error color (red)
  static const Color error = Color(0xFFF44336);
  
  /// Error light variant
  static const Color errorLight = Color(0xFFFFCDD2);
  
  /// Error dark variant
  static const Color errorDark = Color(0xFFB71C1C);
  
  /// Info color (blue)
  static const Color info = Color(0xFF2196F3);
  
  /// Info light variant
  static const Color infoLight = Color(0xFFBBDEFB);
  
  /// Info dark variant
  static const Color infoDark = Color(0xFF01579B);

  // ── Grey Shades ─────────────────────────────────────────────────────────────
  
  /// Grey 100
  static const Color grey100 = Color(0xFFF5F5F5);
  
  /// Grey 200
  static const Color grey200 = Color(0xFFEEEEEE);
  
  /// Grey 300
  static const Color grey300 = Color(0xFFE0E0E0);
  
  /// Grey 400
  static const Color grey400 = Color(0xFFBDBDBD);
  
  /// Grey 600
  static const Color grey600 = Color(0xFF757575);
  
  /// Grey 700
  static const Color grey700 = Color(0xFF616161);
  
  /// Grey 800
  static const Color grey800 = Color(0xFF424242);
  
  /// Grey 900
  static const Color grey900 = Color(0xFF212121);

  // ── Text Colors ─────────────────────────────────────────────────────────────
  
  /// Primary text color for light mode
  static const Color textPrimaryLight = Color(0xFF000000);
  
  /// Secondary text color for light mode
  static const Color textSecondaryLight = Color(0xFF757575);
  
  /// Primary text color for dark mode
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  
  /// Secondary text color for dark mode
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  // ── Category Colors ─────────────────────────────────────────────────────────
  
  /// Category color palette for expenses
  static const Map<String, CategoryColorPair> categoryColors = {
    'food': CategoryColorPair(
      background: Color(0xFFFFE0B2),
      icon: Color(0xFFE65100),
    ),
    'groceries': CategoryColorPair(
      background: Color(0xFFFFE0B2),
      icon: Color(0xFFE65100),
    ),
    'transport': CategoryColorPair(
      background: Color(0xFFBBDEFB),
      icon: Color(0xFF01579B),
    ),
    'transportation': CategoryColorPair(
      background: Color(0xFFBBDEFB),
      icon: Color(0xFF01579B),
    ),
    'shopping': CategoryColorPair(
      background: Color(0xFFE1BEE7),
      icon: Color(0xFF4A148C),
    ),
    'utilities': CategoryColorPair(
      background: Color(0xFFC8E6C9),
      icon: Color(0xFF1B5E20),
    ),
    'healthcare': CategoryColorPair(
      background: Color(0xFFFFCDD2),
      icon: Color(0xFFB71C1C),
    ),
    'health': CategoryColorPair(
      background: Color(0xFFFFCDD2),
      icon: Color(0xFFB71C1C),
    ),
    'entertainment': CategoryColorPair(
      background: Color(0xFFF8BBD0),
      icon: Color(0xFF880E4F),
    ),
    'gifts': CategoryColorPair(
      background: Color(0xFFF8BBD0),
      icon: Color(0xFF880E4F),
    ),
    'income': CategoryColorPair(
      background: Color(0xFFC8E6C9),
      icon: Color(0xFF1B5E20),
    ),
    'salary': CategoryColorPair(
      background: Color(0xFFC8E6C9),
      icon: Color(0xFF1B5E20),
    ),
  };
  
  /// Default category color for uncategorized items
  static const CategoryColorPair defaultCategoryColor = CategoryColorPair(
    background: Color(0xFFEEEEEE),
    icon: Color(0xFF616161),
  );
  
  /// Get category background color by category name
  static Color getCategoryColor(String category) {
    final colorPair = categoryColors[category.toLowerCase()];
    return colorPair?.background ?? defaultCategoryColor.background;
  }
  
  /// Get category icon color by category name
  static Color getCategoryIconColor(String category) {
    final colorPair = categoryColors[category.toLowerCase()];
    return colorPair?.icon ?? defaultCategoryColor.icon;
  }
}

/// Color pair for category styling (background + icon color)
class CategoryColorPair {
  const CategoryColorPair({
    required this.background,
    required this.icon,
  });
  
  final Color background;
  final Color icon;
}
