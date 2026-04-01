import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../models/import_result.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/family_service.dart';
import '../services/import_service.dart';
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

  // Web: category filter & inline panels
  String? _selectedCategoryFilter;
  bool _showAddExpensePanel = false;
  bool _showImportPanel = false;
  bool _showHistoricalPanel = false;
  bool _showAnalyticsPanel = false;
  bool _showAIInsightsPanel = false;
  Expense? _selectedExpenseDetail;

  void _closeAllPanels() {
    _showAddExpensePanel = false;
    _showImportPanel = false;
    _showHistoricalPanel = false;
    _showAnalyticsPanel = false;
    _showAIInsightsPanel = false;
    _selectedExpenseDetail = null;
  }

  bool get _anyPanelOpen =>
      _showAddExpensePanel || _showImportPanel || _showHistoricalPanel ||
      _showAnalyticsPanel || _showAIInsightsPanel || _selectedExpenseDetail != null;

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
    // On web desktop, show inline detail panel instead of navigating
    if (kIsWeb && MediaQuery.of(context).size.width >= 900) {
      setState(() {
        _closeAllPanels();
        _selectedExpenseDetail = expense;
      });
      return;
    }
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
            // ── Action Pane ──────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Expenses',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildActionChip(
                        icon: Icons.auto_awesome,
                        label: 'AI Insights',
                        onTap: () => Navigator.of(context).pushNamed('/ai-features'),
                      ),
                      const SizedBox(width: 8),
                      _buildActionChip(
                        icon: Icons.upload_file,
                        label: 'Import',
                        onTap: () => Navigator.of(context).pushNamed('/csv-import'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _addExpense,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Expense'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _buildViewTab('Current Month', Icons.calendar_month, true),
                      const SizedBox(width: 6),
                      _buildViewTab('Historical', Icons.history, false, comingSoon: true),
                      const SizedBox(width: 6),
                      _buildViewTab('Analytics', Icons.insights, false, comingSoon: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
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

  // ── Unified modern control pill ──────────────────────────────────────────

  Widget _buildControlPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
    bool locked = false,
  }) {
    final bg = active ? color : color.withOpacity(0.08);
    final fg = active ? Colors.white : color;
    return Tooltip(
      message: locked ? 'Coming soon' : '',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        elevation: active ? 2 : 0,
        shadowColor: color.withOpacity(0.3),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 11, color: fg.withOpacity(0.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Keep legacy methods as thin wrappers for mobile layout
  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return _buildControlPill(icon: icon, label: label, color: Colors.grey, onTap: onTap);
  }

  Widget _buildViewTab(String label, IconData icon, bool active, {bool comingSoon = false}) {
    return _buildControlPill(
      icon: icon,
      label: label,
      color: AppColors.primary,
      active: active,
      locked: comingSoon,
      onTap: () {},
    );
  }

  // Kept for backwards compatibility — unused references
  Widget _buildViewTabLegacy(String label, IconData icon, bool active, {bool comingSoon = false}) {
    return Tooltip(
      message: comingSoon ? 'Coming soon' : '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border(bottom: BorderSide(color: AppColors.primary, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? AppColors.primary : Colors.grey[400]),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.primary : Colors.grey[500],
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_outline, size: 11, color: Colors.grey[400]),
            ],
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
    final filtered = _webFilteredExpenses;
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
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Expense',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildControlPill(
                        icon: Icons.calendar_month,
                        label: 'Current Month',
                        color: const Color(0xFF2196F3),
                        active: true,
                        onTap: () {},
                      ),
                      _buildControlPill(
                        icon: _showHistoricalPanel ? Icons.close_rounded : Icons.history,
                        label: _showHistoricalPanel ? 'Close' : 'Historical Performance',
                        color: const Color(0xFF7C4DFF),
                        active: _showHistoricalPanel,
                        onTap: () => setState(() {
                          final opening = !_showHistoricalPanel;
                          _closeAllPanels();
                          _showHistoricalPanel = opening;
                        }),
                      ),
                      _buildControlPill(
                        icon: _showAnalyticsPanel ? Icons.close_rounded : Icons.insights,
                        label: _showAnalyticsPanel ? 'Close' : 'Spending Analytics',
                        color: const Color(0xFF00ACC1),
                        active: _showAnalyticsPanel,
                        onTap: () => setState(() {
                          final opening = !_showAnalyticsPanel;
                          _closeAllPanels();
                          _showAnalyticsPanel = opening;
                        }),
                      ),
                      _buildControlPill(
                        icon: _showAIInsightsPanel ? Icons.close_rounded : Icons.auto_awesome,
                        label: _showAIInsightsPanel ? 'Close' : 'AI Insights',
                        color: const Color(0xFF9C27B0),
                        active: _showAIInsightsPanel,
                        onTap: () => setState(() {
                          final opening = !_showAIInsightsPanel;
                          _closeAllPanels();
                          _showAIInsightsPanel = opening;
                        }),
                      ),
                      _buildControlPill(
                        icon: _showImportPanel ? Icons.close_rounded : Icons.upload_file,
                        label: _showImportPanel ? 'Close' : 'Import',
                        color: const Color(0xFF43A047),
                        active: _showImportPanel,
                        onTap: () => setState(() {
                          final opening = !_showImportPanel;
                          _closeAllPanels();
                          _showImportPanel = opening;
                        }),
                      ),
                      _buildControlPill(
                        icon: _showAddExpensePanel ? Icons.close_rounded : Icons.add_rounded,
                        label: _showAddExpensePanel ? 'Close' : 'Add Expense',
                        color: const Color(0xFFFF6D00),
                        active: _showAddExpensePanel,
                        onTap: () => setState(() {
                          final opening = !_showAddExpensePanel;
                          _closeAllPanels();
                          _showAddExpensePanel = opening;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Three info cards ─────────────────────────────────────
            _buildThreeInfoCards(isDark, primary),
            const SizedBox(height: 24),
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
            // Expense Category Chips (now filter transactions)
            _buildExpenseCategoryGrid(isDark),
            // Clear filter chip
            if (_selectedCategoryFilter != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _selectedCategoryFilter = null),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text('Clear filter: $_selectedCategoryFilter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Two-column layout: Transaction List (left) + Side Panel (right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Transaction List
                Expanded(
                  child: _buildWebTransactionList(filtered, isDark, primary),
                ),
                // Right: Inline Add Expense Panel
                if (_showAddExpensePanel) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildInlineAddExpensePanel(isDark, primary),
                  ),
                ],
                // Right: Inline Import Panel
                if (_showImportPanel) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildInlineImportPanel(isDark, primary),
                  ),
                ],
                // Right: Inline Transaction Detail Panel
                if (_selectedExpenseDetail != null) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildInlineTransactionDetail(isDark, primary),
                  ),
                ],
                // Right: Historical Performance Panel
                if (_showHistoricalPanel) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildHistoricalPerformancePanel(isDark, primary),
                  ),
                ],
                // Right: Spending Analytics Panel
                if (_showAnalyticsPanel) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildSpendingAnalyticsPanel(isDark, primary),
                  ),
                ],
                // Right: AI Insights Panel
                if (_showAIInsightsPanel) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: _buildAIInsightsPanel(isDark, primary),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Three info cards: Budget vs Expense, Over-budget bars, AI proverb ────

  static const _financeProverbs = [
    'A family that budgets together, grows together.',
    'Small savings today build big dreams for tomorrow.',
    'Track every rupee — awareness is the first step to wealth.',
    'The best time to start budgeting was yesterday. The next best is now.',
    'Financial peace isn\'t about how much you earn — it\'s about how wisely you spend.',
    'Every expense tracked is a step closer to financial freedom.',
    'Teach your children about money, and you give them wings for life.',
    'A budget is telling your money where to go instead of wondering where it went.',
    'Consistency beats intensity — save a little every day.',
    'The secret to wealth is simple: spend less than you earn, invest the rest.',
    'Your family\'s financial health is the foundation for everything else.',
    'Don\'t save what\'s left after spending. Spend what\'s left after saving.',
  ];

  Widget _buildThreeInfoCards(bool isDark, Color primary) {
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final totalExpense = _monthlySpendTotal;
    final remaining = totalBudget - totalExpense;
    final usagePct = totalBudget > 0 ? (totalExpense / totalBudget * 100).clamp(0, 999) : 0.0;
    final withinBudget = totalExpense <= totalBudget;

    // Over-budget categories
    final overBudgetItems = <MapEntry<String, double>>[];
    for (final b in _budgets) {
      if (b.spent > b.amount) {
        overBudgetItems.add(MapEntry(b.category, b.spent - b.amount));
      }
    }
    overBudgetItems.sort((a, b) => b.value.compareTo(a.value));

    // Random proverb based on day
    final proverb = _financeProverbs[DateTime.now().day % _financeProverbs.length];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card 1: Budget vs Expense
        Expanded(
          child: Container(
            height: 100,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: withinBudget
                    ? [const Color(0xFF43A047), const Color(0xFF66BB6A)]
                    : [const Color(0xFFE53935), const Color(0xFFEF5350)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Budget vs Expense', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(_fmtCurrency(totalExpense), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(' / ${_fmtCurrency(totalBudget)}', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: totalBudget > 0 ? (totalExpense / totalBudget).clamp(0, 1) : 0,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(withinBudget ? Icons.check_circle : Icons.warning_rounded, color: Colors.white, size: 28),
                    const SizedBox(height: 2),
                    Text(
                      '${usagePct.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Card 2: Over-budget bar graph
        Expanded(
          child: Container(
            height: 100,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 14, color: Colors.red[400]),
                    const SizedBox(width: 4),
                    Text('Over Budget', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red[400])),
                    const Spacer(),
                    Text('${overBudgetItems.length} items', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
                const SizedBox(height: 8),
                if (overBudgetItems.isEmpty)
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_up_alt_outlined, size: 16, color: Colors.green[400]),
                          const SizedBox(width: 6),
                          Text('All within budget!', style: TextStyle(fontSize: 12, color: Colors.green[600], fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ...overBudgetItems.take(5).map((item) {
                          final maxVal = overBudgetItems.first.value;
                          final fraction = maxVal > 0 ? (item.value / maxVal).clamp(0.15, 1.0) : 0.3;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Tooltip(
                                message: '${item.key}: +${_fmtCurrency(item.value)}',
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: FractionallySizedBox(
                                        heightFactor: fraction.toDouble(),
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.red[300],
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.key.length > 5 ? '${item.key.substring(0, 4)}…' : item.key,
                                      style: TextStyle(fontSize: 8, color: Colors.grey[500]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Card 3: AI Finance Proverb
        Expanded(
          child: Container(
            height: 100,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3E5F5), Color(0xFFE8EAF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 24, color: Colors.deepPurple[300]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Daily Wisdom', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepPurple[300], letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(
                        '"$proverb"',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple[700], fontStyle: FontStyle.italic, height: 1.3),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final count = _getCategoryExpenseCount(cat.label);
          final total = _getCategoryExpenseTotal(cat.label);
          return _buildCategoryChip(cat, count, total);
        },
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

  Widget _buildCategoryChip(_ExpenseCategoryItem cat, int count, double total) {
    final isActive = _selectedCategoryFilter == cat.label;
    return Material(
      color: isActive ? cat.color.withOpacity(0.2) : cat.bgColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() {
            _selectedCategoryFilter = isActive ? null : cat.label;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cat.icon, size: 18, color: cat.color),
              const SizedBox(width: 6),
              Text(
                cat.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cat.color,
                ),
              ),
              if (count > 0) ...[                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
              ],
            ],
          ),
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

  /// Filtered expenses for web layout, with optional category filter applied.
  List<Expense> get _webFilteredExpenses {
    final base = _filteredExpenses;
    if (_selectedCategoryFilter == null) return base;
    final lbl = _selectedCategoryFilter!.toLowerCase();
    return base.where((e) => _matchesCategory(e, lbl)).toList();
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

  // ── Web: Transaction List widget ─────────────────────────────────────────

  Widget _buildWebTransactionList(List<Expense> filtered, bool isDark, Color primary) {
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(AppIcons.receiptOutlined, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                _selectedCategoryFilter != null
                    ? 'No $_selectedCategoryFilter transactions this month'
                    : 'No transactions this month',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text('Add your first expense to get started', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ),
        ),
      );
    }

    final filteredTotal = filtered.fold<double>(0.0, (s, e) => s + e.amount);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  'Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${filtered.length}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary),
                  ),
                ),
                const Spacer(),
                Text(
                  'Total: ${_fmtCurrency(filteredTotal)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          ...filtered.map((expense) => _buildWebTransactionRow(expense, isDark)),
        ],
      ),
    );
  }

  // ── Web: Inline Add Expense Panel ────────────────────────────────────────

  Widget _buildInlineAddExpensePanel(bool isDark, Color primary) {
    return _InlineAddExpensePanel(
      onSaved: () {
        setState(() => _showAddExpensePanel = false);
        _loadExpenses();
      },
      onCancel: () => setState(() => _showAddExpensePanel = false),
    );
  }

  // ── Web: Inline Import Panel ─────────────────────────────────────────────

  Widget _buildInlineImportPanel(bool isDark, Color primary) {
    return _InlineImportPanel(
      onDone: () {
        setState(() => _showImportPanel = false);
        _loadExpenses();
      },
      onCancel: () => setState(() => _showImportPanel = false),
    );
  }

  // ── Web: Inline Transaction Detail ───────────────────────────────────────

  Widget _buildInlineTransactionDetail(bool isDark, Color primary) {
    final expense = _selectedExpenseDetail!;
    return _InlineTransactionDetailPanel(
      expense: expense,
      onEdit: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => AddEditExpenseScreen(expense: expense),
          ),
        );
        if (result == true) {
          setState(() => _selectedExpenseDetail = null);
          _loadExpenses();
        }
      },
      onDelete: () => _deleteExpenseInline(expense),
      onClose: () => setState(() => _selectedExpenseDetail = null),
    );
  }

  Future<void> _deleteExpenseInline(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Are you sure you want to delete "${expense.description}"?'),
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
    if (confirmed != true || !mounted) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _expenseService.deleteExpense(
        expenseId: expense.id,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      setState(() => _selectedExpenseDetail = null);
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: $e')),
        );
      }
    }
  }

  // ── Web: Historical Performance Panel ────────────────────────────────────

  Widget _buildHistoricalPerformancePanel(bool isDark, Color primary) {
    return _HistoricalPerformancePanel(
      expenses: _expenses,
      budgets: _budgets,
      onClose: () => setState(() => _showHistoricalPanel = false),
    );
  }

  // ── Web: Spending Analytics Panel ────────────────────────────────────────

  Widget _buildSpendingAnalyticsPanel(bool isDark, Color primary) {
    return _SpendingAnalyticsPanel(
      expenses: _expenses,
      budgets: _budgets,
      onClose: () => setState(() => _showAnalyticsPanel = false),
    );
  }

  // ── Web: AI Insights Panel ───────────────────────────────────────────────

  Widget _buildAIInsightsPanel(bool isDark, Color primary) {
    return _AIInsightsPanel(
      onClose: () => setState(() => _showAIInsightsPanel = false),
    );
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

// ── Inline Add Expense Panel (shown in web layout) ───────────────────────

class _InlineAddExpensePanel extends StatefulWidget {
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _InlineAddExpensePanel({required this.onSaved, required this.onCancel});

  @override
  State<_InlineAddExpensePanel> createState() => _InlineAddExpensePanelState();
}

class _InlineAddExpensePanelState extends State<_InlineAddExpensePanel> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  String _selectedCategory = 'Groceries';
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;
  bool _showDatePicker = false;

  static const _categories = [
    'Groceries', 'Entertainment', 'Education', 'Personal Care',
    'Physical Wellness', 'Mental Wellness', 'Convenience Food',
    'Senior Care', 'Pet Care', 'Vacation', 'Party',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final tags = parseTags(_tagsController.text);
      await ExpenseService().createExpense(
        amount: amount,
        category: _selectedCategory,
        description: description,
        date: _selectedDate,
        tags: tags,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added successfully')),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  late DateTime _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month);

  void _toggleDatePicker() => setState(() => _showDatePicker = !_showDatePicker);
  void _prevMonth() => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1));
  void _nextMonth() {
    final next = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
    if (!next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) {
      setState(() => _calendarMonth = next);
    }
  }

  Widget _buildInlineCalendar() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday % 7; // Sunday = 0
    final earliest = today.subtract(const Duration(days: 365));
    final canGoPrev = DateTime(_calendarMonth.year, _calendarMonth.month - 1).isAfter(DateTime(earliest.year, earliest.month - 1));
    final canGoNext = !DateTime(_calendarMonth.year, _calendarMonth.month + 1).isAfter(DateTime(now.year, now.month));

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        children: [
          // Month nav
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: canGoPrev ? _prevMonth : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: canGoPrev ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_left_rounded, size: 20, color: canGoPrev ? const Color(0xFF7C4DFF) : Colors.grey[300]),
                ),
              ),
              Text(
                '${_monthNames[_calendarMonth.month]} ${_calendarMonth.year}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.deepPurple[700]),
              ),
              InkWell(
                onTap: canGoNext ? _nextMonth : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: canGoNext ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: canGoNext ? const Color(0xFF7C4DFF) : Colors.grey[300]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day-of-week headers
          Row(
            children: _dayLabels.map((d) => Expanded(
              child: Center(child: Text(d, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepPurple[300]))),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Day grid
          ...List.generate(6, (week) {
            return Row(
              children: List.generate(7, (dow) {
                final dayIndex = week * 7 + dow - startWeekday + 1;
                if (dayIndex < 1 || dayIndex > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }
                final date = DateTime(_calendarMonth.year, _calendarMonth.month, dayIndex);
                final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
                final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
                final isFuture = date.isAfter(today);
                final isTooOld = date.isBefore(earliest);
                final isDisabled = isFuture || isTooOld;

                return Expanded(
                  child: GestureDetector(
                    onTap: isDisabled ? null : () {
                      setState(() {
                        _selectedDate = date;
                        _showDatePicker = false;
                      });
                    },
                    child: Container(
                      height: 32,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)])
                            : null,
                        color: isToday && !isSelected ? Colors.deepPurple.shade100 : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$dayIndex',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : isDisabled
                                    ? Colors.grey[300]
                                    : isToday
                                        ? Colors.deepPurple[700]
                                        : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          // Quick pick row
          const SizedBox(height: 8),
          Row(
            children: [
              _quickPickChip('Today', today),
              const SizedBox(width: 6),
              _quickPickChip('Yesterday', today.subtract(const Duration(days: 1))),
              const SizedBox(width: 6),
              _quickPickChip('2 days ago', today.subtract(const Duration(days: 2))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickPickChip(String label, DateTime date) {
    final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedDate = date;
          _calendarMonth = DateTime(date.year, date.month);
          _showDatePicker = false;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)]) : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? null : Border.all(color: Colors.deepPurple.shade100),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.deepPurple[400]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Add Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Amount
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'e.g. Weekly groceries',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          // Category dropdown
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedCategory = v); },
          ),
          const SizedBox(height: 12),
          // ── Modern inline date picker ────────────────────────────
          InkWell(
            onTap: _toggleDatePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _showDatePicker
                      ? [const Color(0xFF7C4DFF), const Color(0xFF536DFE)]
                      : [Colors.grey.shade50, Colors.grey.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _showDatePicker ? const Color(0xFF7C4DFF) : Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: _showDatePicker ? Colors.white : const Color(0xFF7C4DFF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedDate.day} ${_monthNames[_selectedDate.month]} ${_selectedDate.year}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _showDatePicker ? Colors.white : Colors.grey[800],
                      ),
                    ),
                  ),
                  Icon(
                    _showDatePicker ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: _showDatePicker ? Colors.white : Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),
          // Slide-down calendar
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildInlineCalendar(),
            crossFadeState: _showDatePicker ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
          const SizedBox(height: 12),
          // Tags
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: 'Tags (optional)',
              hintText: 'mom, school, medical',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),
          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, size: 18),
                        SizedBox(width: 6),
                        Text('Save Transaction', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
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

// ══════════════════════════════════════════════════════════════════════════════
// Inline Import Panel (right side, same look as Add Expense)
// ══════════════════════════════════════════════════════════════════════════════

class _InlineImportPanel extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const _InlineImportPanel({required this.onDone, required this.onCancel});

  @override
  State<_InlineImportPanel> createState() => _InlineImportPanelState();
}

class _InlineImportPanelState extends State<_InlineImportPanel> {
  String _importType = 'expenses';
  String? _csvText;
  String? _fileName;
  String? _errorMessage;
  bool _isValidating = false;
  bool _isImporting = false;
  ImportPreviewResult? _preview;
  ImportCommitResult? _commitResult;

  bool get _fileSelected => _csvText != null;

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    if (file.bytes == null) {
      setState(() => _errorMessage = 'Could not read file. Please try again.');
      return;
    }

    const maxBytes = 5 * 1024 * 1024;
    if (file.bytes!.length > maxBytes) {
      setState(() => _errorMessage = 'File exceeds the 5 MB limit.');
      return;
    }

    String text;
    try {
      text = utf8.decode(file.bytes!);
    } catch (_) {
      setState(() => _errorMessage = 'File must be UTF-8 encoded.');
      return;
    }

    if (text.trim().isEmpty) {
      setState(() => _errorMessage = 'The selected file is empty.');
      return;
    }

    setState(() {
      _csvText = text;
      _fileName = file.name;
      _preview = null;
      _commitResult = null;
    });
  }

  Future<void> _validate() async {
    if (_csvText == null) return;
    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _preview = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = ImportService(supabaseUrl: auth.supabaseUrl, authService: auth);
      final result = await svc.preview(type: _importType, csvText: _csvText!);
      setState(() {
        _preview = result;
        _isValidating = false;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isValidating = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during validation.';
        _isValidating = false;
      });
    }
  }

  Future<void> _import() async {
    if (_csvText == null) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = ImportService(supabaseUrl: auth.supabaseUrl, authService: auth);
      final result = await svc.commit(type: _importType, csvText: _csvText!);
      setState(() {
        _commitResult = result;
        _isImporting = false;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isImporting = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during import.';
        _isImporting = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _csvText = null;
      _fileName = null;
      _preview = null;
      _commitResult = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _commitResult != null ? _buildDone() : _buildForm(),
    );
  }

  Widget _buildDone() {
    final result = _commitResult!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Icon(Icons.check_circle_outline, color: Colors.green[600], size: 56),
        const SizedBox(height: 12),
        Text(
          '${result.imported} ${result.type} imported',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('Batch: ${result.batchId}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _reset,
                child: const Text('Import Another'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: widget.onDone,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          children: [
            const Text('Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Type selector
        Row(
          children: [
            ChoiceChip(
              label: const Text('Expenses'),
              selected: _importType == 'expenses',
              onSelected: (_) => setState(() {
                _importType = 'expenses';
                _csvText = null;
                _fileName = null;
                _preview = null;
              }),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Budgets'),
              selected: _importType == 'budgets',
              onSelected: (_) => setState(() {
                _importType = 'budgets';
                _csvText = null;
                _fileName = null;
                _preview = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // File picker
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(_fileName ?? 'Select Excel / PDF / Word / Image'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
        ),

        if (_fileName != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green[600], size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(_fileName!, style: TextStyle(color: Colors.green[600], fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              InkWell(
                onTap: () => setState(() {
                  _csvText = null;
                  _fileName = null;
                  _preview = null;
                }),
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ],
          ),
        ],

        // Error
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 12, color: Colors.red[700]))),
              ],
            ),
          ),
        ],

        // Preview results
        if (_preview != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _preview!.isClean ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_preview!.validCount} valid, ${_preview!.errorCount} error${_preview!.errorCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _preview!.isClean ? Colors.green[700] : Colors.orange[800]),
                ),
                if (_preview!.hasErrors) ...[
                  const SizedBox(height: 6),
                  ...(_preview!.errors.take(5).map((e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Row ${e.row}: ${e.field} — ${e.message}', style: TextStyle(fontSize: 11, color: Colors.red[600])),
                  ))),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),

        // Action buttons
        if (_preview == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _fileSelected && !_isValidating ? _validate : null,
              icon: _isValidating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(_isValidating ? 'Validating...' : 'Validate'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

        if (_preview != null && _preview!.isClean)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_isImporting ? _import : null,
              icon: _isImporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload, size: 18),
              label: Text(_isImporting ? 'Importing...' : 'Import ${_preview!.validCount} rows'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

        if (_preview != null && _preview!.hasErrors) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload corrected file'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline Transaction Detail Panel (right side, same look as Add Expense)
// ══════════════════════════════════════════════════════════════════════════════

class _InlineTransactionDetailPanel extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _InlineTransactionDetailPanel({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = expense.category.toLowerCase() == 'income' ||
        expense.category.toLowerCase() == 'salary';
    final d = expense.date;
    final dateStr = '${d.day}/${d.month}/${d.year}';
    final bgColor = AppColors.getCategoryColor(expense.category);
    final iconColor = AppColors.getCategoryIconColor(expense.category);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Text('Transaction Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Category icon + amount
          Center(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(AppIcons.getCategoryIcon(expense.category), size: 28, color: iconColor),
                ),
                const SizedBox(height: 12),
                Text(
                  '${isIncome ? '+' : '-'} ₹${expense.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: isIncome ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Details
          _detailRow(Icons.description_outlined, 'Description', expense.description),
          _detailRow(Icons.category_outlined, 'Category', expense.category),
          _detailRow(Icons.calendar_today_outlined, 'Date', dateStr),
          _detailRow(Icons.source_outlined, 'Source', expense.source),
          if (expense.notes != null && expense.notes!.isNotEmpty)
            _detailRow(Icons.notes_outlined, 'Notes', expense.notes!),
          if (expense.tags.isNotEmpty)
            _detailRow(Icons.label_outlined, 'Tags', expense.tags.join(', ')),
          _detailRow(Icons.verified_outlined, 'Status', expense.isApproved ? 'Approved' : 'Pending'),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[600]),
                  label: Text('Delete', style: TextStyle(color: Colors.red[600])),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: Colors.red[300]!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Historical Performance Panel
// ══════════════════════════════════════════════════════════════════════════════

class _HistoricalPerformancePanel extends StatelessWidget {
  final List<Expense> expenses;
  final List<Budget> budgets;
  final VoidCallback onClose;

  const _HistoricalPerformancePanel({
    required this.expenses,
    required this.budgets,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Group expenses by month for last 6 months
    final monthlyData = <String, double>{};
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final key = '${_monthAbbr(m.month)} ${m.year}';
      monthlyData[key] = 0;
    }
    for (final e in expenses) {
      final d = e.date;
      final diff = (now.year * 12 + now.month) - (d.year * 12 + d.month);
      if (diff >= 0 && diff < 6) {
        final key = '${_monthAbbr(d.month)} ${d.year}';
        monthlyData[key] = (monthlyData[key] ?? 0) + e.amount;
      }
    }

    final maxSpend = monthlyData.values.fold<double>(0, (a, b) => a > b ? a : b);
    final totalBudget = budgets.fold<double>(0, (s, b) => s + b.amount);
    final currentMonthSpend = monthlyData.values.lastOrNull ?? 0;
    final prevMonthSpend = monthlyData.values.length >= 2
        ? monthlyData.values.toList()[monthlyData.values.length - 2]
        : 0.0;
    final trend = prevMonthSpend > 0
        ? ((currentMonthSpend - prevMonthSpend) / prevMonthSpend * 100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 20, color: const Color(0xFF7C4DFF)),
              const SizedBox(width: 8),
              const Text('Historical Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary cards
          Row(
            children: [
              Expanded(child: _miniCard('This Month', '₹${currentMonthSpend.toStringAsFixed(0)}', Colors.deepPurple)),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Budget', '₹${totalBudget.toStringAsFixed(0)}', Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _miniCard(
                'Trend',
                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                trend > 0 ? Colors.red : Colors.green,
              )),
            ],
          ),
          const SizedBox(height: 20),

          // Monthly bar chart
          const Text('Last 6 Months', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 12),

          ...monthlyData.entries.map((entry) {
            final fraction = maxSpend > 0 ? (entry.value / maxSpend).clamp(0.02, 1.0) : 0.02;
            final isCurrentMonth = entry.key == monthlyData.keys.last;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text(entry.key, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: isCurrentMonth ? FontWeight.w700 : FontWeight.w400))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: Colors.grey[100],
                        color: isCurrentMonth ? const Color(0xFF7C4DFF) : Colors.deepPurple[200],
                        minHeight: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: Text('₹${entry.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]), textAlign: TextAlign.right)),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Budget utilization
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: currentMonthSpend <= totalBudget ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  currentMonthSpend <= totalBudget ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  size: 18,
                  color: currentMonthSpend <= totalBudget ? Colors.green[700] : Colors.red[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentMonthSpend <= totalBudget
                        ? 'Within budget — ₹${(totalBudget - currentMonthSpend).toStringAsFixed(0)} remaining'
                        : 'Over budget by ₹${(currentMonthSpend - totalBudget).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: currentMonthSpend <= totalBudget ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  static String _monthAbbr(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m.clamp(1, 12)];
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Spending Analytics Panel
// ══════════════════════════════════════════════════════════════════════════════

class _SpendingAnalyticsPanel extends StatelessWidget {
  final List<Expense> expenses;
  final List<Budget> budgets;
  final VoidCallback onClose;

  const _SpendingAnalyticsPanel({
    required this.expenses,
    required this.budgets,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Current month expenses
    final currentMonthExpenses = expenses.where((e) =>
        e.date.year == now.year && e.date.month == now.month).toList();

    // Category breakdown
    final categorySpend = <String, double>{};
    for (final e in currentMonthExpenses) {
      categorySpend[e.category] = (categorySpend[e.category] ?? 0) + e.amount;
    }
    final sortedCategories = categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalSpend = sortedCategories.fold<double>(0, (s, e) => s + e.value);
    final topCategory = sortedCategories.isNotEmpty ? sortedCategories.first : null;

    // Daily average
    final daysInMonth = now.day;
    final dailyAvg = daysInMonth > 0 ? totalSpend / daysInMonth : 0.0;

    // Transaction count
    final txnCount = currentMonthExpenses.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 20, color: const Color(0xFF00ACC1)),
              const SizedBox(width: 8),
              const Text('Spending Analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary stats
          Row(
            children: [
              Expanded(child: _statCard('Total', '₹${totalSpend.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, const Color(0xFF00ACC1))),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Daily Avg', '₹${dailyAvg.toStringAsFixed(0)}', Icons.trending_up_outlined, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Txns', txnCount.toString(), Icons.receipt_long_outlined, Colors.indigo)),
            ],
          ),
          const SizedBox(height: 20),

          // Category breakdown heading
          Row(
            children: [
              const Text('Category Breakdown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
              const Spacer(),
              if (topCategory != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Top: ${topCategory.key}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red[600])),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Category bars
          if (sortedCategories.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('No expenses this month', style: TextStyle(color: Colors.grey))),
            )
          else
            ...sortedCategories.take(8).map((entry) {
              final pct = totalSpend > 0 ? (entry.value / totalSpend * 100) : 0.0;
              final budgetForCategory = budgets.where((b) => b.category == entry.key).firstOrNull;
              final isOverBudget = budgetForCategory != null && entry.value > budgetForCategory.amount;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.getCategoryIcon(entry.key), size: 14, color: AppColors.getCategoryIconColor(entry.key)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                        Text('₹${entry.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isOverBudget ? Colors.red[600] : Colors.grey[700])),
                        const SizedBox(width: 4),
                        Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0, 1),
                        backgroundColor: Colors.grey[100],
                        color: isOverBudget ? Colors.red[400] : AppColors.getCategoryColor(entry.key),
                        minHeight: 6,
                      ),
                    ),
                    if (budgetForCategory != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Budget: ₹${budgetForCategory.amount.toStringAsFixed(0)}${isOverBudget ? ' (over by ₹${(entry.value - budgetForCategory.amount).toStringAsFixed(0)})' : ''}',
                        style: TextStyle(fontSize: 9, color: isOverBudget ? Colors.red[400] : Colors.grey[400]),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AI Insights Panel
// ══════════════════════════════════════════════════════════════════════════════

class _AIInsightsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _AIInsightsPanel({required this.onClose});

  @override
  State<_AIInsightsPanel> createState() => _AIInsightsPanelState();
}

class _AIInsightsPanelState extends State<_AIInsightsPanel> {
  bool _loading = false;
  String? _analysis;
  String? _error;

  String _chatInput = '';
  final _chatController = TextEditingController();
  final List<_ChatMessage> _chatMessages = [];
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalysis() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) setState(() { _analysis = result['analysis'] as String?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _sendChat() async {
    final msg = _chatController.text.trim();
    if (msg.isEmpty) return;
    _chatController.clear();
    setState(() {
      _chatMessages.add(_ChatMessage(text: msg, isUser: true));
      _chatLoading = true;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().sendChatMessage(
        message: msg,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(text: result['response'] as String? ?? 'No response', isUser: false));
          _chatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(text: 'Error: $e', isUser: false));
          _chatLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: const Color(0xFF9C27B0)),
              const SizedBox(width: 8),
              const Text('AI Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _fetchAnalysis,
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh analysis',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Budget Analysis section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.purple.shade50, Colors.blue.shade50]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 16, color: Colors.purple[600]),
                    const SizedBox(width: 6),
                    Text('Budget Analysis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple[700])),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  ))
                else if (_error != null)
                  Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red[600]))
                else if (_analysis != null)
                  Text(_analysis!, style: const TextStyle(fontSize: 12, height: 1.5))
                else
                  Text('Tap refresh to generate AI analysis', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Chat section
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 16, color: Colors.purple[400]),
              const SizedBox(width: 6),
              Text('Ask AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple[600])),
            ],
          ),
          const SizedBox(height: 8),

          // Chat messages
          if (_chatMessages.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: _chatMessages.length,
                itemBuilder: (ctx, i) {
                  final msg = _chatMessages[i];
                  return Align(
                    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: msg.isUser ? Colors.purple[100] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: msg.isUser ? null : Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(msg.text, style: const TextStyle(fontSize: 12)),
                    ),
                  );
                },
              ),
            ),
            if (_chatLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Thinking...', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],

          // Chat input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: 'Ask about your finances...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _chatLoading ? null : _sendChat,
                icon: Icon(Icons.send_rounded, color: Colors.purple[600]),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}
