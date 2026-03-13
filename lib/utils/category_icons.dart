import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Utility class for mapping expense categories to colors and icons
class CategoryIcons {
  /// Get the background color for a category (lighter shade)
  static Color getCategoryColor(String category) {
    return AppColors.getCategoryColor(category);
  }

  /// Get the icon color for a category (darker shade)
  static Color getCategoryIconColor(String category) {
    return AppColors.getCategoryIconColor(category);
  }

  /// Get the icon for a category
  static IconData getCategoryIcon(String category) {
    return AppIcons.getCategoryIcon(category);
  }
}
