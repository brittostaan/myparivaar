import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/bill.dart';
import '../models/planner_item.dart';
import '../models/savings_goal.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/bill_service.dart';
import '../services/family_planner_service.dart';
import '../services/investment_service.dart';
import '../services/savings_service.dart';
import '../services/ai_service.dart';
import '../widgets/balance_card.dart';
import '../widgets/quick_actions_grid.dart';
import '../widgets/recent_activity_list.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Family Financial Command Center â€” Unified Dashboard
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // â”€â”€ Services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final ExpenseService _expenseService = ExpenseService();
  final BudgetService _budgetService = BudgetService();
  final InvestmentService _investmentService = InvestmentService();
  final BillService _billService = BillService();
  final FamilyPlannerService _plannerService = FamilyPlannerService();
  final SavingsService _savingsService = SavingsService();

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<Expense> _allExpenses = [];
  List<Expense> _recentExpenses = [];
  List<Budget> _budgets = [];
  List<Investment> _investments = [];
  List<Bill> _allBills = [];
  List<Bill> _upcomingBills = [];
  List<PlannerItem> _allPlannerItems = [];
  List<PlannerItem> _upcomingEvents = [];
  List<SavingsGoal> _savingsGoals = [];
  double _totalBalance = 0.0;
  double _percentageChange = 0.0;
  bool _isLoading = true;
  bool _isFetching = false;
  String? _error;

  // AI Forecast
  bool _aiForecastLoading = false;
  String? _aiForecastProjection;
  String? _aiForecastError;

  // â”€â”€ Kids / Parents keyword constants (from kids & parents dashboards) â”€â”€â”€â”€â”€â”€
  static const List<String> _educationKeywords = [
    'school', 'fees', 'fee', 'tuition', 'books', 'book', 'stationary',
    'stationery', 'school van', 'uniform', 'exam', 'class', 'coaching',
  ];
  static const List<String> _kidMoneySentKeywords = [
    'sent', 'send', 'transfer', 'upi', 'allowance', 'pocket money', 'recharge',
  ];
  static const List<String> _parentKeywords = [
    'mom', 'mother', 'dad', 'father', 'amma', 'appa', 'mummy', 'papa', 'parent',
  ];
  static const List<String> _healthKeywords = [
    'health', 'checkup', 'doctor', 'hospital', 'clinic', 'medical', 'medicine',
    'lab', 'test', 'scan', 'dental', 'vision', 'eye', 'physio', 'surgery',
  ];
  static const List<String> _insuranceKeywords = [
    'insurance', 'mediclaim', 'policy', 'premium', 'renewal', 'coverage',
    'retirement', 'pension',
  ];

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

      // â”€â”€ Expenses â”€â”€
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
      );
      final sortedExpenses = [...expenses]
        ..sort((a, b) => b.date.compareTo(a.date));

      // â”€â”€ Budgets â”€â”€
      List<Budget> budgets = [];
      try {
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        budgets = await _budgetService.getBudgets(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
          month: month,
        );
      } catch (_) {}

      // â”€â”€ Investments â”€â”€
      List<Investment> investments = [];
      try {
        investments = await _investmentService.getInvestments(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // â”€â”€ Bills â”€â”€
      List<Bill> allBills = [];
      try {
        allBills = await _billService.getBills(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // â”€â”€ Planner â”€â”€
      List<PlannerItem> allPlannerItems = [];
      try {
        allPlannerItems = await _plannerService.getItems(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // â”€â”€ Savings Goals â”€â”€
      List<SavingsGoal> savingsGoals = [];
      try {
        savingsGoals = await _savingsService.getGoals(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // â”€â”€ Balance â”€â”€
      double totalBalance = 0.0;
      double percentageChange = 0.0;
      try {
        final stats = await _expenseService.getExpenseStats(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
        totalBalance = (stats['total_balance'] as num?)?.toDouble() ?? 0.0;
        percentageChange = (stats['percentage_change'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {
        for (final expense in expenses) {
          final isIncome = expense.category.toLowerCase() == 'income' ||
              expense.category.toLowerCase() == 'salary';
          totalBalance += isIncome ? expense.amount : -expense.amount;
        }
      }

      final upcomingBills = allBills.where((b) => b.isUpcoming).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      final upcomingEvents = allPlannerItems.where((e) => e.isUpcoming).toList()
        ..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

      if (!mounted) return;
      setState(() {
        _allExpenses = sortedExpenses;
        _recentExpenses = sortedExpenses.take(10).toList();
        _budgets = budgets;
        _investments = investments;
        _allBills = allBills;
        _upcomingBills = upcomingBills;
        _allPlannerItems = allPlannerItems;
        _upcomingEvents = upcomingEvents;
        _savingsGoals = savingsGoals;
        _totalBalance = totalBalance;
        _percentageChange = percentageChange;
        _isLoading = false;
        _isFetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isFetching = false;
      });
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // COMPUTED PROPERTIES â€” Financial Metrics
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _formatCurrency(double amount) {
    final abs = amount.abs();
    final formatted = abs.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return amount < 0 ? '-â‚¹$formatted' : 'â‚¹$formatted';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _monthAbbr(int month) {
    const abbrs = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return abbrs[(month - 1).clamp(0, 11)];
  }

  // â”€â”€ Monthly aggregates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double get _monthlySpend {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month &&
            e.category.toLowerCase() != 'income' && e.category.toLowerCase() != 'salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get _monthlyIncome {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month &&
            (e.category.toLowerCase() == 'income' || e.category.toLowerCase() == 'salary'))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get _monthlyBudgetTotal =>
      _budgets.fold(0.0, (sum, b) => sum + b.amount);
  double get _monthlyBudgetSpent =>
      _budgets.fold(0.0, (sum, b) => sum + b.spent);

  Map<String, double> get _categoryTotals {
    final now = DateTime.now();
    final totals = <String, double>{};
    for (final e in _allExpenses) {
      if (e.date.year == now.year && e.date.month == now.month &&
          e.category.toLowerCase() != 'income' && e.category.toLowerCase() != 'salary') {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
    }
    return totals;
  }

  // â”€â”€ Financial health metrics â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double get _savingsRate {
    if (_monthlyIncome <= 0) return 0;
    return ((_monthlyIncome - _monthlySpend) / _monthlyIncome * 100).clamp(-100, 100);
  }

  double get _emergencyFundMonths {
    if (_monthlySpend <= 0) return 0;
    return (_totalBalance / _monthlySpend).clamp(0, 99);
  }

  double get _netWorth {
    final investmentValue = _investments.fold(0.0, (s, i) => s + i.currentValue);
    final savingsValue = _savingsGoals.fold(0.0, (s, g) => s + g.currentAmount);
    return _totalBalance + investmentValue + savingsValue;
  }

  double get _monthlyCashFlow => _monthlyIncome - _monthlySpend;

  int get _budgetsOnTrack =>
      _budgets.where((b) => b.usagePercent < 90).length;

  int get _budgetRiskCount =>
      _budgets.where((b) => b.usagePercent >= 90).length;

  double get _budgetUsage {
    if (_monthlyBudgetTotal <= 0) return 0;
    return (_monthlyBudgetSpent / _monthlyBudgetTotal).clamp(0, 2);
  }

  int get _overdueBillsCount => _allBills.where((b) => b.isOverdue).length;

  double get _overdueBillsTotal =>
      _allBills.where((b) => b.isOverdue).fold(0.0, (s, b) => s + b.amount);

  double get _upcomingBillsTotal =>
      _upcomingBills.fold(0.0, (s, b) => s + b.amount);

  double get _debtPayments =>
      _allBills
          .where((b) =>
              (b.category == BillCategory.loan || b.category == BillCategory.creditCard) &&
              b.isUpcoming)
          .fold(0.0, (s, b) => s + b.amount);

  double get _totalInvestedValue =>
      _investments.fold(0.0, (s, i) => s + i.currentValue);
  double get _totalInvestedAmount =>
      _investments.fold(0.0, (s, i) => s + i.amountInvested);
  double get _totalInvestmentReturns => _totalInvestedValue - _totalInvestedAmount;

  double get _savingsGoalProgress {
    final target = _savingsGoals.fold(0.0, (s, g) => s + g.targetAmount);
    final current = _savingsGoals.fold(0.0, (s, g) => s + g.currentAmount);
    if (target <= 0) return 0;
    return (current / target * 100).clamp(0, 100);
  }

  // â”€â”€ Financial Health Score (0-100) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Weighted: Savings Rate (25), Emergency Fund (25), Budget Adherence (25),
  //           Investment Health (15), Debt Management (10)
  int get _financialHealthScore {
    // Savings Rate score: 20%+ = full marks
    final savingsScore = (_savingsRate / 20.0).clamp(0, 1) * 25;

    // Emergency Fund: 6+ months = full marks
    final emergencyScore = (_emergencyFundMonths / 6.0).clamp(0, 1) * 25;

    // Budget adherence: <80% usage = full marks, >100% = 0
    double budgetScore = 25.0;
    if (_monthlyBudgetTotal > 0) {
      budgetScore = ((1.0 - (_budgetUsage - 0.5).clamp(0, 0.5) / 0.5) * 25).clamp(0, 25);
    }

    // Investment: having any investments and positive returns
    double investScore = 0;
    if (_investments.isNotEmpty) {
      investScore = 7.5;
      if (_totalInvestmentReturns >= 0) investScore = 15;
    }

    // Debt: no overdue bills = full marks
    double debtScore = 10;
    if (_overdueBillsCount > 0) {
      debtScore = (10 - _overdueBillsCount * 3.0).clamp(0, 10);
    }

    return (savingsScore + emergencyScore + budgetScore + investScore + debtScore)
        .round()
        .clamp(0, 100);
  }

  Color _healthScoreColor(int score) {
    if (score >= 75) return const Color(0xFF16A34A);
    if (score >= 50) return const Color(0xFFEA580C);
    return const Color(0xFFDC2626);
  }

  String _healthScoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Fair';
    if (score >= 35) return 'Needs Work';
    return 'Critical';
  }

  // â”€â”€ Kids / Parents spending â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  bool _containsAny(String source, List<String> keywords) {
    final text = source.toLowerCase();
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  String _expenseBlob(Expense e) =>
      '${e.category} ${e.description} ${e.notes ?? ''} ${e.tags.join(' ')}'.toLowerCase();

  double get _kidsSpendingThisMonth {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month &&
            (_containsAny(_expenseBlob(e), _educationKeywords) ||
             _containsAny(_expenseBlob(e), _kidMoneySentKeywords)))
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get _parentsSpendingThisMonth {
    final now = DateTime.now();
    return _allExpenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month &&
            (_containsAny(_expenseBlob(e), _parentKeywords) ||
             _containsAny(_expenseBlob(e), _healthKeywords) ||
             _containsAny(_expenseBlob(e), _insuranceKeywords)))
        .fold(0.0, (s, e) => s + e.amount);
  }

  // â”€â”€ Previous month comparison â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double get _previousMonthSpend {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    return _allExpenses
        .where((e) =>
            e.date.year == prev.year && e.date.month == prev.month &&
            e.category.toLowerCase() != 'income' && e.category.toLowerCase() != 'salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  // â”€â”€ Smart tips engine â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<_SmartTip> get _smartTips {
    final tips = <_SmartTip>[];

    if (_monthlyIncome > 0 && _savingsRate < 20) {
      tips.add(_SmartTip(
        icon: Icons.savings_outlined,
        color: const Color(0xFFEA580C),
        title: 'Boost Your Savings',
        message: 'You\'re saving ${_savingsRate.toStringAsFixed(0)}% of income. The 50/30/20 rule recommends saving at least 20%.',
        priority: 1,
      ));
    }

    if (_emergencyFundMonths < 6 && _monthlySpend > 0) {
      tips.add(_SmartTip(
        icon: Icons.shield_outlined,
        color: const Color(0xFFDC2626),
        title: 'Emergency Fund Gap',
        message: 'Your emergency fund covers ${_emergencyFundMonths.toStringAsFixed(1)} months. Aim for 6 months of expenses (${_formatCurrency(_monthlySpend * 6)}).',
        priority: 2,
      ));
    }

    if (_overdueBillsCount > 0) {
      tips.add(_SmartTip(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFDC2626),
        title: 'Overdue Bills',
        message: 'You have $_overdueBillsCount overdue bill${_overdueBillsCount > 1 ? 's' : ''} totaling ${_formatCurrency(_overdueBillsTotal)}. Late payments hurt your financial health.',
        priority: 0,
      ));
    }

    if (_budgetRiskCount > 0) {
      final worstBudget = _budgets
          .where((b) => b.usagePercent >= 90)
          .reduce((a, b) => a.usagePercent > b.usagePercent ? a : b);
      tips.add(_SmartTip(
        icon: Icons.pie_chart_outline,
        color: const Color(0xFFEA580C),
        title: 'Budget Alert',
        message: '${_capitalize(worstBudget.category)} is at ${worstBudget.usagePercent.toStringAsFixed(0)}% â€” consider reallocating or reducing spend.',
        priority: 1,
      ));
    }

    if (_investments.isNotEmpty && _totalInvestmentReturns < 0) {
      tips.add(_SmartTip(
        icon: Icons.trending_down,
        color: const Color(0xFFDC2626),
        title: 'Portfolio Check',
        message: 'Your investments show ${_formatCurrency(_totalInvestmentReturns)} in losses. Review underperforming assets.',
        priority: 3,
      ));
    }

    if (_investments.isEmpty && _monthlyIncome > 0) {
      tips.add(_SmartTip(
        icon: Icons.query_stats,
        color: const Color(0xFF7C3AED),
        title: 'Start Investing',
        message: 'No investments tracked yet. Even small SIPs can grow significantly over time with compounding.',
        priority: 4,
      ));
    }

    final insuranceBills = _allBills.where((b) => b.category == BillCategory.insurance).toList();
    if (insuranceBills.isEmpty) {
      tips.add(_SmartTip(
        icon: Icons.health_and_safety_outlined,
        color: const Color(0xFF2563EB),
        title: 'Insurance Coverage',
        message: 'No insurance premiums tracked. Term life & health insurance are essential for family financial protection.',
        priority: 5,
      ));
    }

    if (_previousMonthSpend > 0 && _monthlySpend > _previousMonthSpend * 1.2) {
      final increase = ((_monthlySpend / _previousMonthSpend - 1) * 100).toStringAsFixed(0);
      tips.add(_SmartTip(
        icon: Icons.trending_up,
        color: const Color(0xFFEA580C),
        title: 'Spending Spike',
        message: 'This month\'s spending is $increase% higher than last month. Review recent transactions for optimization.',
        priority: 2,
      ));
    }

    tips.sort((a, b) => a.priority.compareTo(b.priority));
    return tips.take(4).toList();
  }

  // â”€â”€ Smart Alerts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<_AlertItem> get _smartAlerts {
    final alerts = <_AlertItem>[];

    for (final bill in _allBills.where((b) => b.isOverdue)) {
      alerts.add(_AlertItem(
        icon: Icons.error_outline,
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
        text: '${bill.name} overdue',
        priority: 0,
      ));
    }

    for (final bill in _upcomingBills.where((b) => b.daysUntilDue <= 3)) {
      alerts.add(_AlertItem(
        icon: Icons.payment,
        color: const Color(0xFFEA580C),
        bgColor: const Color(0xFFFFEDD5),
        text: '${bill.name} due ${bill.daysUntilDue == 0 ? "today" : "in ${bill.daysUntilDue}d"}',
        priority: 1,
      ));
    }

    for (final b in _budgets.where((b) => b.usagePercent >= 90)) {
      alerts.add(_AlertItem(
        icon: Icons.pie_chart,
        color: const Color(0xFFEA580C),
        bgColor: const Color(0xFFFFEDD5),
        text: '${_capitalize(b.category)} budget ${b.usagePercent.toStringAsFixed(0)}%',
        priority: 2,
      ));
    }

    for (final event in _upcomingEvents.where((e) => e.daysUntil <= 7)) {
      final label = event.daysUntil == 0
          ? 'Today' : event.daysUntil == 1
          ? 'Tomorrow' : 'In ${event.daysUntil}d';
      alerts.add(_AlertItem(
        icon: _plannerTypeIcon(event.type),
        color: _plannerTypeColors(event.type).$2,
        bgColor: _plannerTypeColors(event.type).$1,
        text: '${event.title} â€” $label',
        priority: 3,
      ));
    }

    alerts.sort((a, b) => a.priority.compareTo(b.priority));
    return alerts;
  }

  // â”€â”€ Unified Timeline items â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<_TimelineEntry> get _unifiedTimeline {
    final entries = <_TimelineEntry>[];
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 30));

    for (final bill in _upcomingBills.where((b) => b.dueDate.isBefore(cutoff))) {
      entries.add(_TimelineEntry(
        date: bill.dueDate,
        icon: Bill.iconForCategory(bill.category),
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
        title: bill.name,
        subtitle: '${_formatCurrency(bill.amount)} â€¢ ${Bill.categoryLabel(bill.category)}',
        tag: 'Bill',
        tagColor: const Color(0xFFDC2626),
      ));
    }

    for (final event in _upcomingEvents.where((e) =>
        e.startDate.isBefore(cutoff) && !e.startDate.isBefore(now.subtract(const Duration(days: 1))))) {
      final colors = _plannerTypeColors(event.type);
      entries.add(_TimelineEntry(
        date: event.startDate,
        icon: _plannerTypeIcon(event.type),
        color: colors.$2,
        bgColor: colors.$1,
        title: event.title,
        subtitle: _plannerTypeLabel(event.type),
        tag: _plannerTypeLabel(event.type),
        tagColor: colors.$2,
      ));
    }

    for (final goal in _savingsGoals.where((g) =>
        g.targetDate != null && g.targetDate!.isBefore(cutoff) && g.targetDate!.isAfter(now))) {
      entries.add(_TimelineEntry(
        date: goal.targetDate!,
        icon: Icons.flag_outlined,
        color: const Color(0xFF059669),
        bgColor: const Color(0xFFDCFCE7),
        title: '${goal.name} deadline',
        subtitle: '${goal.progressPercent.toStringAsFixed(0)}% complete â€¢ ${_formatCurrency(goal.remaining)} remaining',
        tag: 'Goal',
        tagColor: const Color(0xFF059669),
      ));
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries.take(8).toList();
  }

  // â”€â”€ Spending trend (category comparison vs last month) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<_SpendingTrend> get _spendingTrends {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    final currentTotals = <String, double>{};
    final prevTotals = <String, double>{};

    for (final e in _allExpenses) {
      final cat = e.category.toLowerCase();
      if (cat == 'income' || cat == 'salary') continue;
      if (e.date.year == now.year && e.date.month == now.month) {
        currentTotals[e.category] = (currentTotals[e.category] ?? 0) + e.amount;
      } else if (e.date.year == prev.year && e.date.month == prev.month) {
        prevTotals[e.category] = (prevTotals[e.category] ?? 0) + e.amount;
      }
    }

    final trends = <_SpendingTrend>[];
    for (final entry in currentTotals.entries) {
      final prevAmount = prevTotals[entry.key] ?? 0;
      if (prevAmount > 0) {
        final changePercent = ((entry.value - prevAmount) / prevAmount * 100);
        if (changePercent.abs() >= 10) {
          trends.add(_SpendingTrend(
            category: entry.key,
            current: entry.value,
            previous: prevAmount,
            changePercent: changePercent,
          ));
        }
      }
    }
    trends.sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));
    return trends.take(3).toList();
  }

  // â”€â”€ Budget run-rate projection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<_BudgetProjection> get _budgetProjections {
    final now = DateTime.now();
    final dayOfMonth = now.day;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    if (dayOfMonth < 3) return [];

    final projections = <_BudgetProjection>[];
    for (final b in _budgets) {
      if (b.spent <= 0) continue;
      final dailyRate = b.spent / dayOfMonth;
      final projected = dailyRate * daysInMonth;
      if (projected > b.amount * 1.1) {
        projections.add(_BudgetProjection(
          category: b.category,
          budgeted: b.amount,
          projected: projected,
          overshoot: projected - b.amount,
        ));
      }
    }
    projections.sort((a, b) => b.overshoot.compareTo(a.overshoot));
    return projections.take(3).toList();
  }

  // â”€â”€ AI Forecast â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadAIForecast() async {
    setState(() { _aiForecastLoading = true; _aiForecastError = null; });
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
      setState(() { _aiForecastProjection = result['projection'] as String?; _aiForecastLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiForecastLoading = false; _aiForecastError = e.toString(); });
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // BUILD
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  @override
  Widget build(BuildContext context) {
    return _buildWebLayout(context);
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // WEB (DESKTOP) LAYOUT
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _buildWebLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadDashboardData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // â”€â”€ Smart Alerts Banner â”€â”€
                        if (_smartAlerts.isNotEmpty)
                          _buildWebAlerts(isDark),

                        // â”€â”€ Section 1: Financial Pulse â”€â”€
                        const SizedBox(height: 8),
                        _buildWebFinancialPulse(isDark),

                        // â”€â”€ Section 2: 360Â° Status Cards â”€â”€
                        const SizedBox(height: 32),
                        _buildWebStatusSection(isDark),

                        // â”€â”€ Section 3: Spending Spotlight + Upcoming Timeline â”€â”€
                        const SizedBox(height: 32),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildWebSpendingSpotlight(isDark)),
                            const SizedBox(width: 24),
                            Expanded(child: _buildWebTimeline(isDark)),
                          ],
                        ),

                        // â”€â”€ Section 4: AI Financial Advisor â”€â”€
                        const SizedBox(height: 32),
                        _buildWebAISection(isDark),

                        // â”€â”€ Section 5: Family Lens (Kids + Parents) â”€â”€
                        const SizedBox(height: 32),
                        _buildWebFamilyLens(isDark),

                        // â”€â”€ Section 6: Recent Transactions â”€â”€
                        const SizedBox(height: 32),
                        _buildWebTransactionsTable(isDark),
                      ],
                    ),
                  ),
                ),
    );
  }

  // â”€â”€ Web: Smart Alerts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebAlerts(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _smartAlerts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final alert = _smartAlerts[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: alert.bgColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: alert.color.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(alert.icon, size: 15, color: alert.color),
              const SizedBox(width: 8),
              Text(alert.text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: alert.color)),
            ]),
          );
        },
      ),
    );
  }

  // â”€â”€ Web: Financial Pulse â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebFinancialPulse(bool isDark) {
    final score = _financialHealthScore;
    final scoreColor = _healthScoreColor(score);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          // Score gauge
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _GaugePainter(score: score / 100, color: scoreColor, strokeWidth: 10),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$score', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                    child: Text(_healthScoreLabel(score),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scoreColor)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 32),
          // Metrics
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Family Financial Health', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('360Â° overview of your household finances',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                const SizedBox(height: 20),
                Row(children: [
                  _webPulseMetric('Net Worth', _formatCurrency(_netWorth), Icons.account_balance_wallet, const Color(0xFF60A5FA)),
                  const SizedBox(width: 24),
                  _webPulseMetric('Monthly Cash Flow',
                      '${_monthlyCashFlow >= 0 ? '+' : ''}${_formatCurrency(_monthlyCashFlow)}',
                      Icons.swap_vert_circle_outlined,
                      _monthlyCashFlow >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
                  const SizedBox(width: 24),
                  _webPulseMetric('Savings Rate', '${_savingsRate.toStringAsFixed(0)}%',
                      Icons.savings_outlined,
                      _savingsRate >= 20 ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24)),
                  const SizedBox(width: 24),
                  _webPulseMetric('Budget Health',
                      _budgets.isEmpty ? 'Not Set' : '${(_budgetUsage * 100).toStringAsFixed(0)}% used',
                      Icons.pie_chart_outline,
                      _budgetUsage <= 0.8 ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
                ]),
              ],
            ),
          ),
          // Balance
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text('Balance', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 4),
              Text(_formatCurrency(_totalBalance),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _percentageChange >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: _percentageChange >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_percentageChange >= 0 ? '+' : ''}${_percentageChange.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _percentageChange >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _webPulseMetric(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
        ]),
      ]),
    );
  }

  // â”€â”€ Web: 360Â° Status Cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebStatusSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Money Right Now', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _webStatusCard(
            title: 'Monthly Cash Flow',
            icon: Icons.swap_vert_circle_outlined,
            gradient: const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_formatCurrency(_monthlyCashFlow),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 10),
              _cashFlowBar(),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Income: ${_formatCurrency(_monthlyIncome)}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                Text('Spend: ${_formatCurrency(_monthlySpend)}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
              ]),
            ]),
            onTap: () => Navigator.of(context).pushNamed('/expenses'),
          )),
          const SizedBox(width: 16),
          Expanded(child: _webStatusCard(
            title: 'Budget Tracker',
            icon: Icons.pie_chart_outline,
            gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_budgetsOnTrack of ${_budgets.length} on track',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: _budgetUsage.clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: _budgetUsage > 0.9 ? Colors.red[300] : Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(_budgetUsage * 100).toStringAsFixed(0)}% of total budget used',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ]),
            onTap: () => Navigator.of(context).pushNamed('/budget'),
          )),
          const SizedBox(width: 16),
          Expanded(child: _webStatusCard(
            title: 'Bills & Commitments',
            icon: Icons.receipt_long_outlined,
            gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_formatCurrency(_upcomingBillsTotal),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text('${_upcomingBills.length} upcoming bill${_upcomingBills.length != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              if (_overdueBillsCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                  child: Text('âš  $_overdueBillsCount overdue',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ]),
            onTap: () => Navigator.of(context).pushNamed('/bills'),
          )),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _webStatusCard(
            title: 'Savings Goals',
            icon: Icons.flag_outlined,
            gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_savingsGoalProgress.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (_savingsGoalProgress / 100).clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text('${_savingsGoals.length} goal${_savingsGoals.length != 1 ? 's' : ''} active',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ]),
            onTap: () => Navigator.of(context).pushNamed('/savings'),
          )),
          const SizedBox(width: 16),
          Expanded(child: _webStatusCard(
            title: 'Investments',
            icon: Icons.query_stats,
            gradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_formatCurrency(_totalInvestedValue),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  _totalInvestmentReturns >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 16, color: _totalInvestmentReturns >= 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_totalInvestmentReturns >= 0 ? '+' : ''}${_formatCurrency(_totalInvestmentReturns)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: _totalInvestmentReturns >= 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('${_investments.length} asset${_investments.length != 1 ? 's' : ''} tracked',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ]),
            onTap: () => Navigator.of(context).pushNamed('/investments'),
          )),
          const SizedBox(width: 16),
          Expanded(child: _webStatusCard(
            title: 'Family Spending',
            icon: Icons.family_restroom_outlined,
            gradient: const [Color(0xFF14B8A6), Color(0xFF0D9488)],
            isDark: isDark,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_formatCurrency(_kidsSpendingThisMonth + _parentsSpendingThisMonth),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.child_care, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text('Kids: ${_formatCurrency(_kidsSpendingThisMonth)}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(width: 12),
                const Icon(Icons.elderly, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text('Parents: ${_formatCurrency(_parentsSpendingThisMonth)}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
              ]),
            ]),
            onTap: () => Navigator.of(context).pushNamed('/kids-dashboard'),
          )),
        ]),
      ],
    );
  }

  Widget _cashFlowBar() {
    final total = _monthlyIncome + _monthlySpend;
    final incomeRatio = total > 0 ? _monthlyIncome / total : 0.5;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(children: [
          Expanded(flex: (incomeRatio * 100).round(), child: Container(color: const Color(0xFF86EFAC))),
          Expanded(flex: ((1 - incomeRatio) * 100).round(), child: Container(color: const Color(0xFFFCA5A5))),
        ]),
      ),
    );
  }

  Widget _webStatusCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required bool isDark,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white.withValues(alpha: 0.4)),
              ]),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Web: Spending Spotlight â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebSpendingSpotlight(bool isDark) {
    final totals = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grandTotal = totals.fold(0.0, (sum, item) => sum + item.value);
    final top = totals.take(5).toList();
    final primary = Theme.of(context).colorScheme.primary;
    final colors = [primary, Colors.orange, const Color(0xFF22C55E), const Color(0xFF8B5CF6), Colors.grey.shade400];

    return _webCard(
      isDark: isDark,
      child: SizedBox(
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Spending Spotlight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('This month by category', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 16),
            if (top.isEmpty)
              Expanded(child: Center(child: Text('No expenses this month', style: TextStyle(color: Colors.grey[400]))))
            else
              Expanded(
                child: Row(
                  children: [
                    // Donut chart
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 140, height: 140,
                          child: Stack(alignment: Alignment.center, children: [
                            CustomPaint(
                              size: const Size(140, 140),
                              painter: _DonutPainter(
                                segments: top.asMap().entries.map((e) => _DonutSegment(
                                  share: grandTotal > 0 ? e.value.value / grandTotal : 0,
                                  color: colors[e.key % colors.length],
                                )).toList(),
                                trackColor: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                                strokeWidth: 18,
                              ),
                            ),
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_formatCurrency(grandTotal),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                              Text('Total', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                    // Legend
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: top.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final pct = grandTotal > 0 ? (item.value / grandTotal * 100) : 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Container(width: 8, height: 8,
                                  decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_capitalize(item.key), style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                              Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text(_formatCurrency(item.value), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          );
                        }).toList(),
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

  // â”€â”€ Web: Unified Timeline â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebTimeline(bool isDark) {
    return _webCard(
      isDark: isDark,
      child: SizedBox(
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text("What's Ahead", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/family-planner'),
                child: Text('View all', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: _unifiedTimeline.isEmpty
                  ? Center(child: Text('Nothing upcoming in the next 30 days', style: TextStyle(color: Colors.grey[400])))
                  : ListView(
                      children: _unifiedTimeline.map((e) => _buildTimelineRow(e)).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow(_TimelineEntry entry, {bool compact = false}) {
    final now = DateTime.now();
    final days = entry.date.difference(DateTime(now.year, now.month, now.day)).inDays;
    final daysLabel = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : 'In ${days}d';

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: entry.bgColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: entry.color, width: 3)),
      ),
      child: Row(children: [
        Container(
          width: compact ? 28 : 32,
          height: compact ? 28 : 32,
          decoration: BoxDecoration(color: entry.bgColor, borderRadius: BorderRadius.circular(8)),
          child: Icon(entry.icon, size: compact ? 14 : 16, color: entry.color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.title, style: TextStyle(fontSize: compact ? 12 : 13, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(entry.subtitle, style: TextStyle(fontSize: compact ? 10 : 11, color: Colors.grey[500]),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: entry.tagColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
            child: Text(entry.tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: entry.tagColor)),
          ),
          const SizedBox(height: 2),
          Text(daysLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: days <= 1 ? const Color(0xFFDC2626) : days <= 3 ? const Color(0xFFEA580C) : Colors.grey[500])),
        ]),
      ]),
    );
  }

  // â”€â”€ Web: AI Financial Advisor â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebAISection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 22, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          const Text('AI Financial Advisor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(999)),
            child: const Text('BETA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
          ),
          const Spacer(),
          if (_aiForecastLoading)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            FilledButton.icon(
              onPressed: _loadAIForecast,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(_aiForecastProjection != null ? 'Refresh Forecast' : 'Analyze with AI'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ]),
        const SizedBox(height: 16),

        // AI Prediction + Trends + Risk row
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Spending Trends
          Expanded(child: _webCard(isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.insights, size: 16, color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                const Text('Spending Trends', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              if (_spendingTrends.isEmpty)
                Text('Not enough data to compare trends yet', style: TextStyle(fontSize: 12, color: Colors.grey[400]))
              else
                ..._spendingTrends.map((trend) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: trend.changePercent > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8)),
                      child: Icon(
                        trend.changePercent > 0 ? Icons.trending_up : Icons.trending_down,
                        size: 14,
                        color: trend.changePercent > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_capitalize(trend.category), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('${trend.changePercent > 0 ? '+' : ''}${trend.changePercent.toStringAsFixed(0)}% vs last month',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ])),
                    Text(_formatCurrency(trend.current), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                )),
            ],
          ))),
          const SizedBox(width: 16),

          // Budget Risk Projections
          Expanded(child: _webCard(isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFEA580C)),
                const SizedBox(width: 6),
                const Text('Budget Risk Alert', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              if (_budgetProjections.isEmpty)
                Text('All budgets on track at current pace', style: TextStyle(fontSize: 12, color: Colors.grey[400]))
              else
                ..._budgetProjections.map((proj) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_capitalize(proj.category), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(999)),
                        child: Text('+${_formatCurrency(proj.overshoot)}',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (proj.projected / proj.budgeted).clamp(0, 1.5),
                        minHeight: 6,
                        backgroundColor: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Projected: ${_formatCurrency(proj.projected)} of ${_formatCurrency(proj.budgeted)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  ]),
                )),
            ],
          ))),
          const SizedBox(width: 16),

          // Smart Tips
          Expanded(child: _webCard(isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                const Text('Smart Tips', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              if (_smartTips.isEmpty)
                Text('Looking good! No urgent financial tips.', style: TextStyle(fontSize: 12, color: Colors.grey[400]))
              else
                ..._smartTips.map((tip) => _buildTipCard(tip)),
            ],
          ))),
        ]),

        // AI Forecast result
        if (_aiForecastError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
            child: Text(_aiForecastError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
        if (_aiForecastProjection != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF5F3FF), Color(0xFFEEF2FF)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                SizedBox(width: 8),
                Text('AI Projection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7C3AED))),
              ]),
              const SizedBox(height: 10),
              Text(_aiForecastProjection!, style: const TextStyle(fontSize: 13, height: 1.5)),
            ]),
          ),
        ],

      ],
    );
  }

  Widget _buildTipCard(_SmartTip tip, {bool compact = false}) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: tip.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: tip.color, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(tip.icon, size: compact ? 16 : 18, color: tip.color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tip.title, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(tip.message, style: TextStyle(fontSize: compact ? 10 : 11, color: Colors.grey[600], height: 1.3)),
        ])),
      ]),
    );
  }

  // â”€â”€ Web: Family Lens (Kids + Parents) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebFamilyLens(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Family Lens', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Kids & parents spending insights', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Kids
          Expanded(child: _webCard(isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.child_care, size: 18, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                const Text('Kids Corner', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/kids-dashboard'),
                  child: const Text('Details â†’', style: TextStyle(fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 14),
              _familyMetricRow('Education & School', _formatCurrency(_kidsSpendingThisMonth), const Color(0xFF2563EB)),
              const SizedBox(height: 8),
              _familyMetricRow('Money Sent', _formatCurrency(_kidMoneySentTotal), const Color(0xFF0D9488)),
              const SizedBox(height: 8),
              _familyMetricRow('Kid Investments', _formatCurrency(_kidInvestmentsTotal), const Color(0xFF7C3AED)),
              const SizedBox(height: 12),
              if (_nextKidEvent != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.event, size: 14, color: Color(0xFFCA8A04)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_nextKidEvent!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF854D0E)))),
                  ]),
                ),
            ],
          ))),
          const SizedBox(width: 24),
          // Parents
          Expanded(child: _webCard(isDark: isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: const Color(0xFFFCE7F3), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.elderly, size: 18, color: Color(0xFFDB2777)),
                ),
                const SizedBox(width: 10),
                const Text('Parents Care', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/parents-dashboard'),
                  child: const Text('Details â†’', style: TextStyle(fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 14),
              _familyMetricRow('Health & Medical', _formatCurrency(_parentHealthSpend), const Color(0xFFDC2626)),
              const SizedBox(height: 8),
              _familyMetricRow('Insurance Premiums', _formatCurrency(_parentInsuranceSpend), const Color(0xFF059669)),
              const SizedBox(height: 8),
              _familyMetricRow('Total Support', _formatCurrency(_parentsSpendingThisMonth), const Color(0xFFDB2777)),
              const SizedBox(height: 12),
              if (_nextParentReminder != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.health_and_safety, size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_nextParentReminder!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)))),
                  ]),
                ),
            ],
          ))),
        ]),
      ],
    );
  }

  // Additional family computed properties
  double get _kidMoneySentTotal {
    final now = DateTime.now();
    return _allExpenses
        .where((e) => e.date.year == now.year && e.date.month == now.month &&
            _containsAny(_expenseBlob(e), _kidMoneySentKeywords))
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get _kidInvestmentsTotal =>
      _investments.where((i) => i.childName != null && i.childName!.isNotEmpty)
          .fold(0.0, (s, i) => s + i.currentValue);

  double get _parentHealthSpend {
    final now = DateTime.now();
    return _allExpenses
        .where((e) => e.date.year == now.year && e.date.month == now.month &&
            _containsAny(_expenseBlob(e), _healthKeywords))
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get _parentInsuranceSpend {
    final now = DateTime.now();
    return _allExpenses
        .where((e) => e.date.year == now.year && e.date.month == now.month &&
            _containsAny(_expenseBlob(e), _insuranceKeywords))
        .fold(0.0, (s, e) => s + e.amount);
  }

  String? get _nextKidEvent {
    final now = DateTime.now();
    final schoolKeywords = ['school', 'ptm', 'sports day', 'annual day', 'graduation'];
    for (final item in _upcomingEvents) {
      final text = '${item.title} ${item.description ?? ''}'.toLowerCase();
      if (schoolKeywords.any((kw) => text.contains(kw))) {
        final days = item.daysUntil;
        final dLabel = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : 'In ${days}d';
        return '${item.title} â€” $dLabel';
      }
    }
    return null;
  }

  String? get _nextParentReminder {
    final now = DateTime.now();
    for (final item in _upcomingEvents) {
      final text = '${item.title} ${item.description ?? ''}'.toLowerCase();
      if (_containsAny(text, _healthKeywords) || _containsAny(text, _parentKeywords)) {
        final days = item.daysUntil;
        final dLabel = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : 'In ${days}d';
        return '${item.title} â€” $dLabel';
      }
    }
    return null;
  }

  Widget _familyMetricRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }

  // â”€â”€ Web: Recent Transactions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildWebTransactionsTable(bool isDark) {
    return _webCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/expenses'),
              child: Text('View all', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ),
          ]),
          const SizedBox(height: 12),
          if (_recentExpenses.isEmpty)
            Padding(padding: const EdgeInsets.all(24),
                child: Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey[400]))))
          else
            ..._recentExpenses.take(8).map((expense) {
              final isIncome = expense.category.toLowerCase() == 'income' || expense.category.toLowerCase() == 'salary';
              final bgColor = AppColors.getCategoryColor(expense.category);
              final iconColor = AppColors.getCategoryIconColor(expense.category);
              final d = expense.date;
              final dateStr = '${_monthAbbr(d.month)} ${d.day}';

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9))),
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                    child: Icon(AppIcons.getCategoryIcon(expense.category), size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(expense.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
                    child: Text(_capitalize(expense.category), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: iconColor)),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${isIncome ? '+' : '-'}${_formatCurrency(expense.amount)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                        color: isIncome ? AppColors.success : AppColors.error),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // SHARED WIDGETS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _webCard({required bool isDark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: child,
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(AppIcons.error, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Failed to load dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 14, color: Colors.grey[500]), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadDashboardData,
            icon: const Icon(AppIcons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      ),
    );
  }

  // â”€â”€ Planner helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  (Color, Color) _plannerTypeColors(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:    return (const Color(0xFFFCE7F3), const Color(0xFFDB2777));
      case PlannerItemType.anniversary: return (const Color(0xFFF3E8FF), const Color(0xFF9333EA));
      case PlannerItemType.vacation:    return (const Color(0xFFDBEAFE), const Color(0xFF2563EB));
      case PlannerItemType.event:       return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case PlannerItemType.reminder:    return (const Color(0xFFFFEDD5), const Color(0xFFEA580C));
      case PlannerItemType.task:        return (const Color(0xFFDCFCE7), const Color(0xFF16A34A));
    }
  }

  IconData _plannerTypeIcon(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:    return Icons.cake_outlined;
      case PlannerItemType.anniversary: return Icons.favorite;
      case PlannerItemType.vacation:    return Icons.flight_takeoff_outlined;
      case PlannerItemType.event:       return Icons.event_outlined;
      case PlannerItemType.reminder:    return Icons.notifications_outlined;
      case PlannerItemType.task:        return Icons.task_alt_outlined;
    }
  }

  String _plannerTypeLabel(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:    return 'Birthday';
      case PlannerItemType.anniversary: return 'Anniversary';
      case PlannerItemType.vacation:    return 'Vacation';
      case PlannerItemType.event:       return 'Event';
      case PlannerItemType.reminder:    return 'Reminder';
      case PlannerItemType.task:        return 'Task';
    }
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DATA CLASSES
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _SmartTip {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final int priority;
  const _SmartTip({required this.icon, required this.color, required this.title, required this.message, required this.priority});
}

