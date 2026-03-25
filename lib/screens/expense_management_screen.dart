import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/family_service.dart';
import '../models/expense.dart';
import '../models/budget.dart';
import '../widgets/app_header.dart';
import '../widgets/tag_input_section.dart';
import '../widgets/tag_wrap.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/tag_utils.dart';
import '../services/ai_service.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() =>
      _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  final ExpenseService _expenseService = ExpenseService();
  List<Expense> _expenses = [];
  bool _isLoading = true;
  String? _error;
  String? _errorDiagnostics;
  String _searchQuery = '';
  final BudgetService _budgetService = BudgetService();
  List<Budget> _budgets = [];

  // AI Smart Insights
  bool _loadingInsights = false;
  String? _smartInsights;
  String? _smartInsightsError;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final idToken = await authService.getIdToken();
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: authService.supabaseUrl,
        idToken: idToken,
      );

      // Load budgets for the web budget status card (optional)
      List<Budget> budgets = [];
      try {
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        budgets = await _budgetService.getBudgets(
          supabaseUrl: authService.supabaseUrl,
          idToken: idToken,
          month: month,
        );
      } catch (_) {
        // Budget loading is optional; proceed without it
      }

      if (mounted) {
        setState(() {
          _expenses = expenses;
          _budgets = budgets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorDiagnostics = e is ExpenseException
              ? e.diagnostics
              : 'Exception type: ${e.runtimeType}\n$e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addExpense() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditExpenseScreen(),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _editExpense(Expense expense) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditExpenseScreen(expense: expense),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content:
            Text('Are you sure you want to delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _expenseService.deleteExpense(
        expenseId: expense.id,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      _loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: $e')),
        );
      }
    }
  }

  String _formatCurrency(double amount) {
    return '₹${amount.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final viewMode = context.watch<ViewModeProvider>().mode;
    if (kIsWeb && viewMode == ViewMode.desktop) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expenses',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track and manage your spending',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addExpense,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadExpenses,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(AppIcons.error, size: 32, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Error loading expenses',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.errorDark)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                border: Border.all(color: AppColors.errorLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _errorDiagnostics ?? _error!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Diagnostic info above is selectable — long-press to copy.',
              style: TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadExpenses,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.receiptOutlined,
                size: 64, color: AppColors.grey400),
            const SizedBox(height: 16),
            Text('No expenses yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Tap the + button to add your first expense'),
          ],
        ),
      );
    }

    // Group expenses by month
    final groupedExpenses = <String, List<Expense>>{};
    for (final expense in _expenses) {
      final monthKey =
          '${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}';
      groupedExpenses.putIfAbsent(monthKey, () => []).add(expense);
    }
    final now = DateTime.now();
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    return ListView.builder(
      itemCount: groupedExpenses.length,
      itemBuilder: (context, index) {
        final monthKey = groupedExpenses.keys.elementAt(index);
        final monthExpenses = groupedExpenses[monthKey]!;
        final totalAmount =
            monthExpenses.fold<double>(0, (sum, e) => sum + e.amount);

        final monthName = _getMonthName(monthKey);

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            initiallyExpanded: monthKey == currentMonthKey,
            title: Text(monthName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${monthExpenses.length} transactions • ${_formatCurrency(totalAmount)}'),
            children: monthExpenses
                .map((expense) => _buildExpenseItem(expense))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildExpenseItem(Expense expense) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.getCategoryColor(expense.category),
        child: Icon(_getCategoryIcon(expense.category), size: 20),
      ),
      title: Text(expense.description),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${expense.category} • ${_formatDate(expense.date)}'),
          if (expense.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            TagWrap(tags: expense.tags),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatCurrency(expense.amount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (expense.source == 'email')
            const Icon(AppIcons.email, size: 16, color: AppColors.grey600),
        ],
      ),
      onTap: () => _editExpense(expense),
      onLongPress: () => _deleteExpense(expense),
    );
  }

  IconData _getCategoryIcon(String category) {
    return AppIcons.getCategoryIcon(category);
  }

  String _getMonthName(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    return '${monthNames[month - 1]} $year';
  }

  // ── Web (Desktop) Layout ─────────────────────────────────────────────────

  Widget _buildWebLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildWebError(context)
              : _buildWebContent(context, isDark, theme, primary),
    );
  }

  Widget _buildWebError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.error, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Error loading expenses',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          SelectableText(_errorDiagnostics ?? _error ?? '',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadExpenses,
            icon: const Icon(AppIcons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent(
      BuildContext context, bool isDark, ThemeData theme, Color primary) {
    final filtered = _filteredExpenses;
    final previousMonthSpend = _previousMonthSpend;
    final spendDelta = _monthlySpendTotal - previousMonthSpend;
    final spendDeltaPct = previousMonthSpend > 0
        ? (spendDelta.abs() / previousMonthSpend) * 100
        : 0.0;

    return RefreshIndicator(
      onRefresh: _loadExpenses,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Expense Analysis',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Detailed breakdown of your spending habits',
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _webTabChip(
                            label: 'Current Month',
                            icon: Icons.calendar_month,
                            active: true,
                          ),
                          const SizedBox(width: 8),
                          _webTabChip(
                            label: 'Historical Performance',
                            icon: Icons.history,
                            active: false,
                            comingSoon: true,
                          ),
                          const SizedBox(width: 8),
                          _webTabChip(
                            label: 'Spending Analytics',
                            icon: Icons.insights,
                            active: false,
                            comingSoon: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Expense'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _webStatCard(
                  isDark: isDark,
                  primary: primary,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Total Spent this Month',
                  value: '${_fmtCurrency(_monthlySpendTotal)}.00',
                  trendLabel:
                      '${spendDelta >= 0 ? '+' : '-'}${spendDeltaPct.toStringAsFixed(0)}%',
                  trendUp: spendDelta >= 0,
                  footer: spendDelta == 0
                      ? 'No change from last month'
                      : '${_fmtCurrency(spendDelta.abs())} ${spendDelta >= 0 ? 'higher' : 'lower'} than last month',
                )),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildSmartInsightsCard(isDark, primary),
                ),
                const SizedBox(width: 20),
                Expanded(child: _webCategoryDistCard(isDark, primary)),
              ],
            ),
            const SizedBox(height: 30),
            // Pending review banner
            if (_pendingEmailExpenses.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.pending_actions, color: Colors.amber, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    '${_pendingEmailExpenses.length} email transaction(s) pending your review',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            // Expense Category Widgets
            _buildExpenseCategoryGrid(isDark),
            const SizedBox(height: 30),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildBudgetStatusCard(isDark, primary)),
                const SizedBox(width: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2836),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Category Trend',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              'Last 5 Months',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _trendBar(0.42, primary.withOpacity(0.45)),
                            const SizedBox(width: 6),
                            _trendBar(0.58, primary.withOpacity(0.6)),
                            const SizedBox(width: 6),
                            _trendBar(0.5, primary.withOpacity(0.45)),
                            const SizedBox(width: 6),
                            _trendBar(0.72, primary.withOpacity(0.8)),
                            const SizedBox(width: 6),
                            _trendBar(0.9, primary),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Icon(Icons.close_rounded,
                                size: 12, color: Colors.red),
                            SizedBox(width: 6),
                            Text(
                              'Advanced trend analytics coming soon',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCategoryGrid(bool isDark) {
    const categories = [
      _ExpenseCategoryItem(
        label: 'Entertainment',
        icon: Icons.movie_outlined,
        color: Color(0xFFE91E63),
        bgColor: Color(0xFFFCE4EC),
      ),
      _ExpenseCategoryItem(
        label: 'Groceries',
        icon: Icons.shopping_cart_outlined,
        color: Color(0xFF4CAF50),
        bgColor: Color(0xFFE8F5E9),
      ),
      _ExpenseCategoryItem(
        label: 'Mental Wellness',
        icon: Icons.self_improvement,
        color: Color(0xFF7C4DFF),
        bgColor: Color(0xFFEDE7F6),
      ),
      _ExpenseCategoryItem(
        label: 'Physical Wellness',
        icon: Icons.fitness_center,
        color: Color(0xFFFF5722),
        bgColor: Color(0xFFFBE9E7),
      ),
      _ExpenseCategoryItem(
        label: 'Party',
        icon: Icons.celebration_outlined,
        color: Color(0xFFFF9800),
        bgColor: Color(0xFFFFF3E0),
      ),
      _ExpenseCategoryItem(
        label: 'Personal Care',
        icon: Icons.spa_outlined,
        color: Color(0xFFEC407A),
        bgColor: Color(0xFFFCE4EC),
      ),
      _ExpenseCategoryItem(
        label: 'Pet Care',
        icon: Icons.pets_outlined,
        color: Color(0xFF8D6E63),
        bgColor: Color(0xFFEFEBE9),
      ),
      _ExpenseCategoryItem(
        label: 'Senior Care',
        icon: Icons.elderly_outlined,
        color: Color(0xFF00897B),
        bgColor: Color(0xFFE0F2F1),
      ),
      _ExpenseCategoryItem(
        label: 'Education',
        icon: Icons.school_outlined,
        color: Color(0xFF1565C0),
        bgColor: Color(0xFFE3F2FD),
      ),
      _ExpenseCategoryItem(
        label: 'Vacation',
        icon: Icons.flight_outlined,
        color: Color(0xFF00ACC1),
        bgColor: Color(0xFFE0F7FA),
      ),
      _ExpenseCategoryItem(
        label: 'Convenience Food',
        icon: Icons.fastfood_outlined,
        color: Color(0xFFEF6C00),
        bgColor: Color(0xFFFFF8E1),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spending Categories',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a category to view or add expenses',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final count = _getCategoryExpenseCount(cat.label);
              final total = _getCategoryExpenseTotal(cat.label);
              return _buildCategoryTile(cat, count, total);
            },
          ),
        ],
      ),
    );
  }

  int _getCategoryExpenseCount(String categoryLabel) {
    final now = DateTime.now();
    final lbl = categoryLabel.toLowerCase();
    return _expenses.where((e) {
      if (e.date.year != now.year || e.date.month != now.month) return false;
      return _matchesCategory(e, lbl);
    }).length;
  }

  double _getCategoryExpenseTotal(String categoryLabel) {
    final now = DateTime.now();
    final lbl = categoryLabel.toLowerCase();
    return _expenses.where((e) {
      if (e.date.year != now.year || e.date.month != now.month) return false;
      return _matchesCategory(e, lbl);
    }).fold(0.0, (s, e) => s + e.amount);
  }

  bool _matchesCategory(Expense e, String lbl) {
    final cat = e.category.toLowerCase();
    final desc = e.description.toLowerCase();
    final tags = e.tags.map((t) => t.toLowerCase()).join(' ');
    final blob = '$cat $desc $tags';

    switch (lbl) {
      case 'entertainment':
        return cat == 'entertainment' || blob.contains('movie') || blob.contains('netflix') || blob.contains('concert') || blob.contains('game');
      case 'groceries':
        return cat == 'groceries' || cat == 'grocery' || blob.contains('grocery') || blob.contains('supermarket') || blob.contains('vegetables');
      case 'mental wellness':
        return blob.contains('therapy') || blob.contains('counseling') || blob.contains('meditation') || blob.contains('mental') || blob.contains('wellness app');
      case 'physical wellness':
        return blob.contains('gym') || blob.contains('fitness') || blob.contains('yoga') || blob.contains('sports') || blob.contains('workout');
      case 'party':
        return blob.contains('party') || blob.contains('celebration') || blob.contains('birthday') || blob.contains('event');
      case 'personal care':
        return blob.contains('salon') || blob.contains('spa') || blob.contains('grooming') || blob.contains('haircut') || blob.contains('beauty');
      case 'pet care':
        return blob.contains('pet') || blob.contains('vet') || blob.contains('dog') || blob.contains('cat') || blob.contains('animal');
      case 'senior care':
        return blob.contains('senior') || blob.contains('elderly') || blob.contains('parent care') || blob.contains('old age');
      case 'education':
        return cat == 'education' || blob.contains('school') || blob.contains('tuition') || blob.contains('course') || blob.contains('book') || blob.contains('training');
      case 'vacation':
        return blob.contains('travel') || blob.contains('vacation') || blob.contains('trip') || blob.contains('hotel') || blob.contains('flight') || blob.contains('holiday');
      case 'convenience food':
        return blob.contains('swiggy') || blob.contains('zomato') || blob.contains('food delivery') || blob.contains('takeaway') || blob.contains('fast food') || blob.contains('convenience food');
      default:
        return cat == lbl;
    }
  }

  Widget _buildCategoryTile(_ExpenseCategoryItem cat, int count, double total) {
    return Material(
      color: cat.bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Navigate to add expense with this category pre-selected
          _addExpense();
        },
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon, size: 28, color: cat.color),
                    const SizedBox(height: 6),
                    Text(
                      cat.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cat.color,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        _fmtCurrency(total),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cat.color.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cat.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebTransactionRow(Expense expense, bool isDark) {
    final isIncome = expense.category.toLowerCase() == 'income' ||
        expense.category.toLowerCase() == 'salary';
    final isPending = expense.source == 'email' && !expense.isApproved;
    final bgColor = AppColors.getCategoryColor(expense.category);
    final iconColor = AppColors.getCategoryIconColor(expense.category);
    final d = expense.date;
    final dateStr = '${_webMonthAbbr(d.month)} ${d.day}, ${d.year}';
    final rowBorder =
        BorderSide(color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9));
    return InkWell(
      onTap: () => _editExpense(expense),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(top: rowBorder),
          color: isPending ? Colors.amber.withOpacity(0.04) : null,
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(AppIcons.getCategoryIcon(expense.category),
                size: 22, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.description,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_webCapitalize(expense.category),
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      expense.source == 'email'
                          ? Icons.email_outlined
                          : expense.source == 'csv'
                              ? Icons.upload_file_outlined
                              : Icons.qr_code_2,
                      size: 12,
                      color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(_paymentMethodLabel(expense.source),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (isPending) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('\u23F3 Pending Approval',
                          style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                // Show telemetry chips from notes for email transactions
                if (expense.source == 'email' && expense.notes != null && expense.notes!.contains('|')) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: _buildTelemetryChips(expense.notes!, isDark),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '- '}${_fmtCurrency(expense.amount)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isIncome ? AppColors.success : AppColors.error),
              ),
              const SizedBox(height: 4),
              Text(dateStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              if (isPending) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _approveRejectButton(
                      icon: Icons.check_circle_outline,
                      label: 'Approve',
                      color: AppColors.success,
                      onTap: () => _approveExpense(expense),
                    ),
                    const SizedBox(width: 8),
                    _approveRejectButton(
                      icon: Icons.cancel_outlined,
                      label: 'Reject',
                      color: AppColors.error,
                      onTap: () => _rejectExpense(expense),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildBudgetStatusCard(bool isDark, Color primary) {
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final monthlySpend = _monthlySpendTotal;
    final hasData = totalBudget > 0;
    final ratio = hasData ? (monthlySpend / totalBudget).clamp(0.0, 1.0) : 0.0;
    final withinBudget = !hasData || monthlySpend <= totalBudget;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Weekly Budget Status',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                hasData
                    ? (withinBudget
                        ? 'You are within your spending limit.'
                        : 'You have exceeded your budget.')
                    : 'Set up budgets to track spending here.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13),
              ),
              if (hasData) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    color: withinBudget ? Colors.white : Colors.red[200],
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmtCurrency(monthlySpend)} of ${_fmtCurrency(totalBudget)}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/budget'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Edit Budget',
                      style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            withinBudget
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            color: Colors.white,
            size: 32,
          ),
        ),
      ]),
    );
  }

  Widget _webStatCard({
    required bool isDark,
    required Color primary,
    required IconData icon,
    required String label,
    required String value,
    required String trendLabel,
    required bool trendUp,
    required String footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: primary, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: trendUp
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  children: [
                    Icon(
                      trendUp ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: trendUp ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trendLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: trendUp ? AppColors.error : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            footer,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _webCategoryDistCard(bool isDark, Color primary) {
    final totals = <String, double>{};
    for (final e in _filteredExpenses) {
      if (e.category.toLowerCase() != 'income' &&
          e.category.toLowerCase() != 'salary') {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
    }
    final grand = totals.values.fold(0.0, (s, v) => s + v);
    final sorted = (totals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .toList();
    final colors = [primary, Colors.amber, Colors.green, Colors.red];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Category Distribution',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border(
                  top: BorderSide(color: colors[0], width: 12),
                  right: BorderSide(color: colors[1], width: 12),
                  bottom: BorderSide(color: colors[2], width: 12),
                  left: BorderSide(color: colors[3], width: 12),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtCurrency(grand),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (sorted.isEmpty)
            Text('No data', style: TextStyle(color: Colors.grey[400]))
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final cat = entry.value;
                final pct = grand > 0
                    ? '${(cat.value / grand * 100).toStringAsFixed(0)}%'
                    : '0%';
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${_webCapitalize(cat.key)} ($pct)',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ]);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _trendBar(double heightFactor, Color color) {
    return Expanded(
      child: Container(
        height: 90,
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          widthFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchSmartInsights() async {
    setState(() {
      _loadingInsights = true;
      _smartInsightsError = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _smartInsights = result['analysis'] as String?;
        _loadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInsights = false;
        _smartInsightsError = e.toString();
      });
    }
  }

  Widget _buildSmartInsightsCard(bool isDark, Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 20),
            const SizedBox(width: 8),
            const Text('Smart Insights',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_loadingInsights)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              InkWell(
                onTap: _fetchSmartInsights,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _smartInsights != null ? 'Refresh' : 'Analyze',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (_smartInsightsError != null)
            Text(_smartInsightsError!, style: const TextStyle(color: AppColors.error, fontSize: 12))
          else if (_smartInsights != null)
            Text(_smartInsights!, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4))
          else
            Text(
              'Tap Analyze for AI-powered spending insights.',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }

  Widget _webComingSoonCard({
    required bool isDark,
    required Color primary,
    required String title,
    required IconData icon,
    required String message,
    bool dark = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1E2836)
            : (isDark ? AppColors.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: dark ? Colors.white70 : primary, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: dark ? Colors.white : null)),
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Feature coming soon',
              child: Icon(Icons.close_rounded, size: 13, color: Colors.red),
            ),
          ]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  fontSize: 12,
                  color: dark ? Colors.white54 : Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _filterChip(bool isDark, String label, IconData icon) {
    return Tooltip(
      message: 'Feature coming soon',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(width: 6),
          Icon(Icons.expand_more, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 4),
          const Icon(Icons.close_rounded, size: 11, color: Colors.red),
        ]),
      ),
    );
  }

  // ── Computed helpers ──────────────────────────────────────────────────────

  List<Expense> get _filteredExpenses {
    final now = DateTime.now();
    return _expenses.where((e) {
      // Show only current month expenses
      final inPeriod = e.date.year == now.year && e.date.month == now.month;
      if (!inPeriod) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return e.description.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.tags.any((tag) => tag.toLowerCase().contains(q));
      }
      return true;
    }).toList();
  }

  List<Expense> get _pendingEmailExpenses =>
      _filteredExpenses.where((e) => e.source == 'email' && !e.isApproved).toList();

  double get _monthlySpendTotal {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get _previousMonthSpend {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 1);
    return _expenses
        .where((e) =>
            e.date.year == previous.year &&
            e.date.month == previous.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (s, e) => s + e.amount);
  }

  String _paymentMethodLabel(String source) {
    if (source == 'email') return 'Email Imported';
    if (source == 'csv') return 'CSV Imported';
    return 'Manual Entry';
  }

  String _fmtCurrency(double amount) {
    final formatted = amount.abs().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '\u20B9$formatted';
  }

  String _webCapitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _webMonthAbbr(int month) {
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

  List<Widget> _buildTelemetryChips(String notes, bool isDark) {
    // Notes format: "HDFC Bank | Credit Card | Card **4860 | VPA: xyz@upi | AI from email [INBOX]"
    final segments = notes.split('|').map((s) => s.trim()).toList();
    final chips = <Widget>[];
    for (final seg in segments) {
      // Skip the "AI/Regex from email@addr [folder]" suffix
      if (seg.contains(' from ') && seg.contains('[')) continue;
      if (seg.isEmpty) continue;

      IconData? icon;
      Color? chipColor;
      if (seg.contains('Bank')) {
        icon = Icons.account_balance_outlined;
        chipColor = Colors.blue;
      } else if (seg.contains('Credit Card')) {
        icon = Icons.credit_card;
        chipColor = Colors.deepPurple;
      } else if (seg.contains('Debit Card')) {
        icon = Icons.credit_card_outlined;
        chipColor = Colors.teal;
      } else if (seg.startsWith('UPI') || seg.startsWith('VPA')) {
        icon = Icons.phone_android;
        chipColor = Colors.green;
      } else if (seg.startsWith('Card')) {
        icon = Icons.credit_card;
        chipColor = Colors.indigo;
      } else if (seg.startsWith('Acct')) {
        icon = Icons.account_balance_wallet_outlined;
        chipColor = Colors.orange;
      } else if (seg.startsWith('Ref')) {
        icon = Icons.tag;
        chipColor = Colors.grey;
      } else if (seg.contains('NEFT') || seg.contains('IMPS') || seg.contains('RTGS')) {
        icon = Icons.swap_horiz;
        chipColor = Colors.brown;
      } else {
        continue; // Skip unknown segments
      }

      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: (chipColor ?? Colors.grey).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 10, color: chipColor),
              if (icon != null) const SizedBox(width: 3),
              Text(seg, style: TextStyle(fontSize: 9, color: chipColor, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }
    return chips;
  }

  Widget _approveRejectButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _approveExpense(Expense expense) async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await _expenseService.approveTransaction(
        expenseId: expense.id,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction approved')),
        );
      }
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _rejectExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Transaction'),
        content: Text('Reject "${expense.description}"? This will mark it as rejected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await _expenseService.rejectTransaction(
        expenseId: expense.id,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction rejected')),
        );
      }
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _webTabChip({
    required String label,
    required IconData icon,
    required bool active,
    bool comingSoon = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? const Color(0xFF0D7FF2) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: active ? const Color(0xFF0D7FF2) : null),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF0D7FF2) : null,
            ),
          ),
          if (comingSoon) ...[
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded, size: 11, color: Colors.red),
          ],
        ],
      ),
    );
  }
}

