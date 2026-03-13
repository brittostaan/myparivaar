import 'package:flutter/material.dart';

/// Centralized dimension constants for consistent spacing, sizing, and radii throughout the app.
/// 
/// Usage:
/// ```dart
/// Padding(
///   padding: EdgeInsets.all(AppDimensions.paddingMedium),
///   child: Container(
///     decoration: BoxDecoration(
///       borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
///     ),
///   ),
/// )
/// ```
class AppDimensions {
  AppDimensions._(); // Private constructor to prevent instantiation

  // ══════════════════════════════════════════════════════════════════════════
  // Spacing & Padding
  // ══════════════════════════════════════════════════════════════════════════
  
  /// Extra small spacing: 4.0
  static const double spacingXs = 4.0;
  
  /// Small spacing: 8.0
  static const double spacingSmall = 8.0;
  
  /// Medium spacing (default): 16.0
  static const double spacingMedium = 16.0;
  
  /// Large spacing: 24.0
  static const double spacingLarge = 24.0;
  
  /// Extra large spacing: 32.0
  static const double spacingXl = 32.0;
  
  /// Extra extra large spacing: 48.0
  static const double spacingXxl = 48.0;

  // Padding aliases (same values as spacing for consistency)
  
  /// Extra small padding: 4.0
  static const double paddingXs = spacingXs;
  
  /// Small padding: 8.0
  static const double paddingSmall = spacingSmall;
  
  /// Medium padding (default): 16.0
  static const double paddingMedium = spacingMedium;
  
  /// Large padding: 24.0
  static const double paddingLarge = spacingLarge;
  
  /// Extra large padding: 32.0
  static const double paddingXl = spacingXl;
  
  /// Extra extra large padding: 48.0
  static const double paddingXxl = spacingXxl;

  // ══════════════════════════════════════════════════════════════════════════
  // Border Radius
  // ══════════════════════════════════════════════════════════════════════════
  
  /// Small border radius: 4.0
  static const double radiusSmall = 4.0;
  
  /// Medium border radius (default): 8.0
  static const double radiusMedium = 8.0;
  
  /// Large border radius: 12.0
  static const double radiusLarge = 12.0;
  
  /// Extra large border radius: 16.0
  static const double radiusXl = 16.0;
  
  /// Extra extra large border radius: 24.0
  static const double radiusXxl = 24.0;
  
  /// Circular (pill-shaped) radius: 999.0
  static const double radiusCircular = 999.0;

  // ══════════════════════════════════════════════════════════════════════════
  // Icon Sizes
  // ══════════════════════════════════════════════════════════════════════════
  
  /// Extra small icon size: 16.0
  static const double iconXs = 16.0;
  
  /// Small icon size: 20.0
  static const double iconSmall = 20.0;
  
  /// Medium icon size (default): 24.0
  static const double iconMedium = 24.0;
  
  /// Large icon size: 32.0
  static const double iconLarge = 32.0;
  
  /// Extra large icon size: 48.0
  static const double iconXl = 48.0;
  
  /// Extra extra large icon size: 64.0
  static const double iconXxl = 64.0;

  // ══════════════════════════════════════════════════════════════════════════
  // Component-Specific Dimensions
  // ══════════════════════════════════════════════════════════════════════════
  
  /// Standard button height: 48.0
  static const double buttonHeight = 48.0;
  
  /// Small button height: 36.0
  static const double buttonHeightSmall = 36.0;
  
  /// Large button height: 56.0
  static const double buttonHeightLarge = 56.0;
  
  /// Standard input field height: 48.0
  static const double inputHeight = 48.0;
  
  /// Card elevation: 2.0
  static const double cardElevation = 2.0;
  
  /// Bottom navigation bar height: 72.0
  static const double bottomNavHeight = 72.0;
  
  /// App bar height (standard Material height): 56.0
  static const double appBarHeight = 56.0;
  
  /// Avatar size small: 32.0
  static const double avatarSmall = 32.0;
  
  /// Avatar size medium: 48.0
  static const double avatarMedium = 48.0;
  
  /// Avatar size large: 64.0
  static const double avatarLarge = 64.0;
  
  /// Divider thickness: 1.0
  static const double dividerThickness = 1.0;
  
  /// Border width: 1.0
  static const double borderWidth = 1.0;
  
  /// Border width thick: 2.0
  static const double borderWidthThick = 2.0;

  // ══════════════════════════════════════════════════════════════════════════
  // Edge Insets Presets
  // ══════════════════════════════════════════════════════════════════════════
  
  /// All sides extra small padding
  static const EdgeInsets paddingAllXs = EdgeInsets.all(paddingXs);
  
  /// All sides small padding
  static const EdgeInsets paddingAllSmall = EdgeInsets.all(paddingSmall);
  
  /// All sides medium padding
  static const EdgeInsets paddingAllMedium = EdgeInsets.all(paddingMedium);
  
  /// All sides large padding
  static const EdgeInsets paddingAllLarge = EdgeInsets.all(paddingLarge);
  
  /// All sides extra large padding
  static const EdgeInsets paddingAllXl = EdgeInsets.all(paddingXl);
  
  /// Horizontal small padding
  static const EdgeInsets paddingHorizontalSmall = EdgeInsets.symmetric(horizontal: paddingSmall);
  
  /// Horizontal medium padding
  static const EdgeInsets paddingHorizontalMedium = EdgeInsets.symmetric(horizontal: paddingMedium);
  
  /// Horizontal large padding
  static const EdgeInsets paddingHorizontalLarge = EdgeInsets.symmetric(horizontal: paddingLarge);
  
  /// Vertical small padding
  static const EdgeInsets paddingVerticalSmall = EdgeInsets.symmetric(vertical: paddingSmall);
  
  /// Vertical medium padding
  static const EdgeInsets paddingVerticalMedium = EdgeInsets.symmetric(vertical: paddingMedium);
  
  /// Vertical large padding
  static const EdgeInsets paddingVerticalLarge = EdgeInsets.symmetric(vertical: paddingLarge);

  // ══════════════════════════════════════════════════════════════════════════
  // Border Radius Presets
  // ══════════════════════════════════════════════════════════════════════════
  
  /// Small border radius preset
  static final BorderRadius borderRadiusSmall = BorderRadius.circular(radiusSmall);
  
  /// Medium border radius preset
  static final BorderRadius borderRadiusMedium = BorderRadius.circular(radiusMedium);
  
  /// Large border radius preset
  static final BorderRadius borderRadiusLarge = BorderRadius.circular(radiusLarge);
  
  /// Extra large border radius preset
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  
  /// Extra extra large border radius preset
  static final BorderRadius borderRadiusXxl = BorderRadius.circular(radiusXxl);
  
  /// Circular border radius preset
  static final BorderRadius borderRadiusCircular = BorderRadius.circular(radiusCircular);
}
