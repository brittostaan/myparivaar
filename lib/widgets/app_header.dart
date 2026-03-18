import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import 'global_header_actions.dart';

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
          
          // Global actions (View Mode + Logout)
          if (showViewModeSelector)
            const GlobalHeaderActions(
              showLogout: true,
            ),
          
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