class _ExpenseCategoryItem {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _ExpenseCategoryItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class AddEditExpenseScreen extends StatefulWidget {
  final Expense? expense;

  const AddEditExpenseScreen({super.key, this.expense});

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();

  List<String> _tagSuggestions = [];
  String _selectedCategory = 'food';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isCategorizing = false;

  @override
  void initState() {
    super.initState();
    if (widget.expense != null) {
      _amountController.text = widget.expense!.amount.toStringAsFixed(2);
      _notesController.text = widget.expense!.notes ?? '';
      _tagsController.text = joinTags(widget.expense!.tags);
      _selectedCategory = widget.expense!.category;
      _selectedDate = widget.expense!.date;
    }
    _loadTagSuggestions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadTagSuggestions() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final familyService = FamilyService(
        supabaseUrl: authService.supabaseUrl,
        authService: authService,
      );
      final members = await familyService.fetchMembers();
      if (!mounted) return;
      setState(() {
        _tagSuggestions = members
            .map((member) => member.displayLabel.trim())
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    } catch (_) {
      // Tag suggestions are optional.
    }
  }

  Future<void> _autoCategorize() async {
    final description = _notesController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a note first so AI can suggest a category')),
      );
      return;
    }

    setState(() => _isCategorizing = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().categorizeExpense(
        description: description,
        amount: double.tryParse(_amountController.text),
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      final category = (result['category'] as String?)?.toLowerCase() ?? '';
      const validCategories = ['food', 'transport', 'shopping', 'utilities', 'entertainment', 'other'];
      setState(() {
        _selectedCategory = validCategories.contains(category) ? category : 'other';
        _isCategorizing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCategorizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto-categorize failed: $e')),
      );
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'New Expense',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Amount Display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            '\$',
                            style: TextStyle(
                              fontSize: 40,
                              color: Colors.grey,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _amountController.text.isEmpty
                              ? '0.00'
                              : _amountController.text,
                          style: const TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Note field
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'Add a note...',
                        hintStyle: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 32),

                    TagInputSection(
                      controller: _tagsController,
                      suggestions: _tagSuggestions,
                      helperText:
                          'Use family members or keywords like mom, school, medical, trip.',
                    ),

                    const SizedBox(height: 28),

                    // Category Selection
                    Row(
                      children: [
                        Text(
                          'SELECT CATEGORY',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (_isCategorizing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          InkWell(
                            onTap: _autoCategorize,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 14, color: Colors.deepPurple),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Auto',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Category Grid
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.0,
                      children: [
                        _buildCategoryButton(
                            'food', 'Food', AppIcons.food, Colors.orange),
                        _buildCategoryButton('transport', 'Transport',
                            AppIcons.transport, Colors.blue),
                        _buildCategoryButton('shopping', 'Shopping',
                            AppIcons.shopping, Colors.pink),
                        _buildCategoryButton('utilities', 'Bills',
                            AppIcons.utilities, Colors.green),
                        _buildCategoryButton('entertainment', 'Entertain',
                            AppIcons.entertainment, Colors.purple),
                        _buildCategoryButton(
                            'other', 'Others', Icons.more_horiz, Colors.grey),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Bottom options row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Today button
                        InkWell(
                          onTap: _selectDate,
                          child: Row(
                            children: [
                              Icon(AppIcons.calendar,
                                  color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _selectedDate.day == DateTime.now().day &&
                                        _selectedDate.month ==
                                            DateTime.now().month &&
                                        _selectedDate.year ==
                                            DateTime.now().year
                                    ? 'Today'
                                    : '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Add Receipt button
                        InkWell(
                          onTap: () {
                            // TODO: Add receipt upload functionality
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Receipt upload coming soon!')),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(Icons.camera_alt_outlined,
                                  color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Add Receipt',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Save Button
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _isLoading ? null : () => _showAmountDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1D2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Save Transaction',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.check, size: 20),
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

  Widget _buildCategoryButton(
      String category, String label, IconData icon, Color color) {
    final isSelected = _selectedCategory == category;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = category;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 36,
              color: isSelected ? color : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? color : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAmountDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Amount'),
        content: TextFormField(
          controller: _amountController,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '\$ ',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          onFieldSubmitted: (value) {
            Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _amountController.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {});
      // Now save the expense
      await _saveExpenseWithValidation();
    }
  }

  Future<void> _saveExpenseWithValidation() async {
    // Validate amount
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final expenseService = ExpenseService();

      final description = _notesController.text.trim();
      final notes = _notesController.text.trim();
      final tags = parseTags(_tagsController.text);

      if (widget.expense == null) {
        // Create new expense
        await expenseService.createExpense(
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      } else {
        // Update existing expense
        await expenseService.updateExpense(
          expenseId: widget.expense!.id,
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.expense == null
                ? 'Expense added successfully'
                : 'Expense updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e')),
        );
      }
    }
  }
}
