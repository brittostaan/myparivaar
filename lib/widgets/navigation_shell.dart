import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
class NavigationShell extends StatefulWidget {
  /// The screen content to display above the navigation bar
  final Widget child;
  
  /// The current route name (e.g., '/home', '/expenses')
  final String currentRoute;

  const NavigationShell({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  static bool webSidebarVisible = true;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  void _toggleSidebar() {
    setState(() {
      NavigationShell.webSidebarVisible = !NavigationShell.webSidebarVisible;
    });
  }

  List<_WebSidebarItem> _webSidebarItems() {
    return [
      _WebSidebarItem(
        label: 'Dashboard',
        icon: Icons.grid_view_rounded,
        route: '/home',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Transactions',
        icon: Icons.receipt_long_outlined,
        route: '/expenses',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Budgets',
        icon: Icons.savings_outlined,
        route: '/budget',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Accounts',
        icon: Icons.account_balance_outlined,
        route: '',
        connected: false,
      ),
      _WebSidebarItem(
        label: 'Investments',
        icon: Icons.query_stats,
        route: '',
        connected: false,
      ),
      _WebSidebarItem(
        label: 'Reports',
        icon: Icons.description_outlined,
        route: '',
        connected: false,
      ),
    ];
  }

  Widget _buildWebSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'myparivaar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Finance',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hide navigation',
                  onPressed: _toggleSidebar,
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: _webSidebarItems().map((item) {
                final isActive = item.route == widget.currentRoute;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: item.connected && item.route.isNotEmpty
                        ? () {
                            if (item.route != widget.currentRoute) {
                              Navigator.of(context)
                                  .pushReplacementNamed(item.route);
                            }
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 20,
                            color: isActive ? primary : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isActive
                                    ? primary
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          if (!item.connected)
                            const Tooltip(
                              message: 'Feature coming soon',
                              child: Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pro Plan',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Upgrade for more features',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final showSidebar = NavigationShell.webSidebarVisible;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: showSidebar ? 256 : 0,
                child: showSidebar ? _buildWebSidebar(context) : null,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: widget.child),
                    if (!showSidebar)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Material(
                          color: Colors.white,
                          elevation: 1,
                          borderRadius: BorderRadius.circular(10),
                          child: IconButton(
                            tooltip: 'Show navigation',
                            onPressed: _toggleSidebar,
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Get navigation items for the current route
    final navItems = NavigationConfig.getNavigationItems(widget.currentRoute);
    
    // If no navigation items configured, show child without navigation
    if (navItems == null || navItems.isEmpty) {
      return widget.child;
    }

    // Find the index of the current route in navigation items
    int currentIndex = 0;
    for (int i = 0; i < navItems.length; i++) {
      if (navItems[i].routeName == widget.currentRoute) {
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
      body: widget.child,
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: currentIndex,
        items: bottomNavItems,
        onTabChanged: (index) {
          final targetRoute = navItems[index].routeName;
          
          // Empty routeName means the tab is intentionally unconnected
          if (targetRoute.isEmpty) return;

          // Don't navigate if already on that route
          if (targetRoute == widget.currentRoute) {
            return;
          }
          
          // Replace current route so tabs don't stack up the back history
          Navigator.of(context).pushReplacementNamed(targetRoute);
        },
      ),
    );
  }
}

class _WebSidebarItem {
  final String label;
  final IconData icon;
  final String route;
  final bool connected;

  const _WebSidebarItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.connected,
  });
}
