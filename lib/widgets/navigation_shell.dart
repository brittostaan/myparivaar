import 'package:flutter/material.dart';
import '../config/navigation_config.dart';
import 'app_bottom_navigation_bar.dart';

/// A shell widget that wraps screens with bottom navigation.
/// 
/// This widget automatically:
/// - Queries NavigationConfig to get nav items for the current route
/// - Shows bottom navigation if configured for this route
/// - Highlights the active tab based on current route
/// - Handles navigation when tabs are tapped
/// 
/// Usage: Wrap any screen with this widget in route generation
class NavigationShell extends StatelessWidget {
  /// The screen content to display above the navigation bar
  final Widget child;
  
  /// The current route name (e.g., '/home', '/expenses')
  final String currentRoute;

  const NavigationShell({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    // Get navigation items for the current route
    final navItems = NavigationConfig.getNavigationItems(currentRoute);
    
    // If no navigation items configured, show child without navigation
    if (navItems == null || navItems.isEmpty) {
      return child;
    }

    // Find the index of the current route in navigation items
    int currentIndex = 0;
    for (int i = 0; i < navItems.length; i++) {
      if (navItems[i].routeName == currentRoute) {
        currentIndex = i;
        break;
      }
    }

    // Convert NavigationItem to NavItem for AppBottomNavigationBar
    final bottomNavItems = navItems.map((item) {
      return NavItem(
        label: item.label,
        icon: item.icon,
        filledIcon: item.filledIcon,
      );
    }).toList();

    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: currentIndex,
        items: bottomNavItems,
        onTabChanged: (index) {
          final targetRoute = navItems[index].routeName;
          
          // Don't navigate if already on that route
          if (targetRoute == currentRoute) {
            return;
          }
          
          // Navigate to the selected route
          Navigator.of(context).pushNamed(targetRoute);
        },
      ),
    );
  }
}