class _AlertItem {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String text;
  final int priority;
  const _AlertItem({required this.icon, required this.color, required this.bgColor, required this.text, required this.priority});
}

class _TimelineEntry {
  final DateTime date;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String tag;
  final Color tagColor;
  const _TimelineEntry({
    required this.date, required this.icon, required this.color, required this.bgColor,
    required this.title, required this.subtitle, required this.tag, required this.tagColor,
  });
}

class _SpendingTrend {
  final String category;
  final double current;
  final double previous;
  final double changePercent;
  const _SpendingTrend({required this.category, required this.current, required this.previous, required this.changePercent});
}

class _BudgetProjection {
  final String category;
  final double budgeted;
  final double projected;
  final double overshoot;
  const _BudgetProjection({required this.category, required this.budgeted, required this.projected, required this.overshoot});
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// CUSTOM PAINTERS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

/// Circular gauge painter for the Financial Health Score
class _GaugePainter extends CustomPainter {
  final double score; // 0.0 - 1.0
  final Color color;
  final double strokeWidth;

  const _GaugePainter({required this.score, required this.color, this.strokeWidth = 6});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;
    const startAngle = -math.pi * 0.75;
    const totalSweep = math.pi * 1.5;

    // Track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, totalSweep, false, trackPaint);

    // Filled arc
    final fillPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, totalSweep * score.clamp(0, 1), false, fillPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.score != score || old.color != color;
}

/// Multi-color donut chart painter (reused from original)
class _DonutSegment {
  final double share;
  final Color color;
  const _DonutSegment({required this.share, required this.color});
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final Color trackColor;
  final double strokeWidth;

  const _DonutPainter({required this.segments, required this.trackColor, required this.strokeWidth});

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
      canvas.drawArc(rect, _toRad(currentAngle), _toRad(sweepDeg), false, paint);
      currentAngle += sweepDeg + gapDeg;
    }
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segments != segments || old.trackColor != trackColor || old.strokeWidth != strokeWidth;
}
