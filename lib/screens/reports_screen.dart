import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../models/budget.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import '../services/budget_service.dart';
import '../theme/app_colors.dart';

// ── Report type definitions ───────────────────────────────────────────────────

enum ReportType {
  expenseSummary,
  categoryBreakdown,
  budgetVsActual,
  monthlyTrend,
  topExpenses,
}

enum DateRangePreset {
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear,
  custom,
}

extension ReportTypeExt on ReportType {
  String get label {
    switch (this) {
      case ReportType.expenseSummary:
        return 'Expense Summary';
      case ReportType.categoryBreakdown:
        return 'Category Breakdown';
      case ReportType.budgetVsActual:
        return 'Budget vs Actual';
      case ReportType.monthlyTrend:
        return 'Monthly Trend';
      case ReportType.topExpenses:
        return 'Top Expenses';
    }
  }

  String get description {
    switch (this) {
      case ReportType.expenseSummary:
        return 'Total spend, daily avg, peak day';
      case ReportType.categoryBreakdown:
        return 'Spending split by category';
      case ReportType.budgetVsActual:
        return 'How your budget tracked against spend';
      case ReportType.monthlyTrend:
        return 'Month-over-month spending trend';
      case ReportType.topExpenses:
        return 'Your highest individual transactions';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportType.expenseSummary:
        return Icons.receipt_long_outlined;
      case ReportType.categoryBreakdown:
        return Icons.pie_chart_outline_rounded;
      case ReportType.budgetVsActual:
        return Icons.balance_outlined;
      case ReportType.monthlyTrend:
        return Icons.show_chart_rounded;
      case ReportType.topExpenses:
        return Icons.trending_up_rounded;
    }
  }
}

extension DateRangePresetExt on DateRangePreset {
  String get label {
    switch (this) {
      case DateRangePreset.thisMonth:
        return 'This Month';
      case DateRangePreset.lastMonth:
        return 'Last Month';
      case DateRangePreset.last3Months:
        return 'Last 3 Months';
      case DateRangePreset.last6Months:
        return 'Last 6 Months';
      case DateRangePreset.thisYear:
        return 'This Year';
      case DateRangePreset.custom:
        return 'Custom Range';
    }
  }

