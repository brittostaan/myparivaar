import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/excel_budget_parser.dart';
import '../services/family_service.dart';
import '../services/ai_service.dart';
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

enum _BudgetWebView {
  currentMonth,
  historicalPerformance,
  spendingAnalytics,
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
  _BudgetWebView _selectedWebView = _BudgetWebView.currentMonth;
  Map<String, List<Budget>> _historicalBudgets = {};
  // Incremented on every load; stale async responses are discarded.
  int _loadGeneration = 0;

  // Excel upload
  bool _isUploading = false;

  // AI Budget Insights
  bool _isLoadingInsights = false;
  String? _aiAnalysis;
  List<String> _aiSuggestions = [];
  String? _aiInsightsError;

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

  Future<void> _fetchAIInsights() async {
    setState(() {
      _isLoadingInsights = true;
      _aiInsightsError = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _aiAnalysis = result['analysis'] as String?;
        _aiSuggestions = (result['suggestions'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        _isLoadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingInsights = false;
        _aiInsightsError = e.toString();
      });
    }
  }

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

    String _monthKeyFor(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

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
      final idToken = await authService.getIdToken();
      final months = List.generate(
        6,
        (index) => DateTime(_selectedMonth.year, _selectedMonth.month - index),
      );
      final monthKeys = months.map(_monthKeyFor).toList();
      final historyResults = await Future.wait(
        monthKeys.map(
          (monthKey) => _budgetService.getBudgets(
            supabaseUrl: authService.supabaseUrl,
            idToken: idToken,
            month: monthKey,
          ),
        ),
      );
      final historicalBudgets = <String, List<Budget>>{};
      for (var i = 0; i < monthKeys.length; i++) {
        historicalBudgets[monthKeys[i]] = historyResults[i];
      }
      final budgets = historicalBudgets[_monthKey] ?? const <Budget>[];

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _budgets = budgets;
        _historicalBudgets = historicalBudgets;
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

  Future<void> _uploadExcelBudget() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file data')),
        );
        return;
      }

      setState(() => _isUploading = true);

