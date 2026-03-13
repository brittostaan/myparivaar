import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Navigation item for the bottom navigation bar
class NavItem {
  final String label;
  final IconData icon;
  final IconData? filledIcon;

  const NavItem({
    required this.label,
    required this.icon,
    this.filledIcon,
  });
}

/// A custom bottom navigation bar widget for the app
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final List<NavItem> items;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? AppColors.grey900.withOpacity(0.8)
            : AppColors.surfaceLight.withOpacity(0.8),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.grey800 : AppColors.grey200,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = currentIndex == index;
              
              return Expanded(
                child: InkWell(
                  onTap: () => onTabChanged(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected 
                              ? (item.filledIcon ?? item.icon) 
                              : item.icon,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : (isDark ? AppColors.grey600 : AppColors.grey400),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : (isDark ? AppColors.grey600 : AppColors.grey400),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
