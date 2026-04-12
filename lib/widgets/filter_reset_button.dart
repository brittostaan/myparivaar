import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Standardized filter reset/clear button used across all screens.
///
/// Displays a subtle "Clear filters" button when filters are active.
/// Consistent styling ensures a unified look across Budget, Expenses,
/// Reports, and other filterable screens.
class FilterResetButton extends StatelessWidget {
  const FilterResetButton({
    super.key,
    required this.onReset,
    this.label = 'Clear filters',
    this.isVisible = true,
  });

  /// Callback when the reset button is tapped
  final VoidCallback onReset;

  /// Button label text
  final String label;

  /// Whether to show the button (typically tied to hasActiveFilters)
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextButton.icon(
      onPressed: onReset,
      icon: Icon(
        Icons.filter_alt_off_outlined,
        size: 16,
        color: isDark ? AppColors.error.withOpacity(0.8) : AppColors.error,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.error.withOpacity(0.8) : AppColors.error,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppColors.error.withOpacity(0.2),
          ),
        ),
        backgroundColor: AppColors.error.withOpacity(0.05),
      ),
    );
  }
}
