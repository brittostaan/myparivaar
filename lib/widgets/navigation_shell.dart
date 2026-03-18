import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../config/navigation_config.dart';
import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
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

  /// Whether the shared web top section should be shown.
  final bool showWebTopBar;

  const NavigationShell({
    super.key,
    required this.child,
    required this.currentRoute,
    this.showWebTopBar = true,
  });

  static bool webSidebarVisible = true;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Expense> _allExpenses = [];
  List<Expense> _searchResults = [];
  bool _isSearchLoading = false;
  bool _isSearchLoaded = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchQueryChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      NavigationShell.webSidebarVisible = !NavigationShell.webSidebarVisible;
    });
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_searchFocusNode.hasFocus) {
      _ensureSearchDataLoaded();
    }
  }

  Future<void> _ensureSearchDataLoaded() async {
    if (_isSearchLoaded || _isSearchLoading) return;

    setState(() {
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final authService = context.read<AuthService>();
      final idToken = await authService.getIdToken();
      final expenses = await ExpenseService().getExpenses(
        supabaseUrl: authService.supabaseUrl,
        idToken: idToken,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _allExpenses = expenses;
        _isSearchLoaded = true;
        _isSearchLoading = false;
      });
      _onSearchQueryChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Failed to load transactions';
        _isSearchLoading = false;
      });
    }
  }

  void _onSearchQueryChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      if (_searchResults.isNotEmpty) {
        setState(() => _searchResults = []);
      }
      return;
    }

    final filtered = _allExpenses.where((e) {
      return e.description.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.amount.toStringAsFixed(2).contains(q);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _searchResults = filtered;
    });
  }

  void _onSearchResultTap(Expense expense) {
    _searchController.text = expense.description;
    _searchFocusNode.unfocus();
    Navigator.of(context).pushReplacementNamed('/expenses');
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & dining':
        return Icons.restaurant_outlined;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'transport':
        return Icons.directions_car_outlined;
      case 'entertainment':
        return Icons.movie_outlined;
      case 'healthcare':
        return Icons.local_hospital_outlined;
      case 'utilities':
        return Icons.bolt_outlined;
      case 'rent':
      case 'housing':
        return Icons.home_outlined;
      case 'education':
        return Icons.school_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _buildInlineSearchDropdown() {
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          _searchError!,
          style: const TextStyle(color: Colors.red, fontSize: 13),
        ),
      );
    }

    if (_searchController.text.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 17, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Text(
              _isSearchLoading
                  ? 'Loading transactions...'
                  : 'Type to search across ${_allExpenses.length} transactions',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'No results for "${_searchController.text.trim()}"',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 54),
      itemBuilder: (context, i) {
        final expense = _searchResults[i];
        return ListTile(
          dense: true,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _categoryIcon(expense.category),
              size: 17,
              color: const Color(0xFF475569),
            ),
          ),
          title: Text(
            expense.description,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_capitalise(expense.category)}  ·  ${_formatDate(expense.date)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          trailing: Text(
            '₹${expense.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          onTap: () => _onSearchResultTap(expense),
        );
      },
    );
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
        label: 'Expense',
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
        label: 'Investments',
        icon: Icons.query_stats,
        route: '/investments',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Bills',
        icon: Icons.receipt_outlined,
        route: '/bills',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Reports',
        icon: Icons.description_outlined,
        route: '/reports',
        connected: true,
      ),
      _WebSidebarItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        route: '/user-settings',
        connected: true,
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

  Widget _buildWebTopBar(BuildContext context, bool showSidebar) {
    final theme = Theme.of(context);
    final authService = context.watch<AuthService>();
    final primary = theme.colorScheme.primary;
    final border = const Color(0xFFE2E8F0);
    final displayName = authService.currentUser?.displayName ??
        authService.currentUser?.email ??
        'User';
    final householdName = authService.currentHousehold?.name ?? 'My Family';
    final avatarLetter =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final shouldShowSearchDropdown = _searchFocusNode.hasFocus;
    final topBarHeight = shouldShowSearchDropdown ? 320.0 : 72.0;

    return Container(
      height: topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!showSidebar) ...[
            Material(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              child: IconButton(
                tooltip: 'Show navigation',
                onPressed: _toggleSidebar,
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[400], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onTap: _ensureSearchDataLoaded,
                          decoration: const InputDecoration(
                            hintText: 'Search transactions...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (_isSearchLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchQueryChanged();
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
                if (shouldShowSearchDropdown)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildInlineSearchDropdown(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () =>
                    Navigator.of(context).pushNamed('/notifications'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: border,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).pushNamed('/profile'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        householdName,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withOpacity(0.12),
                    child: Text(
                      avatarLetter,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
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
                child: Column(
                  children: [
                    if (widget.showWebTopBar)
                      _buildWebTopBar(context, showSidebar),
                    Expanded(child: widget.child),
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

