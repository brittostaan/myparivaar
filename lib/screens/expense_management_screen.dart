import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import '../services/budget_service.dart';
import '../models/expense.dart';
import '../models/budget.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

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
  int _selectedPeriod = 2; // 0=Daily, 1=Weekly, 2=Monthly
  final BudgetService _budgetService = BudgetService();
  List<Budget> _budgets = [];

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
      floatingActionButton: FloatingActionButton(
        onPressed: _addExpense,
        child: const Icon(AppIcons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Expenses',
              avatarIcon: AppIcons.wallet,
            ),
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
      subtitle: Text('${expense.category} • ${_formatDate(expense.date)}'),
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Expense'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: ['Daily', 'Weekly', 'Monthly']
                        .asMap()
                        .entries
                        .map((e) => GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedPeriod = e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedPeriod == e.key
                                      ? (isDark
                                          ? AppColors.grey700
                                          : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  e.value,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedPeriod == e.key
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _selectedPeriod == e.key
                                        ? primary
                                        : Colors.grey[500],
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
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
                  child: _webComingSoonCard(
                    isDark: isDark,
                    primary: primary,
                    title: 'Smart Insights',
                    icon: Icons.lightbulb_outlined,
                    message:
                        'You spent more on dining this month. Personalized recommendations are under development.',
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(child: _webCategoryDistCard(isDark, primary)),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                    child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppColors.grey800
                            : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search, color: Colors.grey[400], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search transactions, merchants...',
                          hintStyle:
                              TextStyle(color: Colors.grey[400], fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                )),
                const SizedBox(width: 12),
                _filterChip(isDark, 'Member', Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                _filterChip(
                    isDark, 'Payment Method', Icons.credit_card_outlined),
                const SizedBox(width: 8),
                _filterChip(isDark, 'Category', Icons.category_outlined),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Feature coming soon',
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: const [
                      Icon(Icons.download_outlined, size: 18),
                      SizedBox(width: 4),
                      Icon(Icons.close_rounded, size: 11, color: Colors.red),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color:
                        isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent Transactions',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('${filtered.length} results',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('No transactions found',
                            style: TextStyle(color: Colors.grey[400])),
                      ),
                    )
                  else
                    ...filtered.map((e) => _buildWebTransactionRow(e, isDark)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: TextButton(
                        onPressed: _loadExpenses,
                        child: const Text('View More Transactions',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildWebTransactionRow(Expense expense, bool isDark) {
    final isIncome = expense.category.toLowerCase() == 'income' ||
        expense.category.toLowerCase() == 'salary';
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
        decoration: BoxDecoration(border: Border(top: rowBorder)),
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
                ]),
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
      final bool inPeriod;
      if (_selectedPeriod == 0) {
        inPeriod = e.date.year == now.year &&
            e.date.month == now.month &&
            e.date.day == now.day;
      } else if (_selectedPeriod == 1) {
        inPeriod = now.difference(e.date).inDays < 7;
      } else {
        inPeriod = e.date.year == now.year && e.date.month == now.month;
      }
      if (!inPeriod) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return e.description.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

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

  String _selectedCategory = 'food';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.expense != null) {
      _amountController.text = widget.expense!.amount.toStringAsFixed(2);
      _notesController.text = widget.expense!.notes ?? '';
      _selectedCategory = widget.expense!.category;
      _selectedDate = widget.expense!.date;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
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

                    const SizedBox(height: 60),

                    // Category Selection
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'SELECT CATEGORY',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[400],
                          letterSpacing: 1.2,
                        ),
                      ),
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

      if (widget.expense == null) {
        // Create new expense
        await expenseService.createExpense(
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
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
