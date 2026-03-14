import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import '../widgets/balance_card.dart';
import '../widgets/quick_actions_grid.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/app_header.dart';
import '../theme/app_icons.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
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
        // If stats endpoint doesn't exist, calculate from expenses
        debugPrint('Stats endpoint not available, calculating from expenses: $statsError');
        
        // Fetch all expenses to calculate total
        final allExpenses = await _expenseService.getExpenses(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        
        // Calculate total (income as positive, expenses as negative)
        for (final expense in allExpenses) {
          final isIncome = expense.category.toLowerCase() == 'income' ||
              expense.category.toLowerCase() == 'salary';
          totalBalance += isIncome ? expense.amount : -expense.amount;
        }
        
        // For now, set percentage change to 0 if we can't calculate it
        percentageChange = 0.0;
      }

      setState(() {
        _recentExpenses = expenses;
        _totalBalance = totalBalance;
        _percentageChange = percentageChange;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
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
                                    Navigator.of(context).pushNamed('/expenses');
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
                                        Navigator.of(context).pushNamed('/expenses');
                                      },
                                    ),
                                    QuickAction(
                                      label: 'Budget',
                                      icon: AppIcons.pieChart,
                                      onTap: () {
                                        Navigator.of(context).pushNamed('/budget');
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                
                                // Recent Activity
                                RecentActivityList(
                                  expenses: _recentExpenses,
                                  onSeeAll: () {
                                    Navigator.of(context).pushNamed('/expenses');
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
}
