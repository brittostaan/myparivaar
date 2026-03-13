import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';

/// A centralized app header that appears at the top of all screens.
/// 
/// Shows:
/// - Avatar icon (left)
/// - Page title
/// - View mode selector (mobile/tablet/browser)
/// - Notifications button (right)
/// 
/// Usage:
/// ```dart
/// AppHeader(
///   title: 'Dashboard',
///   subtitle: 'Welcome back', // Optional
/// )
/// ```
class AppHeader extends StatelessWidget {
  /// Main title to display (e.g., "Dashboard", "Expenses", "Settings")
  final String title;
  
  /// Optional subtitle below the title
  final String? subtitle;
  
  /// Custom icon for the avatar (defaults to people icon)
  final IconData? avatarIcon;
  
  /// Whether to show the view mode selector (defaults to true)
  final bool showViewModeSelector;
  
  /// Whether to show the notifications button (defaults to true)
  final bool showNotifications;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarIcon,
    this.showViewModeSelector = true,
    this.showNotifications = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Profile Avatar
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushNamed('/profile');
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Icon(
                avatarIcon ?? AppIcons.people,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Title Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.grey400 : AppColors.grey600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          
          // View Mode Selector
          if (showViewModeSelector) const _ViewModeSelector(),
          
          // Settings Button
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/user-settings');
            },
            icon: Icon(
              AppIcons.settingsOutlined,
              color: isDark ? AppColors.grey300 : AppColors.grey600,
            ),
            tooltip: 'Settings',
          ),
          
          // Notifications Button
          if (showNotifications)
            IconButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/notifications');
              },
              icon: Icon(
                AppIcons.notificationsOutlined,
                color: isDark ? AppColors.grey300 : AppColors.grey600,
              ),
              tooltip: 'Notifications',
            ),
        ],
      ),
    );
  }
}

/// View mode selector widget for switching between mobile, tablet, and browser views
class _ViewModeSelector extends StatelessWidget {
  const _ViewModeSelector();

  @override
  Widget build(BuildContext context) {
    final viewModeProvider = context.watch<ViewModeProvider>();
    final currentMode = viewModeProvider.mode;

    return PopupMenuButton<ViewMode>(
      tooltip: 'View Mode',
      icon: Icon(currentMode.icon),
      onSelected: (mode) => viewModeProvider.setMode(mode),
      itemBuilder: (context) => ViewMode.values.map((mode) {
        return PopupMenuItem<ViewMode>(
          value: mode,
          child: Row(
            children: [
              Icon(
                mode.icon,
                color: mode == currentMode 
                    ? Theme.of(context).primaryColor 
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                mode.label,
                style: TextStyle(
                  fontWeight: mode == currentMode 
                      ? FontWeight.bold 
                      : FontWeight.normal,
                  color: mode == currentMode 
                      ? Theme.of(context).primaryColor 
                      : null,
                ),
              ),
              if (mode == currentMode) ...[
                const Spacer(),
                Icon(
                  AppIcons.check,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
