import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import '../widgets/balance_card.dart';
import '../widgets/quick_actions_grid.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/app_header.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ExpenseService _expenseService = ExpenseService();
  
  List<Expense> _recentExpenses = [];
  double _totalBalance = 0.0;
  double _percentageChange = 0.0;
  bool _isLoading = true;
  bool _isFetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (_isFetching) return;
    _isFetching = true;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final supabaseUrl = authService.supabaseUrl;
      final idToken = await authService.getIdToken();

      // Fetch recent expenses (last 10)
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
        limit: 10,
      );

      // Try to fetch expense stats, but fallback to calculation if endpoint doesn't exist
      double totalBalance = 0.0;
      double percentageChange = 0.0;
      
      try {
        final stats = await _expenseService.getExpenseStats(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        totalBalance = (stats['total_balance'] as num?)?.toDouble() ?? 0.0;
        percentageChange = (stats['percentage_change'] as num?)?.toDouble() ?? 0.0;
      } catch (statsError) {
        // Stats endpoint not available — compute balance from the already-fetched
        // expenses list instead of making a second redundant API call.
        debugPrint('Stats endpoint not available, calculating from expenses: $statsError');

        for (final expense in expenses) {
          final isIncome = expense.category.toLowerCase() == 'income' ||
              expense.category.toLowerCase() == 'salary';
          totalBalance += isIncome ? expense.amount : -expense.amount;
        }

        percentageChange = 0.0;
      }

      setState(() {
        _recentExpenses = expenses;
        _totalBalance = totalBalance;
        _percentageChange = percentageChange;
        _isLoading = false;
        _isFetching = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isFetching = false;
      });
      debugPrint('Error loading dashboard data: $e');
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _formatCurrency(double amount) {
    final abs = amount.abs();
    final formatted = abs
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},');
    return '₹$formatted';
  }

  // ── Computed helpers ───────────────────────────────────────────────────────

  double get _monthlySpend {
    final now = DateTime.now();
    return _recentExpenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Map<String, double> get _categoryTotals {
    final totals = <String, double>{};
    for (final e in _recentExpenses) {
      if (e.category.toLowerCase() != 'income' &&
          e.category.toLowerCase() != 'salary') {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
    }
    return totals;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewMode = context.watch<ViewModeProvider>().mode;
    if (kIsWeb && viewMode == ViewMode.desktop) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  // ── Mobile Layout (original) ───────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final userName = authService.currentUser?.displayName ?? 'Family';
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            AppHeader(
              title: userName,
              subtitle: '${_getGreeting()},',
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  AppIcons.error,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load dashboard',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: _loadDashboardData,
                                  icon: const Icon(AppIcons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDashboardData,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Balance Card
                                BalanceCard(
                                  balance: _totalBalance,
                                  percentageChange: _percentageChange,
                                  onDeposit: null, // Hide for now
                                  onViewDetails: () {
                                    Navigator.of(context)
                                        .pushNamed('/expenses');
                                  },
                                ),
                                const SizedBox(height: 32),

                                // Quick Actions
                                QuickActionsGrid(
                                  actions: [
                                    QuickAction(
                                      label: 'Expense',
                                      icon: AppIcons.addCircle,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/expenses');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Budget',
                                      icon: AppIcons.pieChart,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/budget');
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),

                                // Recent Activity
                                RecentActivityList(
                                  expenses: _recentExpenses,
                                  onSeeAll: () {
                                    Navigator.of(context)
                                        .pushNamed('/expenses');
                                  },
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Web (Desktop) Layout ───────────────────────────────────────────────────

  Widget _buildWebLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authService = context.watch<AuthService>();

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: Row(
        children: [
          _buildSidebar(context, isDark, theme),
          Expanded(
            child: Column(
              children: [
                _buildWebHeader(context, isDark, theme, authService),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _buildWebError(context)
                          : _buildWebContent(
                              context, isDark, theme, authService),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
      BuildContext context, bool isDark, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final border =
        isDark ? AppColors.grey800 : const Color(0xFFE2E8F0);

    final navItems = [
      _DashNavItem(label: 'Dashboard', icon: Icons.grid_view_rounded,
          route: '/home', active: true, connected: true),
      _DashNavItem(label: 'Transactions', icon: Icons.receipt_long_outlined,
          route: '/expenses', active: false, connected: true),
      _DashNavItem(label: 'Budgets', icon: Icons.savings_outlined,
          route: '/budget', active: false, connected: true),
      _DashNavItem(label: 'Accounts', icon: Icons.account_balance_outlined,
          route: '', active: false, connected: false),
      _DashNavItem(label: 'Investments', icon: Icons.query_stats,
          route: '', active: false, connected: false),
      _DashNavItem(label: 'Reports', icon: Icons.description_outlined,
          route: '', active: false, connected: false),
    ];

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('myparivaar',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Finance',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: navItems
                    .map((item) =>
                        _buildSidebarNavItem(context, item, primary, isDark))
                    .toList(),
              ),
            ),
          ),
          // Pro plan card (coming soon)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Pro Plan',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: primary)),
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: 'Feature coming soon',
                              child: Icon(Icons.close_rounded,
                                  size: 12, color: Colors.red),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Upgrade for more features',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
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

  Widget _buildSidebarNavItem(BuildContext context, _DashNavItem item,
      Color primary, bool isDark) {
    final isActive = item.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: item.connected && item.route.isNotEmpty
            ? () {
                if (!isActive) {
                  Navigator.of(context).pushReplacementNamed(item.route);
                }
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 20,
                  color: isActive
                      ? primary
                      : (isDark ? AppColors.grey600 : Colors.grey[600])),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isActive
                          ? primary
                          : (isDark ? AppColors.grey600 : Colors.grey[700]),
                    )),
              ),
              if (!item.connected)
                const Tooltip(
                  message: 'Feature coming soon',
                  child: Icon(Icons.close_rounded,
                      size: 13, color: Colors.red),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebHeader(BuildContext context, bool isDark, ThemeData theme,
      AuthService authService) {
    final primary = theme.colorScheme.primary;
    final border =
        isDark ? AppColors.grey800 : const Color(0xFFE2E8F0);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Search (coming soon)
          Expanded(
            child: Tooltip(
              message: 'Feature coming soon',
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.grey800
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search,
                        color: Colors.grey[400], size: 18),
                    const SizedBox(width: 8),
                    Text('Search transactions...',
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Icons.close_rounded,
                        size: 11, color: Colors.red),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Scan & Pay (coming soon)
          Tooltip(
            message: 'Feature coming soon',
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.qr_code_scanner,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                const Text('Scan & Pay',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(width: 6),
                const Icon(Icons.close_rounded,
                    size: 11, color: Colors.white70),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Notifications
          Stack(children: [
            IconButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/notifications'),
              icon: Icon(Icons.notifications_outlined,
                  color: Colors.grey[600]),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
              ),
            ),
          ]),
          const SizedBox(width: 8),
          Container(
              height: 32,
              width: 1,
              color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
          const SizedBox(width: 12),
          // User
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/profile'),
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      authService.currentUser?.displayName ??
                          authService.currentUser?.email ??
                          'User',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      authService.currentHousehold?.name ?? 'My Household',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: primary.withOpacity(0.15),
                  child: Text(
                    ((authService.currentUser?.displayName?.isNotEmpty ==
                                true
                            ? authService.currentUser!.displayName![0]
                            : authService.currentUser?.email?.isNotEmpty ==
                                    true
                                ? authService.currentUser!.email![0]
                                : 'U'))
                        .toUpperCase(),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primary,
                        fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.error, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Failed to load dashboard',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadDashboardData,
            icon: const Icon(AppIcons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent(BuildContext context, bool isDark, ThemeData theme,
      AuthService authService) {
    final primary = theme.colorScheme.primary;
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Overview cards ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Net Worth (large primary card)
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -24,
                          bottom: -24,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Net Worth',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            Text(
                              _formatCurrency(_totalBalance),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _percentageChange >= 0
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_percentageChange >= 0 ? '+' : ''}${_percentageChange.toStringAsFixed(1)}% this month',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Monthly Spending
                Expanded(
                  child: _buildStatCard(
                    isDark: isDark,
                    label: 'Monthly Spending',
                    value: _formatCurrency(_monthlySpend),
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _monthlySpend > 0 ? 0.65 : 0,
                            backgroundColor: isDark
                                ? AppColors.grey800
                                : AppColors.grey200,
                            color: Colors.orange,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Current month',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Credit Score (coming soon)
                Expanded(
                  child: _buildStatCard(
                    isDark: isDark,
                    label: 'Credit Score',
                    value: '—',
                    badge: _comingSoonBadge(),
                    footer: Text('Feature coming soon',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // ── Row 2: Linked Accounts + Upcoming Bills ───────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildSectionCard(
                    isDark: isDark,
                    title: 'Linked Accounts',
                    trailing: _comingSoonBadge(),
                    child: _comingSoonPlaceholder(
                        Icons.account_balance_outlined,
                        'Bank account linking coming soon'),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildSectionCard(
                    isDark: isDark,
                    title: 'Upcoming Bills',
                    trailing: _comingSoonBadge(),
                    child: _comingSoonPlaceholder(
                        Icons.receipt_outlined, 'Bills tracking coming soon'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // ── Row 3: Investments + Category Breakdown ───────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSectionCard(
                    isDark: isDark,
                    title: 'Investments',
                    trailing: _comingSoonBadge(),
                    child: _comingSoonPlaceholder(
                        Icons.query_stats, 'Investment tracking coming soon'),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildSectionCard(
                    isDark: isDark,
                    title: 'Spending by Category',
                    child:
                        _buildCategoryBreakdown(context, isDark, primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // ── Recent Transactions ───────────────────────────────────────
            _buildSectionCard(
              isDark: isDark,
              title: 'Recent Transactions',
              trailing: TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/expenses'),
                child: const Text('View All',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              child: _buildTransactionsTable(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required String label,
    required String value,
    Widget? badge,
    Widget? footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500)),
              if (badge != null) badge,
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold)),
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                if (trailing != null) trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _comingSoonPlaceholder(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(
      BuildContext context, bool isDark, Color primary) {
    final totals = _categoryTotals;
    final grandTotal = totals.values.fold(0.0, (s, v) => s + v);

    if (totals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('No expense data yet',
            style: TextStyle(color: Colors.grey[400])),
      );
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();
    final colors = [primary, Colors.orange, Colors.green, Colors.red];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: top.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_capitalize(cat.key),
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700])),
                    Text(_formatCurrency(cat.value),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: grandTotal > 0 ? cat.value / grandTotal : 0,
                    backgroundColor: isDark
                        ? AppColors.grey800
                        : const Color(0xFFF1F5F9),
                    color: colors[i % colors.length],
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionsTable(BuildContext context, bool isDark) {
    if (_recentExpenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text('No transactions yet',
                style: TextStyle(color: Colors.grey[400]))),
      );
    }

    final headerStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.grey[400],
        letterSpacing: 0.5);
    final rowBorder = BorderSide(
        color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9));

    return Column(children: [
      // Header row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
            border: Border(bottom: rowBorder)),
        child: Row(children: [
          Expanded(flex: 3, child: Text('DESCRIPTION', style: headerStyle)),
          Expanded(child: Text('SOURCE', style: headerStyle)),
          Expanded(child: Text('CATEGORY', style: headerStyle)),
          Expanded(child: Text('DATE', style: headerStyle)),
          Expanded(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('AMOUNT', style: headerStyle))),
        ]),
      ),
      // Data rows
      ..._recentExpenses.map((expense) {
        final isIncome = expense.category.toLowerCase() == 'income' ||
            expense.category.toLowerCase() == 'salary';
        final bgColor = AppColors.getCategoryColor(expense.category);
        final iconColor = AppColors.getCategoryIconColor(expense.category);
        final d = expense.date;
        final dateStr = '${_monthAbbr(d.month)} ${d.day}, ${d.year}';
        return InkWell(
          onTap: () => Navigator.of(context).pushNamed('/expenses'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration:
                BoxDecoration(border: Border(bottom: rowBorder)),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(AppIcons.getCategoryIcon(expense.category),
                        size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(expense.description,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
              Expanded(
                  child: Text(expense.source.toUpperCase(),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500]))),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _capitalize(expense.category),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: iconColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                  child: Text(dateStr,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500]))),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${isIncome ? '+' : '-'}${_formatCurrency(expense.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isIncome ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _comingSoonBadge() => const Tooltip(
        message: 'Feature coming soon',
        child: Icon(Icons.close_rounded, size: 14, color: Colors.red),
      );

  String _capitalize(String cat) =>
      cat.isEmpty ? cat : cat[0].toUpperCase() + cat.substring(1).toLowerCase();

  String _monthAbbr(int month) {
    const abbrs = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return abbrs[(month - 1).clamp(0, 11)];
  }
}

// ── Helper data class for sidebar nav items ────────────────────────────────

class _DashNavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool active;
  final bool connected;

  const _DashNavItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.active,
    required this.connected,
  });
}
