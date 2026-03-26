import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../models/bill.dart';
import '../models/planner_item.dart';
import '../services/bill_service.dart';
import '../services/family_planner_service.dart';
import '../services/investment_service.dart';
import '../services/ai_service.dart';
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
  final BudgetService _budgetService = BudgetService();
  final InvestmentService _investmentService = InvestmentService();
  final BillService _billService = BillService();
  final FamilyPlannerService _plannerService = FamilyPlannerService();

  List<Expense> _allExpenses = [];
  List<Expense> _recentExpenses = [];
  List<Budget> _budgets = [];
  List<Investment> _investments = [];
  List<Bill> _upcomingBills = [];
  List<PlannerItem> _upcomingEvents = [];
  double _totalBalance = 0.0;
  double _percentageChange = 0.0;
  bool _isLoading = true;
  bool _isFetching = false;
  String? _error;

  // AI Forecast
  bool _aiForecastLoading = false;
  String? _aiForecastProjection;
  String? _aiForecastError;

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

      // Fetch all expenses once and derive slices for each card.
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
      );
      final sortedExpenses = [...expenses]
        ..sort((a, b) => b.date.compareTo(a.date));
      final recentExpenses = sortedExpenses.take(10).toList();

      // Try to fetch expense stats, but fallback to calculation if endpoint doesn't exist
      double totalBalance = 0.0;
      double percentageChange = 0.0;
      List<Budget> budgets = [];

      try {
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        budgets = await _budgetService.getBudgets(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
          month: month,
        );
      } catch (budgetError) {
        debugPrint('Budget endpoint not available for dashboard: $budgetError');
      }

      List<Investment> investments = [];
      try {
        investments = await _investmentService.getInvestments(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (investmentError) {
        debugPrint('Investment endpoint not available for dashboard: $investmentError');
      }

      List<Bill> bills = [];
      try {
        final allBills = await _billService.getBills(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        bills = allBills.where((b) => b.isUpcoming).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      } catch (billError) {
        debugPrint('Bill endpoint not available for dashboard: $billError');
      }

      List<PlannerItem> events = [];
      try {
        final allItems = await _plannerService.getItems(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        events = allItems.where((e) => e.isUpcoming).toList()
          ..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
      } catch (plannerError) {
        debugPrint('Family planner endpoint not available for dashboard: $plannerError');
      }

      try {
        final stats = await _expenseService.getExpenseStats(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        totalBalance = (stats['total_balance'] as num?)?.toDouble() ?? 0.0;
        percentageChange =
            (stats['percentage_change'] as num?)?.toDouble() ?? 0.0;
      } catch (statsError) {
        // Stats endpoint not available — compute balance from the already-fetched
        // expenses list instead of making a second redundant API call.
        debugPrint(
            'Stats endpoint not available, calculating from expenses: $statsError');

        for (final expense in expenses) {
          final isIncome = expense.category.toLowerCase() == 'income' ||
              expense.category.toLowerCase() == 'salary';
          totalBalance += isIncome ? expense.amount : -expense.amount;
        }

        percentageChange = 0.0;
      }

      setState(() {
        _allExpenses = sortedExpenses;
        _recentExpenses = recentExpenses;
        _budgets = budgets;
        _investments = investments;
        _upcomingBills = bills;
        _upcomingEvents = events;
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
    final formatted = abs.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '₹$formatted';
  }

  // ── Computed helpers ───────────────────────────────────────────────────────

  double get _monthlySpend {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Map<String, double> get _categoryTotals {
    final now = DateTime.now();
    final totals = <String, double>{};
    for (final e in _allExpenses) {
      if (e.date.year == now.year &&
          e.date.month == now.month &&
          e.category.toLowerCase() != 'income' &&
          e.category.toLowerCase() != 'salary') {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
    }
    return totals;
  }

  double get _monthlyIncome {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            (e.category.toLowerCase() == 'income' ||
                e.category.toLowerCase() == 'salary'))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get _monthlyBudgetTotal =>
      _budgets.fold(0.0, (sum, budget) => sum + budget.amount);

  double get _monthlyBudgetSpent =>
      _budgets.fold(0.0, (sum, budget) => sum + budget.spent);

  double get _savingsRate {
    if (_monthlyIncome <= 0) return 0;
    return ((_monthlyIncome - _monthlySpend) / _monthlyIncome) * 100;
  }

  double get _emergencyFundMonths {
    if (_monthlySpend <= 0) return 0;
    final months = _totalBalance / _monthlySpend;
    return months < 0 ? 0 : months;
  }

  int get _budgetRiskCount {
    return _budgets.where((budget) => budget.usagePercent >= 90).length;
  }

  double get _totalInvestedValue =>
      _investments.fold(0.0, (sum, inv) => sum + inv.currentValue);

  bool get _hasCoreExpenseData {
    return _allExpenses.any((e) {
      final category = e.category.toLowerCase();
      return category != 'income' && category != 'salary';
    });
  }

  double get _forecastBudget {
    if (_monthlyBudgetTotal > 0) return _monthlyBudgetTotal * 1.08;
    if (_monthlySpend > 0) return _monthlySpend * 1.15;
    return 0;
  }

  double get _forecastExpenses {
    if (_monthlySpend > 0) return _monthlySpend * 1.05;
    return 0;
  }

  Future<void> _loadAIForecast() async {
    setState(() {
      _aiForecastLoading = true;
      _aiForecastError = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().runFinancialSimulation(
        monthlyIncome: _monthlyBudgetTotal > 0 ? _monthlyBudgetTotal : _monthlySpend * 1.2,
        monthlyExpenses: _monthlySpend,
        monthlySavings: (_monthlyBudgetTotal - _monthlySpend).clamp(0, double.infinity),
        scenarioMonths: 3,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _aiForecastProjection = result['projection'] as String?;
        _aiForecastLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiForecastLoading = false;
        _aiForecastError = e.toString();
      });
    }
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
                                    QuickAction(
                                      label: 'Investments',
                                      icon: Icons.query_stats,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/investments');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Planner',
                                      icon: Icons.event_note_outlined,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/family-planner');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Kids',
                                      icon: Icons.child_care_outlined,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/kids-dashboard');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Parents',
                                      icon: Icons.family_restroom_outlined,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/parents-dashboard');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Assets',
                                      icon: Icons.account_balance_outlined,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/assets');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Key Contacts',
                                      icon: Icons.contacts_outlined,
                                      onTap: () {
                                        Navigator.of(context)
                                            .pushNamed('/key-contacts');
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

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildWebError(context)
              : Row(
                  children: [
                    _buildSidebar(context, isDark, theme),
                    Expanded(
                      child: _buildWebContent(context, isDark, theme),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isDark, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.grey800 : const Color(0xFFE2E8F0);

    final navItems = [
      _DashNavItem(
          label: 'Dashboard',
          icon: Icons.grid_view_rounded,
          route: '/home',
          active: true,
          connected: true),
      _DashNavItem(
        label: 'Family Planner',
        icon: Icons.event_note_outlined,
        route: '/family-planner',
        active: false,
        connected: true),
      _DashNavItem(
        label: 'Kids Dashboard',
        icon: Icons.child_care_outlined,
        route: '/kids-dashboard',
        active: false,
        connected: true),
      _DashNavItem(
        label: 'Parents Dashboard',
        icon: Icons.family_restroom_outlined,
        route: '/parents-dashboard',
        active: false,
        connected: true),
      _DashNavItem(
          label: 'Transactions',
          icon: Icons.receipt_long_outlined,
          route: '/expenses',
          active: false,
          connected: true),
      _DashNavItem(
          label: 'Budgets',
          icon: Icons.savings_outlined,
          route: '/budget',
          active: false,
          connected: true),
      _DashNavItem(
          label: 'Accounts',
          icon: Icons.account_balance_outlined,
          route: '',
          active: false,
          connected: false),
      _DashNavItem(
          label: 'Investments',
          icon: Icons.query_stats,
          route: '/investments',
          active: false,
          connected: true),
      _DashNavItem(
          label: 'Assets',
          icon: Icons.account_balance_outlined,
          route: '/assets',
          active: false,
          connected: true),
      _DashNavItem(
          label: 'Key Contacts',
          icon: Icons.contacts_outlined,
          route: '/key-contacts',
          active: false,
          connected: true),
      _DashNavItem(
          label: 'Reports',
          icon: Icons.description_outlined,
          route: '',
          active: false,
          connected: false),
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

  Widget _buildSidebarNavItem(
      BuildContext context, _DashNavItem item, Color primary, bool isDark) {
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
                  child: Icon(Icons.close_rounded, size: 13, color: Colors.red),
                ),
            ],
          ),
        ),
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

  Widget _buildWebContent(BuildContext context, bool isDark, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHomeOverviewRow(isDark, primary),
            const SizedBox(height: 32),
            _buildForecastSection(isDark),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSpendingSpotlightCard(isDark, primary)),
                const SizedBox(width: 24),
                Expanded(child: _buildUpcomingBillsCard(isDark)),
              ],
            ),
            const SizedBox(height: 32),
            _buildImportantDatesCard(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeOverviewRow(bool isDark, Color primary) {
    final budgetUsage = _monthlyBudgetTotal > 0
        ? (_monthlyBudgetSpent / _monthlyBudgetTotal).clamp(0.0, 1.0)
        : 0.0;
    final budgetStatus = _monthlyBudgetTotal <= 0
        ? 'Not Set'
        : budgetUsage >= 1
            ? 'At Risk'
            : 'On Track';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildHomeCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Health',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                const SizedBox(height: 8),
                _buildHealthMetricRow(
                  'Savings Rate',
                  '${_savingsRate.toStringAsFixed(0)}%',
                  _savingsRate >= 20 ? 'Good' : 'Improve',
                  _savingsRate >= 20
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFEDD5),
                  _savingsRate >= 20
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFEA580C),
                ),
                const SizedBox(height: 6),
                _buildHealthMetricRow(
                  'Emergency Fund',
                  '${_emergencyFundMonths.toStringAsFixed(1)}m',
                  _emergencyFundMonths >= 6 ? 'Strong' : 'Improve',
                  _emergencyFundMonths >= 6
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFEDD5),
                  _emergencyFundMonths >= 6
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFEA580C),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? AppColors.grey800
                            : const Color(0xFFF1F5F9),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Budget Risk',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          Text(
                            _budgets.isEmpty
                                ? 'Budget sync pending'
                                : '$_budgetRiskCount categories over',
                            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                      Text(
                        _budgetRiskCount > 0 ? 'High' : 'Low',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _budgetRiskCount > 0
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildHomeCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Spending',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatCurrency(_monthlySpend),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: budgetUsage,
                    minHeight: 7,
                    backgroundColor:
                        isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _monthlyBudgetTotal > 0
                      ? '${(budgetUsage * 100).toStringAsFixed(0)}% of your monthly budget used'
                      : 'Monthly budget not configured yet',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildHomeCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Budget Current Month',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ),
                    if (_monthlyBudgetTotal <= 0) _comingSoonBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _monthlyBudgetTotal > 0
                          ? _formatCurrency(_monthlyBudgetTotal)
                          : '—',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _monthlyBudgetTotal > 0 ? '(Budgeted)' : 'Coming soon',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: budgetUsage,
                    minHeight: 7,
                    backgroundColor:
                        isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                    color: primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _monthlyBudgetTotal > 0
                          ? 'Spent ${_formatCurrency(_monthlyBudgetSpent)} (${(budgetUsage * 100).toStringAsFixed(0)}%)'
                          : 'Budget backend not connected',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        budgetStatus,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: budgetStatus == 'At Risk'
                              ? AppColors.error
                              : primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForecastSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'AI Forecasted - ${_monthAbbr((DateTime.now().month % 12) + 1)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'BETA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
            const Spacer(),
            if (_aiForecastLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.icon(
                onPressed: _loadAIForecast,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(_aiForecastProjection != null ? 'Refresh' : 'Analyze with AI'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _buildForecastCard(
                colors: const [Color(0xFFFFFFFF), Color(0xFFEEF2FF)],
                borderColor: const Color(0xFFC7D2FE),
                accent: const Color(0xFF4F46E5),
                title: 'Forecasted Budget',
                value: _forecastBudget > 0
                    ? _formatCurrency(_forecastBudget)
                    : '—',
                message: _forecastBudget > 0
                    ? 'Estimated from your current budget setup and recent spending trend.'
                    : 'Budget forecasting unlocks once monthly budgets are configured.',
                icon: Icons.auto_awesome,
                showComingSoon: _forecastBudget <= 0,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildForecastCard(
                colors: const [Color(0xFFFFFFFF), Color(0xFFF5F3FF)],
                borderColor: const Color(0xFFDDD6FE),
                accent: const Color(0xFF7C3AED),
                title: 'Forecasted Expenses',
                value: _forecastExpenses > 0
                    ? _formatCurrency(_forecastExpenses)
                    : '—',
                message: _forecastExpenses > 0
                    ? 'Based on your recent approved expenses and current category mix.'
                    : 'We need more transaction history to estimate upcoming expenses.',
                icon: Icons.insights,
                showComingSoon: _forecastExpenses <= 0,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildForecastCard(
                colors: const [Color(0xFFFFFFFF), Color(0xFFECFDF5)],
                borderColor: const Color(0xFFA7F3D0),
                accent: const Color(0xFF059669),
                title: 'Forecasted Investments',
                value: _totalInvestedValue > 0
                    ? _formatCurrency(_totalInvestedValue)
                    : '—',
                message: _totalInvestedValue > 0
                    ? 'Total portfolio value based on your current investments.'
                    : 'Investment account sync is not connected yet for personalized forecasts.',
                icon: Icons.account_balance,
                showComingSoon: _totalInvestedValue <= 0,
              ),
            ),
          ],
        ),
        if (_aiForecastError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_aiForecastError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
        if (_aiForecastProjection != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF5F3FF), Color(0xFFEEF2FF)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 8),
                    const Text(
                      'AI Projection',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7C3AED)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(_aiForecastProjection!, style: const TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSpendingSpotlightCard(bool isDark, Color primary) {
    final totals = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grandTotal = totals.fold(0.0, (sum, item) => sum + item.value);
    final top = totals.take(4).toList();
    final dominant = top.isNotEmpty ? top.first : null;
    final dominantShare =
        dominant == null || grandTotal <= 0 ? 0.0 : dominant.value / grandTotal;
    final colors = [primary, Colors.orange, Colors.green, Colors.grey.shade400];

    return _buildHomeCard(
      isDark: isDark,
      child: SizedBox(
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Major Expense',
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[500])),
                      Text(
                        dominant == null
                            ? 'No data yet'
                            : _capitalize(dominant.key),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.pie_chart, color: Colors.grey[400], size: 18),
              ],
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(160, 160),
                          painter: _DonutPainter(
                            segments: top.asMap().entries.map((e) {
                              final share = grandTotal > 0
                                  ? e.value.value / grandTotal
                                  : 0.0;
                              return _DonutSegment(
                                share: share,
                                color: colors[e.key % colors.length],
                              );
                            }).toList(),
                            trackColor: isDark
                                ? AppColors.grey800
                                : const Color(0xFFF1F5F9),
                            strokeWidth: 18,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(dominantShare * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              dominant == null
                                  ? 'Waiting'
                                  : _capitalize(dominant.key),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    children: top.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return SizedBox(
                        width: 150,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colors[index % colors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _capitalize(item.key),
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[500]),
                                  ),
                                  Text(
                                    _formatCurrency(item.value),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingBillsCard(bool isDark) {
    return _buildHomeCard(
      isDark: isDark,
      child: SizedBox(
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upcoming Bills',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _upcomingBills.isEmpty
                  ? Column(
                      children: [
                        _buildUpcomingBillRow(
                          icon: Icons.credit_card,
                          iconBg: const Color(0xFFFEE2E2),
                          iconColor: const Color(0xFFDC2626),
                          title: 'Credit Card Sync',
                          subtitle: 'Auto-detected statement due dates',
                          amount: 'Coming soon',
                        ),
                        _buildUpcomingBillRow(
                          icon: Icons.bolt,
                          iconBg: const Color(0xFFDBEAFE),
                          iconColor: const Color(0xFF2563EB),
                          title: 'Utility Tracking',
                          subtitle: 'Electricity and recurring bills',
                          amount: 'Coming soon',
                        ),
                        _buildUpcomingBillRow(
                          icon: Icons.wifi,
                          iconBg: const Color(0xFFDCFCE7),
                          iconColor: const Color(0xFF16A34A),
                          title: 'Internet & Subscriptions',
                          subtitle: 'Recurring household expenses',
                          amount: 'Coming soon',
                          isLast: true,
                        ),
                      ],
                    )
                  : Column(
                      children: List.generate(
                        _upcomingBills.take(3).length,
                        (i) {
                          final bill = _upcomingBills[i];
                          final colors = _billCategoryColors(bill.category);
                          final days = bill.daysUntilDue;
                          final subtitle = bill.provider != null
                              ? '${bill.provider} • ${days == 0 ? 'due today' : 'due in ${days}d'}'
                              : (days == 0 ? 'Due today' : 'Due in ${days}d');
                          return _buildUpcomingBillRow(
                            icon: Bill.iconForCategory(bill.category),
                            iconBg: colors.$1,
                            iconColor: colors.$2,
                            title: bill.name,
                            subtitle: subtitle,
                            amount: _formatCurrency(bill.amount),
                            isLast: i == _upcomingBills.take(3).length - 1,
                            showComingSoon: false,
                          );
                        },
                      ),
                    ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).pushReplacementNamed('/bills'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.grey800 : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All Bills',
                        style:
                            TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 13),
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

  (Color, Color) _plannerTypeColors(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return (const Color(0xFFFCE7F3), const Color(0xFFDB2777));
      case PlannerItemType.anniversary:
        return (const Color(0xFFF3E8FF), const Color(0xFF9333EA));
      case PlannerItemType.vacation:
        return (const Color(0xFFDBEAFE), const Color(0xFF2563EB));
      case PlannerItemType.event:
        return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case PlannerItemType.reminder:
        return (const Color(0xFFFFEDD5), const Color(0xFFEA580C));
      case PlannerItemType.task:
        return (const Color(0xFFDCFCE7), const Color(0xFF16A34A));
    }
  }

  IconData _plannerTypeIcon(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return Icons.cake_outlined;
      case PlannerItemType.anniversary:
        return Icons.favorite;
      case PlannerItemType.vacation:
        return Icons.flight_takeoff_outlined;
      case PlannerItemType.event:
        return Icons.event_outlined;
      case PlannerItemType.reminder:
        return Icons.notifications_outlined;
      case PlannerItemType.task:
        return Icons.task_alt_outlined;
    }
  }

  String _plannerTypeLabel(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return 'Birthday';
      case PlannerItemType.anniversary:
        return 'Anniversary';
      case PlannerItemType.vacation:
        return 'Vacation';
      case PlannerItemType.event:
        return 'Event';
      case PlannerItemType.reminder:
        return 'Reminder';
      case PlannerItemType.task:
        return 'Task';
    }
  }

  Widget _buildImportantDatesCard(bool isDark) {
    final hasData = _upcomingEvents.isNotEmpty;
    final displayItems = _upcomingEvents.take(4).toList();

    // Placeholder tiles shown when no data is loaded yet
    final placeholders = [
      (Icons.cake_outlined, const Color(0xFFFCE7F3), const Color(0xFFDB2777), 'Birthdays'),
      (Icons.favorite, const Color(0xFFF3E8FF), const Color(0xFF9333EA), 'Anniversaries'),
      (Icons.volunteer_activism, const Color(0xFFFEE2E2), const Color(0xFFDC2626), 'Celebrations'),
      (Icons.celebration, const Color(0xFFFFEDD5), const Color(0xFFEA580C), 'Festivals'),
    ];

    return _buildHomeCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Upcoming Events',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pushNamed('/family-planner'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Text('View all', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.grey[500]),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: hasData
                ? displayItems.map((item) {
                    final colors = _plannerTypeColors(item.type);
                    final days = item.daysUntil;
                    final daysLabel = days == 0
                        ? 'Today'
                        : days == 1
                            ? 'Tomorrow'
                            : 'In ${days}d';
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).pushNamed('/family-planner'),
                      child: Container(
                        width: 230,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.grey800 : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.$1,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_plannerTypeIcon(item.type), color: colors.$2, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _plannerTypeLabel(item.type),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    daysLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: days == 0
                                          ? AppColors.error
                                          : days <= 7
                                              ? const Color(0xFFEA580C)
                                              : Colors.grey[500],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList()
                : placeholders.map((p) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).pushNamed('/family-planner'),
                      child: Container(
                        width: 230,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.grey800 : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: p.$2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(p.$1, color: p.$3, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.$4,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'No upcoming events',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeCard({
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _buildHealthMetricRow(
    String label,
    String value,
    String status,
    Color badgeBg,
    Color badgeFg,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        Row(
          children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.bold, color: badgeFg),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForecastCard({
    required List<Color> colors,
    required Color borderColor,
    required Color accent,
    required String title,
    required String value,
    required String message,
    required IconData icon,
    required bool showComingSoon,
    List<String> details = const [],
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: accent),
                    ),
                    if (showComingSoon) ...[
                      const SizedBox(width: 8),
                      _comingSoonBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(message,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600], height: 1.4)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...details.map((detail) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          detail,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  (Color, Color) _billCategoryColors(BillCategory category) {
    switch (category) {
      case BillCategory.rent:
        return (const Color(0xFFDBEAFE), const Color(0xFF2563EB));
      case BillCategory.utilities:
        return (const Color(0xFFFFF7ED), const Color(0xFFEA580C));
      case BillCategory.internet:
        return (const Color(0xFFDCFCE7), const Color(0xFF16A34A));
      case BillCategory.insurance:
        return (const Color(0xFFDCFCE7), const Color(0xFF059669));
      case BillCategory.creditCard:
        return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case BillCategory.subscription:
        return (const Color(0xFFEDE9FE), const Color(0xFF7C3AED));
      case BillCategory.loan:
        return (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
      case BillCategory.school:
        return (const Color(0xFFFEF9C3), const Color(0xFFCA8A04));
      case BillCategory.other:
        return (const Color(0xFFF1F5F9), const Color(0xFF64748B));
    }
  }

  Widget _buildUpcomingBillRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String amount,
    bool isLast = false,
    bool showComingSoon = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
          Text(amount,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          if (showComingSoon) ...[
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded, size: 12, color: Colors.red),
          ],
        ],
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
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[700])),
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
                    backgroundColor:
                        isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
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
    final rowBorder =
        BorderSide(color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9));

    return Column(children: [
      // Header row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: rowBorder)),
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
            decoration: BoxDecoration(border: Border(bottom: rowBorder)),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: bgColor, borderRadius: BorderRadius.circular(8)),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
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

// ── Multi-color donut chart painter ───────────────────────────────────────

class _DonutSegment {
  final double share; // 0.0 - 1.0
  final Color color;

  const _DonutSegment({required this.share, required this.color});
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final Color trackColor;
  final double strokeWidth;

  const _DonutPainter({
    required this.segments,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const gapDeg = 2.5;
    const startOffsetDeg = -90.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, radius, trackPaint);

    if (segments.isEmpty) return;

    final totalShare = segments.fold(0.0, (sum, seg) => sum + seg.share);
    if (totalShare <= 0) return;

    double currentAngle = startOffsetDeg;
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    for (final seg in segments) {
      if (seg.share <= 0) continue;
      final sweepDeg = (seg.share / totalShare) * 360.0 - gapDeg;
      if (sweepDeg <= 0) continue;

      paint.color = seg.color;
      canvas.drawArc(
        rect,
        _toRad(currentAngle),
        _toRad(sweepDeg),
        false,
        paint,
      );
      currentAngle += sweepDeg + gapDeg;
    }
  }

  double _toRad(double deg) => deg * 3.141592653589793 / 180.0;

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
