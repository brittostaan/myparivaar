import 'package:flutter/material.dart';
import '../theme/app_icons.dart';

/// Represents a single navigation item in the bottom navigation bar
class NavigationItem {
  /// Display label for the navigation item
  final String label;
  
  /// Icon to show when not selected
  final IconData icon;
  
  /// Icon to show when selected (optional, falls back to [icon])
  final IconData? filledIcon;
  
  /// Route name to navigate to when tapped
  final String routeName;

  const NavigationItem({
    required this.label,
    required this.icon,
    required this.routeName,
    this.filledIcon,
  });
}

/// Central configuration defining which navigation items appear on each screen.
/// 
/// **How to use:**
/// 1. Define navigation items for your route in the map below
/// 2. The NavigationShell will automatically show them on that screen
/// 3. When user taps an item, they navigate to its routeName
/// 
/// **Example:**
/// ```dart
/// '/my-new-screen': [
///   NavigationItem(
///     label: 'Home',
///     icon: AppIcons.home,
///     filledIcon: AppIcons.homeFilled,
///     routeName: '/home',
///   ),
///   NavigationItem(
///     label: 'Settings',
///     icon: AppIcons.settings,
///     routeName: '/user-settings',
///   ),
/// ],
/// ```
class NavigationConfig {
  /// Map of route names to their bottom navigation items.
  /// Screens not in this map will not show bottom navigation.
  static final Map<String, List<NavigationItem>> _routeNavigationMap = {
    // Main dashboard screens - standard navigation
    '/home': _mainNavigation,
    '/expenses': _mainNavigation,
    '/budget': _mainNavigation,
    '/investments': _mainNavigation,
    '/bills': _mainNavigation,
    '/reports': _mainNavigation,
    '/family-planner': _mainNavigation,
    '/kids-dashboard': _mainNavigation,
    '/parents-dashboard': _mainNavigation,
    '/ai': _mainNavigation,
    '/user-settings': _mainNavigation,
    '/more': _mainNavigation,
    '/family': _mainNavigation,
    '/admin-settings': _mainNavigation,
    '/email-settings': _mainNavigation,
    '/notifications': _mainNavigation,
    '/csv-import': _mainNavigation,
    '/savings': _mainNavigation,
  };

  /// Standard navigation shown on main screens
  static final List<NavigationItem> _mainNavigation = [
    const NavigationItem(
      label: 'Home',
      icon: AppIcons.homeOutlined,
      filledIcon: AppIcons.home,
      routeName: '/home',
    ),
    const NavigationItem(
      label: 'Voice',
      icon: AppIcons.micOutlined,
      filledIcon: AppIcons.mic,
      routeName: '', // intentionally unconnected
    ),
    const NavigationItem(
      label: 'More',
      icon: Icons.more_horiz,
      routeName: '/more',
    ),
  ];

  /// Get navigation items for a specific route.
  /// Returns null if the route should not show bottom navigation.
  static List<NavigationItem>? getNavigationItems(String? routeName) {
    if (routeName == null) return null;
    return _routeNavigationMap[routeName];
  }

  /// Check if a route should show bottom navigation
  static bool shouldShowNavigation(String? routeName) {
    return getNavigationItems(routeName) != null;
  }
}