      final parser = ExcelBudgetParser();
      final rows = parser.parseExcelFile(Uint8List.fromList(bytes));

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No budget data found in the Excel file')),
        );
        return;
      }

      setState(() => _isUploading = false);
      if (!mounted) return;

      // Show preview dialog with month/year picker
      final dialogResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ExcelPreviewDialog(
          rows: rows,
          initialMonth: _monthKey,
        ),
      );

      if (dialogResult == null || !mounted) return;
      final selectedMonth = dialogResult['month'] as String;
      final editedRows = dialogResult['rows'] as List<_EditableRow>;

      setState(() => _isUploading = true);

      // Import each row individually
      // Use "category - subcategory" as the budget category to keep items separate
      final validRows = editedRows.where((r) => r.isValid).toList();
      int successCount = 0;
      final errors = <String>[];

      for (final row in validRows) {
        try {
          // Build a unique category: if there's a subcategory, combine them
          final budgetCategory = row.subcategory.isNotEmpty
              ? '${row.category} - ${row.subcategory}'.toLowerCase().trim()
              : row.category.toLowerCase().trim();

          await _budgetService.upsertBudget(
            supabaseUrl: authService.supabaseUrl,
            idToken: await authService.getIdToken(),
            category: budgetCategory,
            amount: row.amount,
            month: selectedMonth,
          );
          successCount++;
        } catch (e) {
          final label = row.subcategory.isNotEmpty
              ? '${row.category} - ${row.subcategory}'
              : row.category;
          errors.add('${_titleCase(label)}: $e');
        }
      }

      if (!mounted) return;
      setState(() => _isUploading = false);
      await _loadBudgets();

      if (!mounted) return;
      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $successCount budget items'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        // Show detailed error dialog
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warningDark),
                const SizedBox(width: 8),
                Text('Imported $successCount, ${errors.length} failed'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (successCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('$successCount categories imported successfully.',
                          style: const TextStyle(color: AppColors.success)),
                    ),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...errors.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process Excel file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = BudgetSummary(month: _monthKey, budgets: _budgets);
    if (kIsWeb) {
      return _buildWebLayout(context, summary);
    }

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
                          'Budget',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Plan your monthly spending',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_backendAvailable) ...[
                    IconButton(
                      onPressed: _isUploading ? null : _uploadExcelBudget,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      tooltip: 'Upload Excel',
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: () => _addOrEditBudget(),
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
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                OutlinedButton.icon(
                  onPressed: _isUploading ? null : _uploadExcelBudget,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_isUploading ? 'Processing...' : 'Upload Excel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _addOrEditBudget(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Budget'),
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
            const SizedBox(height: 24),
            Row(
              children: [
                _webTabChip(
                  label: 'Current Month',
                  icon: Icons.calendar_month,
                  active: _selectedWebView == _BudgetWebView.currentMonth,
                  onTap: () => setState(
                    () => _selectedWebView = _BudgetWebView.currentMonth,
                  ),
                ),
                const SizedBox(width: 8),
                _webTabChip(
                  label: 'Historical Performance',
                  icon: Icons.history,
                  active: _selectedWebView == _BudgetWebView.historicalPerformance,
                  onTap: () => setState(
                    () =>
                        _selectedWebView = _BudgetWebView.historicalPerformance,
                  ),
                ),
                const SizedBox(width: 8),
                _webTabChip(
                  label: 'Spending Analytics',
                  icon: Icons.insights,
                  active: _selectedWebView == _BudgetWebView.spendingAnalytics,
                  onTap: () => setState(
                    () => _selectedWebView = _BudgetWebView.spendingAnalytics,
                  ),
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
            if (_selectedWebView == _BudgetWebView.currentMonth)
              _buildCurrentMonthSection(summary, isDark, primary)
            else if (_selectedWebView == _BudgetWebView.historicalPerformance)
              _buildHistoricalPerformanceSection(isDark, primary)
            else
              _buildSpendingAnalyticsSection(isDark, primary),
          ],
        ),
      ),
    );
  }

  List<({DateTime month, BudgetSummary summary})> _historicalSummaries() {
    final summaries = _historicalBudgets.entries
        .map((entry) {
          final parts = entry.key.split('-');
          final month = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
          return (month: month, summary: BudgetSummary(month: entry.key, budgets: entry.value));
        })
        .toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return summaries;
  }

  Color _usageColor(double ratio, Color primary) {
    if (ratio > 1) return AppColors.error;
    if (ratio >= 0.8) return AppColors.warningDark;
    return primary;
  }

  Widget _buildCurrentMonthSection(BudgetSummary summary, bool isDark, Color primary) {
    final remaining = summary.totalRemaining;
    final projectedSavings = remaining > 0 ? remaining * 0.8 : 0.0;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildBudgetComplianceCard(
                isDark: isDark,
                primary: primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSmartBudgetInsightCard(
                isDark: isDark,
                primary: primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        // AI Budget Insights
        _buildAIInsightsCard(isDark, primary),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _budgetSummaryCard(
                title: 'Total Monthly Budget',
                value: '₹${summary.totalSpent.toStringAsFixed(0)}',
                subtitle: '/ ₹${summary.totalBudget.toStringAsFixed(0)}',
                progress: summary.totalBudget > 0
                    ? (summary.totalSpent / summary.totalBudget).clamp(0.0, 1.0)
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
                valueColor: remaining >= 0 ? AppColors.success : AppColors.error,
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
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
                  child: Center(child: Text('No budgets set for this month')),
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
                  color: isDark ? AppColors.grey800 : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
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
      ],
    );
  }

  Widget _buildBudgetComplianceCard({
    required bool isDark,
    required Color primary,
  }) {
    final summaries = _historicalSummaries();

    return Container(
      padding: const EdgeInsets.all(22),
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
          const Text(
            'Budget Compliance (6 Months)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (summaries.isEmpty)
            Text(
              'No historical budget data available yet.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summaries.map((item) {
                final ratio = item.summary.totalBudget > 0
                    ? (item.summary.totalSpent / item.summary.totalBudget)
                        .clamp(0.0, 1.0)
                    : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniBar(
                          ratio == 0 ? 0.08 : ratio,
                          _usageColor(
                            item.summary.totalBudget > 0
                                ? item.summary.totalSpent /
                                    item.summary.totalBudget
                                : 0.0,
                            primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _monthLabel(item.month).split(' ').first,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(
              '${summaries.where((item) => item.summary.totalBudget > 0 && item.summary.totalSpent <= item.summary.totalBudget).length} of ${summaries.length} months stayed within budget.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmartBudgetInsightCard({
    required bool isDark,
    required Color primary,
  }) {
    final sortedBudgets = [..._budgets]
      ..sort((a, b) => b.usagePercent.compareTo(a.usagePercent));
    final focusBudget = sortedBudgets.isNotEmpty ? sortedBudgets.first : null;

    String title;
    String message;
    Color accent;
    IconData icon;

    if (focusBudget == null) {
      title = 'Smart Budget Insight';
      message = 'Add budgets to start receiving usage-based insights.';
      accent = primary;
      icon = Icons.auto_awesome;
    } else if (focusBudget.isOverBudget) {
      title = 'Overspend Alert';
      message = '${_titleCase(focusBudget.category)} is over budget by ₹${focusBudget.remaining.abs().toStringAsFixed(0)} this month. Review and adjust the category limit.';
      accent = AppColors.error;
      icon = Icons.warning_amber_rounded;
    } else if (focusBudget.usagePercent >= 85) {
      title = 'Tightest Budget';
      message = '${_titleCase(focusBudget.category)} has already used ${focusBudget.usagePercent.toStringAsFixed(0)}% of its budget, leaving ₹${focusBudget.remaining.toStringAsFixed(0)}.';
      accent = AppColors.warningDark;
      icon = Icons.trending_up_rounded;
    } else {
      final bestBudget = [..._budgets]
        ..sort((a, b) => a.usagePercent.compareTo(b.usagePercent));
      final winner = bestBudget.first;
      title = 'Best Controlled Category';
      message = '${_titleCase(winner.category)} is tracking well at ${winner.usagePercent.toStringAsFixed(0)}% used, leaving ₹${winner.remaining.toStringAsFixed(0)} for the month.';
      accent = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalPerformanceSection(bool isDark, Color primary) {
    final summaries = _historicalSummaries();
    final compliantMonths = summaries
        .where((item) => item.summary.totalBudget > 0 && item.summary.totalSpent <= item.summary.totalBudget)
        .length;
    final averageUsage = summaries.isEmpty
        ? 0.0
        : summaries
                .map((item) => item.summary.totalBudget > 0
                    ? item.summary.totalSpent / item.summary.totalBudget
                    : 0.0)
                .reduce((a, b) => a + b) /
            summaries.length;
    final latest = summaries.isNotEmpty ? summaries.last.summary : const BudgetSummary(month: '', budgets: []);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _budgetSummaryCard(
                title: 'Months On Track',
                value: '$compliantMonths/${summaries.length}',
                subtitle: 'Stayed within budget',
                valueColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Average Utilization',
                value: '${(averageUsage * 100).toStringAsFixed(0)}%',
                subtitle: 'Across the last 6 months',
                valueColor: _usageColor(averageUsage, primary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Latest Month Spend',
                value: '₹${latest.totalSpent.toStringAsFixed(0)}',
                subtitle: latest.month.isEmpty ? 'No history yet' : _monthLabel(_selectedMonth),
                valueColor: primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _buildBudgetComplianceCard(isDark: isDark, primary: primary),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
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
              const Text(
                'Month-by-Month Breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              ...summaries.reversed.map((item) {
                final ratio = item.summary.totalBudget > 0
                    ? item.summary.totalSpent / item.summary.totalBudget
                    : 0.0;
                final color = _usageColor(ratio, primary);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          _monthLabel(item.month),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: ratio.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '₹${item.summary.totalSpent.toStringAsFixed(0)} / ₹${item.summary.totalBudget.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpendingAnalyticsSection(bool isDark, Color primary) {
    final categoryStats = <String, _BudgetCategoryAnalytics>{};
    for (final budgets in _historicalBudgets.values) {
      for (final budget in budgets) {
        final existing = categoryStats[budget.category] ??
            _BudgetCategoryAnalytics(category: budget.category);
        existing.totalBudget += budget.amount;
        existing.totalSpent += budget.spent;
        existing.monthsTracked += 1;
        if (budget.isOverBudget) existing.overBudgetMonths += 1;
        categoryStats[budget.category] = existing;
      }
    }

    final categories = categoryStats.values.toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    final topCategory = categories.isNotEmpty ? categories.first : null;
    final averageMonthlySpend = categories.isEmpty
        ? 0.0
        : categories.fold<double>(0.0, (sum, item) => sum + item.totalSpent) /
            _historicalBudgets.length.clamp(1, 1000);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _budgetSummaryCard(
                title: 'Top Spend Category',
                value: topCategory == null ? '—' : _titleCase(topCategory.category),
                subtitle: topCategory == null
                    ? 'No analytics yet'
                    : '₹${topCategory.totalSpent.toStringAsFixed(0)} over ${topCategory.monthsTracked} months',
                valueColor: primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Average Monthly Spend',
                value: '₹${averageMonthlySpend.toStringAsFixed(0)}',
                subtitle: 'Across tracked categories',
                valueColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Most Volatile Category',
                value: topCategory == null ? '—' : '${topCategory.overBudgetMonths}',
                subtitle: topCategory == null
                    ? 'No over-budget months'
                    : '${_titleCase(topCategory.category)} months over budget',
                valueColor: AppColors.warningDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
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
              const Text(
                'Category Analytics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (categories.isEmpty)
                const Text('No analytics available yet for the selected history window.')
              else
                ...categories.map((item) {
                  final ratio = item.totalBudget > 0 ? item.totalSpent / item.totalBudget : 0.0;
                  final color = _usageColor(ratio, primary);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            _titleCase(item.category),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: ratio.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Spent ₹${item.totalSpent.toStringAsFixed(0)} of ₹${item.totalBudget.toStringAsFixed(0)} across ${item.monthsTracked} months',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(ratio * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _webTabChip({
    required String label,
    required IconData icon,
    required bool active,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
            Icon(
              icon,
              size: 15,
              color: active ? const Color(0xFF0D7FF2) : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF0D7FF2) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIInsightsCard(bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 22),
              const SizedBox(width: 8),
              const Text(
                'AI Budget Insights',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_isLoadingInsights)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.icon(
                  onPressed: _fetchAIInsights,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_aiAnalysis != null ? 'Refresh' : 'Analyze'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
          if (_aiInsightsError != null) ...[
            const SizedBox(height: 12),
            Text(
              _aiInsightsError!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          if (_aiAnalysis != null) ...[
            const SizedBox(height: 16),
            Text(_aiAnalysis!, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          if (_aiSuggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Suggestions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._aiSuggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
          if (_aiAnalysis == null && !_isLoadingInsights && _aiInsightsError == null) ...[
            const SizedBox(height: 8),
            Text(
              'Tap Analyze to get AI-powered insights on your budget performance.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
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

class _BudgetCategoryAnalytics {
  final String category;
  double totalBudget;
  double totalSpent;
  int monthsTracked;
  int overBudgetMonths;

  _BudgetCategoryAnalytics({
    required this.category,
    this.totalBudget = 0,
    this.totalSpent = 0,
    this.monthsTracked = 0,
    this.overBudgetMonths = 0,
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

/// Helper to aggregate amounts per category during Excel import
class _AggregatedBudget {
  double amount = 0;
  final List<String> tags = [];
}

/// Mutable row for the preview dialog — lets users edit the category
class _EditableRow {
  String category;
  final String subcategory;
  final double amount;
  final bool isValid;
  final String? validationError;

  _EditableRow({
    required this.category,
    this.subcategory = '',
    required this.amount,
    this.isValid = true,
    this.validationError,
  });

  factory _EditableRow.fromBudgetRow(BudgetRow row, String mappedCategory) {
    return _EditableRow(
      category: mappedCategory,
      subcategory: row.subcategory,
      amount: row.amount,
      isValid: row.isValid,
      validationError: row.validationError,
    );
  }
}

/// Dialog that shows a preview of parsed Excel budget rows before importing.
class _ExcelPreviewDialog extends StatefulWidget {
  final List<BudgetRow> rows;
  final String initialMonth;

  const _ExcelPreviewDialog({
    required this.rows,
    required this.initialMonth,
  });

  @override
  State<_ExcelPreviewDialog> createState() => _ExcelPreviewDialogState();
}

class _ExcelPreviewDialogState extends State<_ExcelPreviewDialog> {
  late int _selectedYear;
  late int _selectedMonth;
  late List<_EditableRow> _editableRows;

  static const _validCategories = [
    'food',
    'transport',
    'utilities',
    'shopping',
    'healthcare',
    'entertainment',
    'other',
  ];

  /// Map raw Excel category to the closest valid backend category
  static String _mapToValidCategory(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return 'other';
    if (_validCategories.contains(lower)) return lower;

    const mapping = <String, List<String>>{
      'food': ['food', 'grocery', 'groceries', 'meal', 'dining', 'provisions',
        'kitchen', 'vegetables', 'fruits', 'milk', 'snack'],
      'transport': ['transport', 'travel', 'fuel', 'petrol', 'commut',
        'vehicle', 'car', 'bike', 'parking', 'auto', 'cab'],
      'utilities': ['utility', 'utilities', 'electric', 'water', 'internet',
        'wifi', 'phone', 'mobile', 'recharge', 'bill', 'maintenance', 'rent',
        'housing', 'household', 'emi', 'act'],
      'shopping': ['shopping', 'cloth', 'fashion', 'amazon', 'flipkart',
        'online', 'gadget', 'electronics'],
      'healthcare': ['health', 'medical', 'medicine', 'doctor', 'hospital',
        'pharmacy', 'insurance', 'gym', 'fitness', 'dental', 'parlour'],
      'entertainment': ['entertainment', 'movie', 'netflix', 'subscription',
        'hobby', 'game', 'sport', 'outing', 'party', 'fun', 'leisure',
        'class', 'classes', 'yoga', 'violin', 'cello', 'music'],
    };

    for (final entry in mapping.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'other';
  }

  @override
  void initState() {
    super.initState();
    final parts = widget.initialMonth.split('-');
    _selectedYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    _selectedMonth = int.tryParse(parts[1]) ?? DateTime.now().month;

    // Convert BudgetRows to editable rows with mapped categories
    _editableRows = widget.rows.map((row) {
      return _EditableRow.fromBudgetRow(row, _mapToValidCategory(row.category));
    }).toList();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final validRows = _editableRows.where((r) => r.isValid).toList();
    final invalidRows = _editableRows.where((r) => !r.isValid).toList();
    final totalAmount =
        validRows.fold<double>(0, (sum, r) => sum + r.amount);
    final hasSubcategories =
        _editableRows.any((r) => r.subcategory.isNotEmpty);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Excel Import Preview')),
        ],
      ),
      content: SizedBox(
        width: 750,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month/Year picker row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Import to:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _selectedMonth,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: List.generate(12, (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(_monthNames[i], style: const TextStyle(fontSize: 13)),
                    )),
                    onChanged: (v) => setState(() => _selectedMonth = v!),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _selectedYear,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: List.generate(5, (i) {
                      final year = DateTime.now().year - 2 + i;
                      return DropdownMenuItem(
                        value: year,
                        child: Text('$year', style: const TextStyle(fontSize: 13)),
                      );
                    }),
                    onChanged: (v) => setState(() => _selectedYear = v!),
                  ),
                  const Spacer(),
                  Text(
                    _monthKey,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Summary bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _chip('${validRows.length} valid', AppColors.success),
                  const SizedBox(width: 8),
                  if (invalidRows.isNotEmpty)
                    _chip('${invalidRows.length} invalid', AppColors.error),
                  const Spacer(),
                  Text(
                    'Total: ₹${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Items are grouped by category during import. You can change categories below.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            // Table
            Expanded(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: {
                    0: const FixedColumnWidth(32),
                    1: const FlexColumnWidth(1.6),
                    if (hasSubcategories) 2: const FlexColumnWidth(1.8),
                    (hasSubcategories ? 3 : 2): const FlexColumnWidth(1),
                    (hasSubcategories ? 4 : 3): const FixedColumnWidth(40),
                  },
                  border: TableBorder.all(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                      ),
                      children: [
                        const _TableHeader('#'),
                        const _TableHeader('Category'),
                        if (hasSubcategories) const _TableHeader('Item'),
                        const _TableHeader('Amount'),
                        const _TableHeader(''),
                      ],
                    ),
                    ..._editableRows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: row.isValid
                              ? null
                              : AppColors.error.withValues(alpha: 0.06),
                        ),
                        children: [
                          _TableCell(
                            Text('${idx + 1}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                          _TableCell(
                            _CategoryEditor(
                              value: row.category,
                              enabled: row.isValid,
                              onChanged: (v) {
                                setState(() => row.category = v);
                              },
                            ),
                          ),
                          if (hasSubcategories)
                            _TableCell(
                              Text(row.subcategory,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          _TableCell(
                            Text(
                              row.isValid
                                  ? '₹${row.amount.toStringAsFixed(0)}'
                                  : row.validationError ?? 'Invalid',
                              style: TextStyle(
                                fontSize: 12,
                                color: row.isValid ? null : AppColors.error,
                              ),
                            ),
                          ),
                          _TableCell(
                            Icon(
                              row.isValid
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: row.isValid
                                  ? AppColors.success
                                  : AppColors.error,
                              size: 15,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            if (invalidRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Invalid rows will be skipped during import.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: validRows.isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'month': _monthKey,
                    'rows': _editableRows,
                  }),
          icon: const Icon(Icons.upload),
          label: Text('Import ${validRows.length} Items'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final Widget child;
  const _TableCell(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    );
  }
}

/// Editable category field with autocomplete suggestions + custom input.
class _CategoryEditor extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CategoryEditor({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _suggestions = [
    'food', 'transport', 'utilities', 'shopping',
    'healthcare', 'entertainment', 'other',
  ];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _titleCase(value)),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase().trim();
        if (query.isEmpty) return _suggestions;
        return _suggestions
            .where((s) => s.contains(query))
            .toList();
      },
      displayStringForOption: (s) => _titleCase(s),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return SizedBox(
          height: 30,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
            ),
            onSubmitted: (_) {
              final text = controller.text.toLowerCase().trim();
              if (text.isNotEmpty) onChanged(text);
            },
          ),
        );
      },
      onSelected: (selection) {
        onChanged(selection.toLowerCase().trim());
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(_titleCase(option), style: const TextStyle(fontSize: 13)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
