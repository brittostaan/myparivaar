import 'dart:math' as math;
import 'dart:async';

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
import '../utils/category_emoji.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Home Dashboard — Rich Authenticated Dashboard with Light Design
// ═══════════════════════════════════════════════════════════════════════════

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  // ── Services ───────────────────────────────────────────────────────────────
  final ExpenseService _expenseService = ExpenseService();
  final BudgetService _budgetService = BudgetService();
  final InvestmentService _investmentService = InvestmentService();
  final BillService _billService = BillService();
  final FamilyPlannerService _plannerService = FamilyPlannerService();
  final SavingsService _savingsService = SavingsService();

  // ── State ──────────────────────────────────────────────────────────────────
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
  bool _isLoading = true;
  bool _isFetching = false;
  String? _error;
  Timer? _refreshTimer;

  // AI Insights
  bool _aiInsightsLoading = false;
  List<_AIInsight> _aiInsights = [];

  // Keywords for family spending detection
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

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    // Auto-refresh every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadDashboardData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (_isFetching) return;
    _isFetching = true;
    if (_allExpenses.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final supabaseUrl = authService.supabaseUrl;
      final idToken = await authService.getIdToken();

      // ── Expenses ──
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
      );
      final sortedExpenses = [...expenses]
        ..sort((a, b) => b.date.compareTo(a.date));

      // ── Budgets ──
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

      // ── Investments ──
      List<Investment> investments = [];
      try {
        investments = await _investmentService.getInvestments(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // ── Bills ──
      List<Bill> allBills = [];
      try {
        allBills = await _billService.getBills(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // ── Planner ──
      List<PlannerItem> allPlannerItems = [];
      try {
        allPlannerItems = await _plannerService.getItems(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // ── Savings Goals ──
      List<SavingsGoal> savingsGoals = [];
      try {
        savingsGoals = await _savingsService.getGoals(
          supabaseUrl: supabaseUrl,
          idToken: idToken,
        );
      } catch (_) {}

      // ── Balance ──
      double totalBalance = 0.0;
      for (final expense in expenses) {
        final isIncome = expense.category.toLowerCase() == 'income' ||
            expense.category.toLowerCase() == 'salary';
        totalBalance += isIncome ? expense.amount : -expense.amount;
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
        _isLoading = false;
        _isFetching = false;
      });

      // Generate AI insights after data loads
      _generateAIInsights();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isFetching = false;
      });
    }
  }

  void _generateAIInsights() {
    setState(() => _aiInsightsLoading = true);
    
    final insights = <_AIInsight>[];

    // Savings tip
    if (_monthlyIncome > 0 && _savingsRate < 20) {
      insights.add(_AIInsight(
        emoji: '💡',
        title: 'Boost Savings',
        message: 'You\'re saving ${_savingsRate.toStringAsFixed(0)}% — aim for 20%+ with the 50/30/20 rule.',
        color: const Color(0xFFFBBF24),
      ));
    }

    // Budget warning
    if (_budgetRiskCount > 0) {
      insights.add(_AIInsight(
        emoji: '⚠️',
        title: 'Budget Alert',
        message: '$_budgetRiskCount budget${_budgetRiskCount > 1 ? 's' : ''} at 90%+ — consider reallocating funds.',
        color: const Color(0xFFF97316),
      ));
    }

    // Investment opportunity
    if (_investments.isEmpty && _monthlyIncome > 0) {
      insights.add(_AIInsight(
        emoji: '📈',
        title: 'Start Investing',
        message: 'No investments tracked yet. Small SIPs can grow significantly with compounding.',
        color: const Color(0xFF8B5CF6),
      ));
    } else if (_totalInvestmentReturns > 0) {
      insights.add(_AIInsight(
        emoji: '🎯',
        title: 'Portfolio Growing',
        message: 'Your investments are up ${_formatCurrency(_totalInvestmentReturns)}. Keep the momentum!',
        color: const Color(0xFF22C55E),
      ));
    }

    // Spending trend
    if (_previousMonthSpend > 0 && _monthlySpend > _previousMonthSpend * 1.2) {
      final increase = ((_monthlySpend / _previousMonthSpend - 1) * 100).toStringAsFixed(0);
      insights.add(_AIInsight(
        emoji: '📊',
        title: 'Spending Spike',
        message: 'This month is $increase% higher than last month. Review recent transactions.',
        color: const Color(0xFFEF4444),
      ));
    }

    // Emergency fund
    if (_emergencyFundMonths < 3 && _monthlySpend > 0) {
      insights.add(_AIInsight(
        emoji: '🛡️',
        title: 'Emergency Fund',
        message: 'You have ${_emergencyFundMonths.toStringAsFixed(1)} months coverage. Aim for 6 months.',
        color: const Color(0xFF3B82F6),
      ));
    }

    // Bills reminder
    if (_overdueBillsCount > 0) {
      insights.add(_AIInsight(
        emoji: '🔔',
        title: 'Overdue Bills',
        message: '$_overdueBillsCount bill${_overdueBillsCount > 1 ? 's' : ''} overdue totaling ${_formatCurrency(_overdueBillsTotal)}.',
        color: const Color(0xFFDC2626),
      ));
    }

    // Positive reinforcement
    if (_financialHealthScore >= 75) {
      insights.add(_AIInsight(
        emoji: '✨',
        title: 'Great Progress!',
        message: 'Your financial health is excellent. Keep up the good habits!',
        color: const Color(0xFF10B981),
      ));
    }

    setState(() {
      _aiInsights = insights.take(4).toList();
      _aiInsightsLoading = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPUTED PROPERTIES
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatCurrency(double amount) {
    final abs = amount.abs();
    final formatted = abs.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return amount < 0 ? '-₹$formatted' : '₹$formatted';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  // ── Monthly aggregates ─────────────────────────────────────────────────────

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

  // ── Financial health metrics ───────────────────────────────────────────────

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

  // ── Financial Health Score (0-100) ─────────────────────────────────────────
  int get _financialHealthScore {
    final savingsScore = (_savingsRate / 20.0).clamp(0, 1) * 25;
    final emergencyScore = (_emergencyFundMonths / 6.0).clamp(0, 1) * 25;
    double budgetScore = 25.0;
    if (_monthlyBudgetTotal > 0) {
      budgetScore = ((1.0 - (_budgetUsage - 0.5).clamp(0, 0.5) / 0.5) * 25).clamp(0, 25);
    }
    double investScore = 0;
    if (_investments.isNotEmpty) {
      investScore = 7.5;
      if (_totalInvestmentReturns >= 0) investScore = 15;
    }
    double debtScore = 10;
    if (_overdueBillsCount > 0) {
      debtScore = (10 - _overdueBillsCount * 3.0).clamp(0, 10);
    }
    return (savingsScore + emergencyScore + budgetScore + investScore + debtScore)
        .round()
        .clamp(0, 100);
  }

  Color _healthScoreColor(int score) {
    if (score >= 75) return const Color(0xFF22C55E);
    if (score >= 50) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  String _healthScoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Fair';
    if (score >= 35) return 'Needs Work';
    return 'Critical';
  }

  // ── Family spending ────────────────────────────────────────────────────────

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

  double get _previousMonthSpend {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    return _allExpenses
        .where((e) =>
            e.date.year == prev.year && e.date.month == prev.month &&
            e.category.toLowerCase() != 'income' && e.category.toLowerCase() != 'salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildNavBar(context, isMobile),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _error != null
                    ? _buildErrorState()
                    : RefreshIndicator(
                        onRefresh: _loadDashboardData,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 16 : 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHealthScoreHero(isMobile),
                              SizedBox(height: isMobile ? 20 : 28),
                              _buildMetricsGrid(isMobile),
                              SizedBox(height: isMobile ? 20 : 28),
                              _buildAIInsightsSection(isMobile),
                              SizedBox(height: isMobile ? 20 : 28),
                              _buildRecentActivitySection(isMobile),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNavBar(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'myParivaar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2332),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (!isMobile) ...[
            _navButton(Icons.home_outlined, 'Home', '/home'),
            const SizedBox(width: 8),
            _navButton(Icons.account_balance_wallet_outlined, 'Expenses', '/expenses'),
            const SizedBox(width: 8),
            _navButton(Icons.pie_chart_outline, 'Budget', '/budget'),
            const SizedBox(width: 8),
            _navButton(Icons.savings_outlined, 'Savings', '/savings'),
            const SizedBox(width: 24),
          ],
          // Profile menu
          PopupMenuButton<String>(
            offset: const Offset(0, 45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF3B82F6),
                    child: const Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF64748B)),
                  ],
                ],
              ),
            ),
            onSelected: (value) {
              if (value == 'signout') {
                Provider.of<AuthService>(context, listen: false).signOut();
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, value);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '/profile', child: Row(children: [
                Icon(Icons.person_outline, size: 18), SizedBox(width: 12), Text('Profile'),
              ])),
              const PopupMenuItem(value: '/user-settings', child: Row(children: [
                Icon(Icons.settings_outlined, size: 18), SizedBox(width: 12), Text('Settings'),
              ])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'signout', child: Row(children: [
                Icon(Icons.logout, size: 18, color: Colors.red), SizedBox(width: 12),
                Text('Sign Out', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, String label, String route) {
    return TextButton.icon(
      onPressed: () => Navigator.pushReplacementNamed(context, route),
      icon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
      label: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEALTH SCORE HERO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHealthScoreHero(bool isMobile) {
    final score = _financialHealthScore;
    final scoreColor = _healthScoreColor(score);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                _buildScoreGauge(score, scoreColor),
                const SizedBox(height: 24),
                _buildPulseMetrics(isMobile),
              ],
            )
          : Row(
              children: [
                _buildScoreGauge(score, scoreColor),
                const SizedBox(width: 48),
                Expanded(child: _buildPulseMetrics(isMobile)),
              ],
            ),
    );
  }

  Widget _buildScoreGauge(int score, Color scoreColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _LightGaugePainter(
              score: score / 100,
              color: scoreColor,
              trackColor: const Color(0xFFE2E8F0),
              strokeWidth: 12,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: scoreColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _healthScoreLabel(score),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Financial Health Score',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildPulseMetrics(bool isMobile) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _pulseMetricChip(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Net Worth',
          value: _formatCurrency(_netWorth),
          color: const Color(0xFF3B82F6),
        ),
        _pulseMetricChip(
          icon: Icons.swap_vert_circle_outlined,
          label: 'Cash Flow',
          value: '${_monthlyCashFlow >= 0 ? '+' : ''}${_formatCurrency(_monthlyCashFlow)}',
          color: _monthlyCashFlow >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
        ),
        _pulseMetricChip(
          icon: Icons.savings_outlined,
          label: 'Savings Rate',
          value: '${_savingsRate.toStringAsFixed(0)}%',
          color: _savingsRate >= 20 ? const Color(0xFF22C55E) : const Color(0xFFF97316),
        ),
        _pulseMetricChip(
          icon: Icons.pie_chart_outline,
          label: 'Budget Used',
          value: _budgets.isEmpty ? 'Not Set' : '${(_budgetUsage * 100).toStringAsFixed(0)}%',
          color: _budgetUsage <= 0.8 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
        ),
      ],
    );
  }

  Widget _pulseMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METRICS GRID
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetricsGrid(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Money at a Glance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        isMobile
            ? Column(
                children: [
                  _buildCashFlowCard(),
                  const SizedBox(height: 12),
                  _buildBudgetCard(),
                  const SizedBox(height: 12),
                  _buildSavingsCard(),
                  const SizedBox(height: 12),
                  _buildInvestmentsCard(),
                  const SizedBox(height: 12),
                  _buildBillsCard(),
                  const SizedBox(height: 12),
                  _buildFamilyCard(),
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildCashFlowCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildBudgetCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSavingsCard()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildInvestmentsCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildBillsCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildFamilyCard()),
                    ],
                  ),
                ],
              ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required IconData icon,
    required Color accentColor,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(icon, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }

  // ── Cash Flow Card ─────────────────────────────────────────────────────────

  Widget _buildCashFlowCard() {
    return _metricCard(
      title: 'Monthly Cash Flow',
      icon: Icons.swap_vert_circle_outlined,
      accentColor: const Color(0xFF3B82F6),
      onTap: () => Navigator.pushReplacementNamed(context, '/expenses'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCurrency(_monthlyCashFlow),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _monthlyCashFlow >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 12),
          _cashFlowBar(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Income: ${_formatCurrency(_monthlyIncome)}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Spend: ${_formatCurrency(_monthlySpend)}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cashFlowBar() {
    final total = _monthlyIncome + _monthlySpend;
    final incomeRatio = total > 0 ? _monthlyIncome / total : 0.5;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Row(children: [
          Expanded(flex: (incomeRatio * 100).round(), child: Container(color: const Color(0xFF22C55E))),
          Expanded(flex: ((1 - incomeRatio) * 100).round(), child: Container(color: const Color(0xFFEF4444))),
        ]),
      ),
    );
  }

  // ── Budget Card ────────────────────────────────────────────────────────────

  Widget _buildBudgetCard() {
    return _metricCard(
      title: 'Budget Tracker',
      icon: Icons.pie_chart_outline,
      accentColor: const Color(0xFFF59E0B),
      onTap: () => Navigator.pushReplacementNamed(context, '/budget'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_budgetsOnTrack',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
              ),
              Text(
                ' of ${_budgets.length}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _budgetsOnTrack == _budgets.length
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _budgetsOnTrack == _budgets.length ? 'All on track!' : '$_budgetRiskCount at risk',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _budgetsOnTrack == _budgets.length
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _budgetUsage.clamp(0, 1),
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              color: _budgetUsage > 0.9 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_budgetUsage * 100).toStringAsFixed(0)}% of total budget used',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  // ── Savings Card ───────────────────────────────────────────────────────────

  Widget _buildSavingsCard() {
    return _metricCard(
      title: 'Savings Goals',
      icon: Icons.flag_outlined,
      accentColor: const Color(0xFF22C55E),
      onTap: () => Navigator.pushReplacementNamed(context, '/savings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_savingsGoalProgress.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag, size: 12, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      '${_savingsGoals.length} goal${_savingsGoals.length != 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_savingsGoalProgress / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              color: const Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Progress towards all goals',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  // ── Investments Card ───────────────────────────────────────────────────────

  Widget _buildInvestmentsCard() {
    return _metricCard(
      title: 'Investments',
      icon: Icons.query_stats,
      accentColor: const Color(0xFF8B5CF6),
      onTap: () => Navigator.pushReplacementNamed(context, '/investments'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCurrency(_totalInvestedValue),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _totalInvestmentReturns >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 18,
                color: _totalInvestmentReturns >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 6),
              Text(
                '${_totalInvestmentReturns >= 0 ? '+' : ''}${_formatCurrency(_totalInvestmentReturns)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _totalInvestmentReturns >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_investments.length} asset${_investments.length != 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bills Card ─────────────────────────────────────────────────────────────

  Widget _buildBillsCard() {
    return _metricCard(
      title: 'Upcoming Bills',
      icon: Icons.receipt_long_outlined,
      accentColor: const Color(0xFFEF4444),
      onTap: () => Navigator.pushReplacementNamed(context, '/bills'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCurrency(_upcomingBillsTotal),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${_upcomingBills.length} upcoming',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              if (_overdueBillsCount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                      const SizedBox(width: 4),
                      Text(
                        '$_overdueBillsCount overdue',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Family Card ────────────────────────────────────────────────────────────

  Widget _buildFamilyCard() {
    return _metricCard(
      title: 'Family Spending',
      icon: Icons.family_restroom_outlined,
      accentColor: const Color(0xFF14B8A6),
      onTap: () => Navigator.pushReplacementNamed(context, '/kids-dashboard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCurrency(_kidsSpendingThisMonth + _parentsSpendingThisMonth),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.child_care, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                'Kids: ${_formatCurrency(_kidsSpendingThisMonth)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.elderly, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                'Parents: ${_formatCurrency(_parentsSpendingThisMonth)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI INSIGHTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAIInsightsSection(bool isMobile) {
    if (_aiInsights.isEmpty && !_aiInsightsLoading) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Smart Insights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _aiInsightsLoading
            ? const Center(child: CircularProgressIndicator())
            : SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _aiInsights.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _aiInsightCard(_aiInsights[index]),
                ),
              ),
      ],
    );
  }

  Widget _aiInsightCard(_AIInsight insight) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: insight.color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: insight.color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(insight.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: insight.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            insight.message,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECENT ACTIVITY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRecentActivitySection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/expenses'),
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: _recentExpenses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No recent transactions',
                          style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentExpenses.take(8).length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                  itemBuilder: (context, index) => _activityRow(_recentExpenses[index]),
                ),
        ),
      ],
    );
  }

  Widget _activityRow(Expense expense) {
    final isIncome = expense.category.toLowerCase() == 'income' ||
        expense.category.toLowerCase() == 'salary';
    final emoji = CategoryEmoji.getCategoryEmoji(expense.category);
    final now = DateTime.now();
    final diff = now.difference(expense.date);

    String timeAgo;
    if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      timeAgo = 'Yesterday';
    } else if (diff.inDays < 7) {
      timeAgo = '${diff.inDays}d ago';
    } else {
      timeAgo = '${expense.date.day}/${expense.date.month}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isIncome ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_capitalize(expense.category)} • $timeAgo',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}${_formatCurrency(expense.amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isIncome ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOADING & ERROR STATES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your financial data...', style: TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class _AIInsight {
  final String emoji;
  final String title;
  final String message;
  final Color color;

  const _AIInsight({
    required this.emoji,
    required this.title,
    required this.message,
    required this.color,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

/// Light theme gauge painter with visible track
class _LightGaugePainter extends CustomPainter {
  final double score;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  const _LightGaugePainter({
    required this.score,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;
    const startAngle = -math.pi * 0.75;
    const totalSweep = math.pi * 1.5;

    // Track (background arc)
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      trackPaint,
    );

    // Filled arc
    final fillPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep * score.clamp(0, 1),
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_LightGaugePainter old) =>
      old.score != score || old.color != color || old.trackColor != trackColor;
}