  DateTimeRange resolve() {
    final now = DateTime.now();
    switch (this) {
      case DateRangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
      case DateRangePreset.lastMonth:
        final first = DateTime(now.year, now.month - 1, 1);
        final last = DateTime(now.year, now.month, 0);
        return DateTimeRange(start: first, end: last);
      case DateRangePreset.last3Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 2, 1),
          end: now,
        );
      case DateRangePreset.last6Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 5, 1),
          end: now,
        );
      case DateRangePreset.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case DateRangePreset.custom:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
    }
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ── Config state ─────────────────────────────────────────────────────────
  ReportType _reportType = ReportType.expenseSummary;
  DateRangePreset _preset = DateRangePreset.thisMonth;
  DateTimeRange? _customRange;
  String? _filterCategory; // null = all categories

  // ── Data state ───────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  List<Expense> _expenses = [];
  List<Budget> _budgets = [];

  final ExpenseService _expenseService = ExpenseService();
  final BudgetService _budgetService = BudgetService();

  DateTimeRange get _activeRange =>
      _preset == DateRangePreset.custom && _customRange != null
          ? _customRange!
          : _preset.resolve();

  @override
  void initState() {
    super.initState();
    _runReport();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtAmt(double v) =>
      'Rs ${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  Future<void> _runReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      final url = auth.supabaseUrl;
      String token = await auth.getIdToken();
      final range = _activeRange;

      final expenses = await _expenseService.getExpenses(
        supabaseUrl: url,
        idToken: token,
        startDate: _fmt(range.start),
        endDate: _fmt(range.end),
        limit: 500,
      );

      List<Budget> budgets = [];
      if (_reportType == ReportType.budgetVsActual) {
        final month = '${range.start.year}-${range.start.month.toString().padLeft(2, '0')}';
        try {
          budgets = await _budgetService.getBudgets(
            supabaseUrl: url,
            idToken: token,
            month: month,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _budgets = budgets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange ?? DateRangePreset.thisMonth.resolve(),
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _preset = DateRangePreset.custom;
      });
      _runReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildConfigBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(error: _error!, onRetry: _runReport)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: _buildReport(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reports',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Build custom reports from your financial data.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _runReport,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Run Report'),
          ),
        ],
      ),
    );
  }

  // ── Config Bar ────────────────────────────────────────────────────────────

  Widget _buildConfigBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report Type chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportType.values.map((t) {
                final selected = t == _reportType;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(t.icon, size: 16),
                    label: Text(t.label),
                    selected: selected,
                    onSelected: (_) {
                      if (t == _reportType) return;
                      setState(() => _reportType = t);
                      _runReport();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          // Date Range + Category row
          Row(
            children: [
              // Date range
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...DateRangePreset.values.where((p) => p != DateRangePreset.custom).map((p) {
                      return ChoiceChip(
                        label: Text(p.label, style: const TextStyle(fontSize: 12)),
                        selected: _preset == p,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() => _preset = p);
                          _runReport();
                        },
                      );
                    }),
                    ActionChip(
                      label: Text(
                        _preset == DateRangePreset.custom && _customRange != null
                            ? '${_fmt(_customRange!.start)} → ${_fmt(_customRange!.end)}'
                            : 'Custom…',
                        style: const TextStyle(fontSize: 12),
                      ),
                      avatar: Icon(
                        Icons.date_range_rounded,
                        size: 15,
                        color: _preset == DateRangePreset.custom
                            ? AppColors.primary
                            : Colors.grey[600],
                      ),
                      onPressed: _pickCustomRange,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Category filter
              if (_expenses.isNotEmpty) _buildCategoryFilter(),
            ],
          ),
          // Active range display
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_fmt(_activeRange.start)}  →  ${_fmt(_activeRange.end)}   ·  ${_filtered.length} transactions',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = _expenses.map((e) => e.category).toSet().toList()..sort();
    return DropdownButton<String?>(
      value: _filterCategory,
      hint: const Text('All categories'),
      underline: const SizedBox.shrink(),
      isDense: true,
      items: [
        const DropdownMenuItem(value: null, child: Text('All categories')),
        ...categories.map((c) => DropdownMenuItem(value: c, child: Text(_capitalise(c)))),
      ],
      onChanged: (val) => setState(() => _filterCategory = val),
    );
  }

  // ── Filtered expenses ─────────────────────────────────────────────────────

  List<Expense> get _filtered {
    if (_filterCategory == null) return _expenses;
    return _expenses.where((e) => e.category == _filterCategory).toList();
  }

  // ── Report dispatcher ─────────────────────────────────────────────────────

  Widget _buildReport() {
    if (_filtered.isEmpty && _reportType != ReportType.budgetVsActual) {
      return const _EmptyState();
    }

    switch (_reportType) {
      case ReportType.expenseSummary:
        return _ReportExpenseSummary(expenses: _filtered, fmtAmt: _fmtAmt);
      case ReportType.categoryBreakdown:
        return _ReportCategoryBreakdown(expenses: _filtered, fmtAmt: _fmtAmt, capitalise: _capitalise);
      case ReportType.budgetVsActual:
        return _ReportBudgetVsActual(expenses: _expenses, budgets: _budgets, fmtAmt: _fmtAmt, capitalise: _capitalise);
      case ReportType.monthlyTrend:
        return _ReportMonthlyTrend(expenses: _filtered, fmtAmt: _fmtAmt);
      case ReportType.topExpenses:
        return _ReportTopExpenses(expenses: _filtered, fmtAmt: _fmtAmt, capitalise: _capitalise);
    }
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReportCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _StatTile({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent ?? const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bar row ───────────────────────────────────────────────────────────────────

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String valueText;
  final Color color;
  final String? trailing;

  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.valueText,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(
                trailing ?? valueText,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (ctx, constraints) {
            return Stack(
              children: [
                Container(
                  height: 8,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Report: Expense Summary ───────────────────────────────────────────────────

class _ReportExpenseSummary extends StatelessWidget {
  final List<Expense> expenses;
  final String Function(double) fmtAmt;

  const _ReportExpenseSummary({required this.expenses, required this.fmtAmt});

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const _EmptyState();

    final total = expenses.fold<double>(0, (s, e) => s + e.amount);
    final days = <String, double>{};
    for (final e in expenses) {
      final k = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      days[k] = (days[k] ?? 0) + e.amount;
    }
    final maxEntry = days.entries.reduce((a, b) => a.value > b.value ? a : b);
    final uniqueDays = days.length;
    final avgPerDay = uniqueDays > 0 ? total / uniqueDays : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportCard(
          title: 'Summary',
          child: Column(
            children: [
              Row(children: [
                _StatTile(label: 'Total Spent', value: fmtAmt(total)),
                const SizedBox(width: 12),
                _StatTile(label: 'Transactions', value: '${expenses.length}'),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatTile(label: 'Avg per Day', value: fmtAmt(avgPerDay)),
                const SizedBox(width: 12),
                _StatTile(label: 'Peak Day', value: maxEntry.key),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatTile(
                  label: 'Peak Day Spend',
                  value: fmtAmt(maxEntry.value),
                  accent: const Color(0xFFDC2626),
                ),
                const SizedBox(width: 12),
                _StatTile(label: 'Active Days', value: '$uniqueDays days'),
              ]),
            ],
          ),
        ),
        _ReportCard(
          title: 'Daily Spend',
          child: Column(
            children: days.entries
                .toList()
                .sorted((a, b) => a.key.compareTo(b.key))
                .take(30)
                .map((e) => _BarRow(
                      label: e.key,
                      value: e.value,
                      max: maxEntry.value,
                      valueText: fmtAmt(e.value),
                      color: AppColors.primary,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ── Report: Category Breakdown ────────────────────────────────────────────────

class _ReportCategoryBreakdown extends StatelessWidget {
  final List<Expense> expenses;
  final String Function(double) fmtAmt;
  final String Function(String) capitalise;

  const _ReportCategoryBreakdown({
    required this.expenses,
    required this.fmtAmt,
    required this.capitalise,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const _EmptyState();

    final totals = <String, double>{};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = totals.values.fold<double>(0, (s, v) => s + v);
    final maxVal = sorted.first.value;

    final palette = [
      const Color(0xFF258CF4),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
      const Color(0xFF64748B),
      const Color(0xFF6366F1),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportCard(
          title: 'By Category  ·  ${fmtAmt(total)} total',
          child: Column(
            children: sorted.asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value;
              final pct = total > 0 ? (cat.value / total * 100) : 0.0;
              return _BarRow(
                label: capitalise(cat.key),
                value: cat.value,
                max: maxVal,
                valueText: fmtAmt(cat.value),
                color: palette[idx % palette.length],
                trailing: '${pct.toStringAsFixed(1)}%  ${fmtAmt(cat.value)}',
              );
            }).toList(),
          ),
        ),
        _ReportCard(
          title: 'Transaction Count by Category',
          child: Column(
            children: () {
              final counts = <String, int>{};
              for (final e in expenses) {
                counts[e.category] = (counts[e.category] ?? 0) + 1;
              }
              final cSorted = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final maxCount = cSorted.first.value.toDouble();
              return cSorted.asMap().entries.map((entry) {
                final cat = entry.value;
                return _BarRow(
                  label: capitalise(cat.key),
                  value: cat.value.toDouble(),
                  max: maxCount,
                  valueText: '${cat.value}',
                  color: palette[entry.key % palette.length],
                  trailing: '${cat.value} txns',
                );
              }).toList();
            }(),
          ),
        ),
      ],
    );
  }
}

// ── Report: Budget vs Actual ──────────────────────────────────────────────────

class _ReportBudgetVsActual extends StatelessWidget {
  final List<Expense> expenses;
  final List<Budget> budgets;
  final String Function(double) fmtAmt;
  final String Function(String) capitalise;

  const _ReportBudgetVsActual({
    required this.expenses,
    required this.budgets,
    required this.fmtAmt,
    required this.capitalise,
  });

  @override
  Widget build(BuildContext context) {
    if (budgets.isEmpty && expenses.isEmpty) return const _EmptyState();

    final spendByCategory = <String, double>{};
    for (final e in expenses) {
      spendByCategory[e.category] = (spendByCategory[e.category] ?? 0) + e.amount;
    }

    final rows = <Map<String, dynamic>>[];
    for (final b in budgets) {
      rows.add({
        'category': b.category,
        'budget': b.amount,
        'actual': spendByCategory[b.category] ?? 0.0,
      });
    }
    // Categories with spend but no budget
    for (final e in spendByCategory.entries) {
      if (!budgets.any((b) => b.category == e.key)) {
        rows.add({'category': e.key, 'budget': 0.0, 'actual': e.value});
      }
    }
    rows.sort((a, b) => (b['actual'] as double).compareTo(a['actual'] as double));

    final totalBudget = rows.fold<double>(0, (s, r) => s + (r['budget'] as double));
    final totalActual = rows.fold<double>(0, (s, r) => s + (r['actual'] as double));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportCard(
          title: 'Overview',
          child: Column(
            children: [
              Row(children: [
                _StatTile(label: 'Total Budgeted', value: fmtAmt(totalBudget)),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Total Actual',
                  value: fmtAmt(totalActual),
                  accent: totalActual > totalBudget && totalBudget > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatTile(
                  label: 'Variance',
                  value: fmtAmt((totalBudget - totalActual).abs()),
                  accent: totalActual > totalBudget
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                ),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Status',
                  value: totalBudget == 0
                      ? 'No budget set'
                      : totalActual <= totalBudget
                          ? 'On track'
                          : 'Over budget',
                  accent: totalActual > totalBudget
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                ),
              ]),
            ],
          ),
        ),
        _ReportCard(
          title: 'Category Breakdown',
          child: Column(
            children: rows.map((r) {
              final cat = r['category'] as String;
              final budget = r['budget'] as double;
              final actual = r['actual'] as double;
              final isOver = budget > 0 && actual > budget;
              final barMax = (budget > actual ? budget : actual) * 1.05;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            capitalise(cat),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (isOver)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Over',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Budget bar
                    if (budget > 0)
                      _BarRow(
                        label: 'Budgeted',
                        value: budget,
                        max: barMax,
                        valueText: fmtAmt(budget),
                        color: const Color(0xFF94A3B8),
                      ),
                    // Actual bar
                    _BarRow(
                      label: 'Actual',
                      value: actual,
                      max: barMax,
                      valueText: fmtAmt(actual),
                      color: isOver ? const Color(0xFFDC2626) : const Color(0xFF258CF4),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Report: Monthly Trend ─────────────────────────────────────────────────────

class _ReportMonthlyTrend extends StatelessWidget {
  final List<Expense> expenses;
  final String Function(double) fmtAmt;

  const _ReportMonthlyTrend({required this.expenses, required this.fmtAmt});

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const _EmptyState();

    final monthly = <String, double>{};
    for (final e in expenses) {
      final k = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      monthly[k] = (monthly[k] ?? 0) + e.amount;
    }
    final sorted = monthly.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (sorted.isEmpty) return const _EmptyState();

    final realMax = sorted.fold<double>(0, (p, e) => e.value > p ? e.value : p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportCard(
          title: 'Month-over-Month Spend',
          child: Column(
            children: sorted.map((e) {
              final prev = sorted.indexOf(e) > 0
                  ? sorted[sorted.indexOf(e) - 1].value
                  : null;
              final change = prev != null && prev > 0
                  ? ((e.value - prev) / prev * 100)
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        if (change != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: change > 0
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: change > 0
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(fmtAmt(e.value),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(builder: (ctx, c) {
                      final fraction = realMax <= 0 ? 0.0 : (e.value / realMax).clamp(0.0, 1.0);
                      final isHighest = e.value == realMax;
                      return Stack(children: [
                        Container(
                          height: 10,
                          width: c.maxWidth,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Container(
                          height: 10,
                          width: c.maxWidth * fraction,
                          decoration: BoxDecoration(
                            color: isHighest
                                ? const Color(0xFFDC2626)
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ]);
                    }),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        _ReportCard(
          title: 'Stats',
          child: Column(
            children: [
              Row(children: [
                _StatTile(
                  label: 'Lowest Month',
                  value: sorted.reduce((a, b) => a.value < b.value ? a : b).key,
                ),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Highest Month',
                  value: sorted.reduce((a, b) => a.value > b.value ? a : b).key,
                  accent: const Color(0xFFDC2626),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatTile(
                  label: 'Avg / Month',
                  value: fmtAmt(
                    monthly.values.fold<double>(0, (s, v) => s + v) /
                        monthly.length,
                  ),
                ),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Months Tracked',
                  value: '${monthly.length}',
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Report: Top Expenses ──────────────────────────────────────────────────────

class _ReportTopExpenses extends StatelessWidget {
  final List<Expense> expenses;
  final String Function(double) fmtAmt;
  final String Function(String) capitalise;

  const _ReportTopExpenses({
    required this.expenses,
    required this.fmtAmt,
    required this.capitalise,
  });

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const _EmptyState();

    final sorted = [...expenses]..sort((a, b) => b.amount.compareTo(a.amount));
    final top = sorted.take(50).toList();
    final maxAmt = top.first.amount;
    final total = expenses.fold<double>(0, (s, e) => s + e.amount);

    const palette = [
      Color(0xFF258CF4),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
    ];
    final cats = <String>[];
    for (final e in top) {
      if (!cats.contains(e.category)) cats.add(e.category);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportCard(
          title: 'Overview',
          child: Row(children: [
            _StatTile(label: 'Showing top', value: '${top.length} txns'),
            const SizedBox(width: 12),
            _StatTile(
              label: 'Top ${top.length} = % of total',
              value: total > 0
                  ? '${(top.fold<double>(0, (s, e) => s + e.amount) / total * 100).toStringAsFixed(1)}%'
                  : '—',
            ),
          ]),
        ),
        _ReportCard(
          title: 'Top Transactions',
          child: Column(
            children: top.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final catIdx = cats.indexOf(e.category);
              final color = palette[catIdx % palette.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${capitalise(e.category)}  ·  ${_fmtDate(e.date)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtAmt(e.amount),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: LinearProgressIndicator(
                            value: maxAmt > 0 ? e.amount / maxAmt : 0,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: color,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 36, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text(
              'No data for this range',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B)),
            ),
            SizedBox(height: 4),
            Text(
              'Try a different date range or add more expenses.',
              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: Colors.redAccent),
            const SizedBox(height: 10),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ── Extension helpers ─────────────────────────────────────────────────────────

extension _IterableExt<T> on Iterable<T> {
  Iterable<T> sorted(int Function(T, T) compare) {
    final list = toList();
    list.sort(compare);
    return list;
  }
}
