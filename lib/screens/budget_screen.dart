import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/app_header.dart';

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
    final category = await showDialog<String>(
      context: context,
      builder: (context) {
        final amountController = TextEditingController(
          text: existing == null ? '' : existing.amount.toStringAsFixed(2),
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
                    Navigator.pop(context, '$selectedCategory|$amount');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (category == null || !mounted) return;

    final parts = category.split('|');
    if (parts.length != 2) return;

    final selectedCategory = parts[0];
    final selectedAmount = double.tryParse(parts[1]);
    if (selectedAmount == null) return;

    try {
      await _budgetService.upsertBudget(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        category: selectedCategory,
        amount: selectedAmount,
        month: _monthKey,
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
        content: Text('Delete ${_titleCase(budget.category)} budget for $_monthKey?'),
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
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadBudgets();
  }

  @override
  Widget build(BuildContext context) {
    final summary = BudgetSummary(month: _monthKey, budgets: _budgets);

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
    final progressColor =
        isOver ? AppColors.errorDark : (percent >= 80 ? AppColors.warningDark : AppColors.successDark);

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
                  icon: const Icon(AppIcons.delete, size: 18, color: AppColors.error),
                  tooltip: 'Delete budget',
                ),
              ],
            ),
            Text('Budget: Rs ${budget.amount.toStringAsFixed(2)}'),
            Text('Spent: Rs ${budget.spent.toStringAsFixed(2)}'),
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
