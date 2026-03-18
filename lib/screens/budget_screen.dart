import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/family_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/tag_utils.dart';
import '../widgets/app_header.dart';
import '../widgets/tag_input_section.dart';
import '../widgets/tag_wrap.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetService _budgetService = BudgetService();
  final List<String> _categories = const [
    'food',
    'transport',
    'utilities',
    'shopping',
    'healthcare',
    'entertainment',
    'other',
  ];

  List<Budget> _budgets = [];
  List<String> _tagSuggestions = [];
  bool _isLoading = false;
  String? _error;
  // Technical detail (HTTP status + raw body) shown under the error for debugging.
  String? _errorDetail;
  // Budget Edge Functions are deployed. Set to false to disable the feature.
  final bool _backendAvailable = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  // Incremented on every load; stale async responses are discarded.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (_backendAvailable) _loadBudgets();
    _loadTagSuggestions();
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

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  Future<void> _loadBudgets() async {
    if (!_backendAvailable) return;
    final gen = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
      _errorDetail = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final budgets = await _budgetService.getBudgets(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        month: _monthKey,
      );

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _budgets = budgets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      final detail = _buildErrorDetail(e);
      setState(() {
        _error = e is BudgetException
            ? e.message
            : 'Unexpected error: ${e.runtimeType}';
        _errorDetail = detail;
        _isLoading = false;
      });
    }
  }

  /// Formats the technical diagnostic string shown under the error message.
  String _buildErrorDetail(Object e) {
    if (e is BudgetException) {
      final lines = <String>[];
      if (e.statusCode != null) lines.add('HTTP ${e.statusCode}');
      if (e.rawBody != null && e.rawBody!.isNotEmpty) {
        lines.add('Response: ${e.rawBody}');
      }
      return lines.isEmpty ? e.message : lines.join('\n');
    }
    return e.toString();
  }

  Future<void> _addOrEditBudget({Budget? existing}) async {
    // Capture authService before any await to avoid BuildContext across async gaps.
    final authService = Provider.of<AuthService>(context, listen: false);
    final result = await showDialog<_BudgetFormResult>(
      context: context,
      builder: (context) {
        final amountController = TextEditingController(
          text: existing == null ? '' : existing.amount.toStringAsFixed(2),
        );
        final tagsController = TextEditingController(
          text: joinTags(existing?.tags),
        );
        String selectedCategory = existing?.category ?? _categories.first;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Budget' : 'Edit Budget'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    items: _categories
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(_titleCase(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedCategory = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monthly Budget',
                      prefixText: 'Rs ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TagInputSection(
                    controller: tagsController,
                    suggestions: _tagSuggestions,
                    helperText:
                        'Tag this budget with family members or intent like mom, school, travel.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      _BudgetFormResult(
                        category: selectedCategory,
                        amount: amount,
                        tags: parseTags(tagsController.text),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    final selectedCategory = result.category;
    final selectedAmount = result.amount;

    try {
      await _budgetService.upsertBudget(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        category: selectedCategory,
        amount: selectedAmount,
        month: _monthKey,
        tags: result.tags,
      );
      if (!mounted) return;
      await _loadBudgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? 'Budget added successfully'
              : 'Budget updated successfully'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save budget: $e')),
      );
    }
  }

  Future<void> _deleteBudget(Budget budget) async {
    // Capture authService before any await to avoid BuildContext across async gaps.
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text(
            'Delete ${_titleCase(budget.category)} budget for $_monthKey?'),
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

    if (confirm != true) return;
    if (!mounted) return;

    try {
      await _budgetService.deleteBudget(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        budgetId: budget.id,
      );
      if (!mounted) return;
      await _loadBudgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Budget deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete budget: $e')),
      );
    }
  }

  void _moveMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadBudgets();
  }

  @override
  Widget build(BuildContext context) {
    final summary = BudgetSummary(month: _monthKey, budgets: _budgets);
    if (kIsWeb) {
      return _buildWebLayout(context, summary);
    }

    return Scaffold(
      floatingActionButton: _backendAvailable
          ? FloatingActionButton(
              onPressed: () => _addOrEditBudget(),
              child: const Icon(AppIcons.add),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Budget',
              avatarIcon: AppIcons.pieChart,
            ),
            _buildMonthSelector(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _SummaryCard(summary: summary),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, BudgetSummary summary) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildWebError()
              : _buildWebContent(summary, isDark, primary),
    );
  }

  Widget _buildWebError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.error, size: 48, color: AppColors.error),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: 10),
              Container(
                width: 560,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _errorDetail!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.grey600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadBudgets,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebContent(BudgetSummary summary, bool isDark, Color primary) {
    final remaining = summary.totalRemaining;
    final projectedSavings = remaining > 0 ? remaining * 0.8 : 0.0;

    return RefreshIndicator(
      onRefresh: _loadBudgets,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: 'Add budget',
                    onPressed: () => _addOrEditBudget(),
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Budget Analysis',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Detailed breakdown of your budget',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
                const Spacer(),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  _monthLabel(_selectedMonth),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: (_selectedMonth.year == DateTime.now().year &&
                          _selectedMonth.month == DateTime.now().month)
                      ? null
                      : () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _budgetSummaryCard(
                    title: 'Total Monthly Budget',
                    value: '₹${summary.totalSpent.toStringAsFixed(0)}',
                    subtitle: '/ ₹${summary.totalBudget.toStringAsFixed(0)}',
                    progress: summary.totalBudget > 0
                        ? (summary.totalSpent / summary.totalBudget)
                            .clamp(0.0, 1.0)
                        : 0,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _budgetSummaryCard(
                    title: 'Remaining to Spend',
                    value: '₹${remaining.toStringAsFixed(0)}',
                    subtitle: remaining >= 0
                        ? 'Safe to spend'
                        : 'Exceeded current budget',
                    valueColor:
                        remaining >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _budgetSummaryCard(
                    title: 'Projected Savings',
                    value: '₹${projectedSavings.toStringAsFixed(0)}',
                    subtitle: 'Projected from current trend',
                    valueColor: primary,
                    comingSoon: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Category-wise Budgets',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          _monthLabel(_selectedMonth),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_budgets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No budgets set for this month'),
                      ),
                    )
                  else
                    ..._budgets.map((budget) => _buildWebBudgetRow(
                          budget,
                          isDark,
                          onEdit: () => _addOrEditBudget(existing: budget),
                          onDelete: () => _deleteBudget(budget),
                        )),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.grey800 : const Color(0xFFF8FAFC),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: primary, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Looks like your food budget is tight. Tap Review & Adjust to quickly rebalance.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => _addOrEditBudget(),
                          child: const Text('Review & Adjust'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? AppColors.grey800
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Budget Compliance (6 Months)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _miniBar(0.7, const Color(0xFF10B981)),
                            const SizedBox(width: 6),
                            _miniBar(0.75, const Color(0xFF10B981)),
                            const SizedBox(width: 6),
                            _miniBar(1, const Color(0xFFEF4444)),
                            const SizedBox(width: 6),
                            _miniBar(0.88, const Color(0xFFF59E0B)),
                            const SizedBox(width: 6),
                            _miniBar(0.65, const Color(0xFF10B981)),
                            const SizedBox(width: 6),
                            _miniBar(0.82, primary),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            Icon(Icons.close_rounded,
                                size: 12, color: Colors.red),
                            SizedBox(width: 6),
                            Text(
                              'Historical trend breakdown is under development',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: primary, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Smart Budget Insight',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.close_rounded,
                                size: 12, color: Colors.red),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'AI recommendations are under development. You can still edit budgets manually using Review & Adjust.',
                          style: TextStyle(fontSize: 13, height: 1.4),
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

  Widget _budgetSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    Color? valueColor,
    double? progress,
    Color? color,
    bool comingSoon = false,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
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
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
              if (comingSoon)
                const Icon(Icons.close_rounded, size: 12, color: Colors.red),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              if (subtitle.startsWith('/')) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ),
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: const Color(0xFFF1F5F9),
                color: color ?? primary,
              ),
            ),
          ],
          if (!subtitle.startsWith('/')) ...[
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebBudgetRow(
    Budget budget,
    bool isDark, {
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final percent = budget.usagePercent.clamp(0, 100).toDouble();
    final isOver = budget.isOverBudget;
    final statusColor = isOver
        ? AppColors.error
        : (percent >= 80 ? AppColors.warningDark : AppColors.success);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _budgetCategoryIcon(budget.category),
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleCase(budget.category),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '₹${budget.amount.toStringAsFixed(0)} budgeted',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    if (budget.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      TagWrap(tags: budget.tags),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${budget.spent.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    isOver
                        ? 'Exceeded by ₹${budget.remaining.abs().toStringAsFixed(0)}'
                        : percent >= 80
                            ? '${percent.toStringAsFixed(0)}% utilized'
                            : 'Under budget',
                    style: TextStyle(fontSize: 11, color: statusColor),
                  ),
                ],
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit budget',
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete budget',
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isOver
                    ? 'Overspent: ${percent.toStringAsFixed(0)}%'
                    : 'Spent: ${percent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                isOver
                    ? 'Needs adjustment'
                    : '₹${budget.remaining.toStringAsFixed(0)} left',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _budgetCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'utilities':
        return Icons.bolt;
      case 'transport':
        return Icons.directions_car;
      case 'entertainment':
        return Icons.movie;
      case 'healthcare':
        return Icons.local_hospital;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Widget _miniBar(double heightFactor, Color color) {
    return Expanded(
      child: SizedBox(
        height: 96,
        child: Align(
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
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                _monthLabel(_selectedMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: (_selectedMonth.year == DateTime.now().year &&
                    _selectedMonth.month == DateTime.now().month)
                ? null
                : () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_backendAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.pieChart, size: 64, color: AppColors.grey400),
              SizedBox(height: 16),
              Text(
                'Budget Feature Coming Soon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Budget management is under development and will be available in an upcoming release.',
                style: TextStyle(color: AppColors.grey400),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.error, size: 48, color: AppColors.error),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_errorDetail != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _errorDetail!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.grey600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadBudgets,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_budgets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.pieChart, size: 64, color: AppColors.grey400),
            SizedBox(height: 12),
            Text(
              'No budgets set for this month',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Tap + to create your first budget'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBudgets,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        itemCount: _budgets.length,
        itemBuilder: (context, index) {
          final budget = _budgets[index];
          return _BudgetCard(
            budget: budget,
            onEdit: () => _addOrEditBudget(existing: budget),
            onDelete: () => _deleteBudget(budget),
          );
        },
      ),
    );
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  String _monthLabel(DateTime date) {
    const months = [
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
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _BudgetFormResult {
  final String category;
  final double amount;
  final List<String> tags;

  const _BudgetFormResult({
    required this.category,
    required this.amount,
    required this.tags,
  });
}

class _SummaryCard extends StatelessWidget {
  final BudgetSummary summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final remaining = summary.totalRemaining;
    final color = remaining < 0 ? AppColors.errorDark : AppColors.successDark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                label: 'Budget',
                value: 'Rs ${summary.totalBudget.toStringAsFixed(0)}',
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                label: 'Spent',
                value: 'Rs ${summary.totalSpent.toStringAsFixed(0)}',
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                label: 'Remaining',
                value: 'Rs ${remaining.toStringAsFixed(0)}',
                valueColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.grey600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BudgetCard({
    required this.budget,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final percent = budget.usagePercent.clamp(0, 100).toDouble();
    final isOver = budget.isOverBudget;
    final progressColor = isOver
        ? AppColors.errorDark
        : (percent >= 80 ? AppColors.warningDark : AppColors.successDark);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.category.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.edit, size: 18),
                  tooltip: 'Edit budget',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(AppIcons.delete,
                      size: 18, color: AppColors.error),
                  tooltip: 'Delete budget',
                ),
              ],
            ),
            Text('Budget: Rs ${budget.amount.toStringAsFixed(2)}'),
            Text('Spent: Rs ${budget.spent.toStringAsFixed(2)}'),
            if (budget.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              TagWrap(tags: budget.tags),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 10,
                backgroundColor: AppColors.grey200,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isOver
                  ? 'Over budget by Rs ${budget.remaining.abs().toStringAsFixed(2)}'
                  : 'Remaining Rs ${budget.remaining.toStringAsFixed(2)}',
              style: TextStyle(
                color: progressColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
