import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/planner_item.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/family_planner_service.dart';
import '../services/investment_service.dart';
import '../theme/app_colors.dart';

class KidsDashboardScreen extends StatefulWidget {
  const KidsDashboardScreen({super.key});

  @override
  State<KidsDashboardScreen> createState() => _KidsDashboardScreenState();
}

class _KidsDashboardScreenState extends State<KidsDashboardScreen> {
  final ExpenseService _expenseService = ExpenseService();
  final BudgetService _budgetService = BudgetService();
  final FamilyPlannerService _plannerService = FamilyPlannerService();
  final InvestmentService _investmentService = InvestmentService();

  final TextEditingController _kidNameCtrl = TextEditingController();

  final List<String> _kidNames = [];
  List<Expense> _expenses = [];
  List<Budget> _budgets = [];
  List<PlannerItem> _plannerItems = [];
  List<Investment> _investments = [];

  bool _isLoading = true;
  String? _error;

  static const List<String> _educationKeywords = [
    'school',
    'fees',
    'fee',
    'tuition',
    'books',
    'book',
    'stationary',
    'stationery',
    'school van',
    'transport',
    'uniform',
    'exam',
    'class',
    'coaching',
  ];

  static const List<String> _moneySentKeywords = [
    'sent',
    'send',
    'transfer',
    'upi',
    'allowance',
    'pocket money',
    'recharge',
    'to kid',
  ];

  static const List<String> _schoolEventKeywords = [
    'parent teacher',
    'ptm',
    'sports day',
    'graduation',
    'annual day',
    'school meeting',
    'school event',
    'open house',
    'orientation',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _kidNameCtrl.dispose();
    super.dispose();
  }

  Future<T> _callWithAuthRetry<T>(
    Future<T> Function(String supabaseUrl, String token) fn,
  ) async {
    final auth = context.read<AuthService>();
    final supabaseUrl = auth.supabaseUrl;

    try {
      final token = await auth.getIdToken();
      return await fn(supabaseUrl, token);
    } on AppAuthException {
      final freshToken = await auth.getIdToken(true);
      return await fn(supabaseUrl, freshToken);
    }
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 2, 1);
      final startDate = _fmtDate(start);
      final endDate = _fmtDate(now);

      final expenses = await _callWithAuthRetry(
        (url, token) => _expenseService.getExpenses(
          supabaseUrl: url,
          idToken: token,
          limit: 500,
          startDate: startDate,
          endDate: endDate,
        ),
      );

      final budgetMonths = <String>{
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
        '${DateTime(now.year, now.month - 1, 1).year}-${DateTime(now.year, now.month - 1, 1).month.toString().padLeft(2, '0')}',
      };

      final allBudgets = <Budget>[];
      for (final month in budgetMonths) {
        try {
          final monthBudgets = await _callWithAuthRetry(
            (url, token) => _budgetService.getBudgets(
              supabaseUrl: url,
              idToken: token,
              month: month,
            ),
          );
          allBudgets.addAll(monthBudgets);
        } catch (_) {
          // Continue even if one month fails.
        }
      }

      List<PlannerItem> plannerItems = [];
      try {
        plannerItems = await _callWithAuthRetry(
          (url, token) => _plannerService.getItems(
            supabaseUrl: url,
            idToken: token,
          ),
        );
      } catch (_) {
        // Planner may not be available in all environments yet.
      }

      List<Investment> investments = [];
      try {
        investments = await _callWithAuthRetry(
          (url, token) => _investmentService.getInvestments(
            supabaseUrl: url,
            idToken: token,
          ),
        );
      } catch (_) {
        // Investments backend may not be available in all environments yet.
      }

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _budgets = allBudgets;
        _plannerItems = plannerItems;
        _investments = investments;
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

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtCurrency(double amount) {
    final value = amount.toStringAsFixed(2);
    return 'Rs $value';
  }

  String _normalize(String input) => input.toLowerCase().trim();

  bool _containsAny(String source, List<String> keywords) {
    final text = _normalize(source);
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  bool _containsKidName(String source) {
    if (_kidNames.isEmpty) return false;
    final text = _normalize(source);
    for (final name in _kidNames) {
      if (text.contains(_normalize(name))) return true;
    }
    return false;
  }

  String _expenseBlob(Expense e) {
    return '${e.category} ${e.description} ${e.notes ?? ''} ${e.tags.join(' ')}'
        .toLowerCase();
  }

  bool _isKidEducationExpense(Expense e) {
    final text = _expenseBlob(e);
    final hasKidSignal = _containsKidName(text) || _kidNames.isEmpty;
    return hasKidSignal && _containsAny(text, _educationKeywords);
  }

  bool _isMoneySentExpense(Expense e) {
    final text = _expenseBlob(e);
    final hasKidSignal = _containsKidName(text) || _kidNames.isEmpty;
    return hasKidSignal && _containsAny(text, _moneySentKeywords);
  }

  bool _isKidBudget(Budget b) {
    final text = '${b.category} ${b.tags.join(' ')}'.toLowerCase();
    final hasKidSignal = _containsKidName(text) || _kidNames.isEmpty;
    return hasKidSignal && _containsAny(text, _educationKeywords);
  }

  bool _kidNameMatches(String? childName) {
    if (childName == null || childName.trim().isEmpty) return false;
    if (_kidNames.isEmpty) return true;
    final normalized = _normalize(childName);
    for (final name in _kidNames) {
      if (normalized.contains(_normalize(name)) ||
          _normalize(name).contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  bool _isKidPlannerEvent(PlannerItem item) {
    final text = '${item.title} ${item.description ?? ''} ${item.location ?? ''}'
        .toLowerCase();
    final hasKidSignal = _containsKidName(text) ||
        item.type == PlannerItemType.birthday ||
        item.type == PlannerItemType.event ||
        item.type == PlannerItemType.reminder;
    return hasKidSignal &&
        (_containsAny(text, _schoolEventKeywords) ||
            item.type == PlannerItemType.birthday ||
            item.type == PlannerItemType.event ||
            item.type == PlannerItemType.vacation);
  }

  List<Expense> get _kidTaggedExpenses {
    return _expenses
        .where((e) => _isKidEducationExpense(e) || _containsKidName(_expenseBlob(e)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Expense> get _moneySentExpenses {
    return _expenses.where(_isMoneySentExpense).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Investment> get _kidInvestments {
    return _investments.where((inv) => _kidNameMatches(inv.childName)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Budget> get _kidBudgets {
    return _budgets.where(_isKidBudget).toList();
  }

  List<PlannerItem> get _kidPlannerEvents {
    final now = DateTime.now();
    return _plannerItems
        .where(_isKidPlannerEvent)
        .where((item) => !item.startDate.isBefore(now.subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  double get _moneySentTotal =>
      _moneySentExpenses.fold<double>(0, (sum, e) => sum + e.amount);

  double get _kidExpenseTotal =>
      _kidTaggedExpenses.fold<double>(0, (sum, e) => sum + e.amount);

  double get _kidBudgetTotal =>
      _kidBudgets.fold<double>(0, (sum, b) => sum + b.amount);

  double get _kidBudgetSpent =>
      _kidBudgets.fold<double>(0, (sum, b) => sum + b.spent);

  double get _kidInvestmentsTotal =>
      _kidInvestments.fold<double>(0, (sum, inv) => sum + inv.currentValue);

  void _addKidName() {
    final name = _kidNameCtrl.text.trim();
    if (name.isEmpty) return;

    final exists = _kidNames.any((n) => _normalize(n) == _normalize(name));
    if (exists) {
      _kidNameCtrl.clear();
      return;
    }

    setState(() {
      _kidNames.add(name);
      _kidNameCtrl.clear();
    });
  }

  void _removeKidName(String name) {
    setState(() {
      _kidNames.remove(name);
    });
  }

  String _formatDate(DateTime date) {
    const months = [
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
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceHoverLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(error: _error!, onRetry: _loadAllData)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const Divider(height: 1, color: AppColors.borderLight),
                        const SizedBox(height: 12),
                        _buildKidNameBar(),
                        const SizedBox(height: 12),
                        _buildStats(),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Money Sent to Kids',
                                  subtitle:
                                      'Transfers, allowance, pocket money, and similar sends',
                                  emptyText:
                                      'No kid-related money sends found for current data.',
                                  children: _moneySentExpenses.take(8).map((e) {
                                    return _ExpenseInsightTile(
                                      title: e.description,
                                      subtitle:
                                          '${e.category} · ${_formatDate(e.date)}',
                                      amount: _fmtCurrency(e.amount),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _InsightListCard(
                                  title: 'School & Kids Planner',
                                  subtitle:
                                      'PTMs, sports day, graduation, birthdays, and upcoming events',
                                  emptyText:
                                      'No upcoming kid-related planner events found.',
                                  children: _kidPlannerEvents.take(8).map((item) {
                                    return _PlannerInsightTile(
                                      item: item,
                                      dateLabel: _formatDate(item.startDate),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Kid Tagged Expenses',
                                  subtitle:
                                      'Education and kid-related expense signals (books, fees, van, etc.)',
                                  emptyText: 'No kid-tagged expenses found.',
                                  children: _kidTaggedExpenses.take(8).map((e) {
                                    return _ExpenseInsightTile(
                                      title: e.description,
                                      subtitle:
                                          '${e.category} · ${_formatDate(e.date)}',
                                      amount: _fmtCurrency(e.amount),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Kids Budget & Investments',
                                  subtitle:
                                      'Budget buckets tagged to kids and real investments linked by child name',
                                  emptyText:
                                      'No kid budgets or child-linked investments available yet.',
                                  children: [
                                    ..._kidBudgets.take(5).map((b) {
                                      return _BudgetInsightTile(
                                        category: b.category,
                                        month: b.month,
                                        budgetAmount: _fmtCurrency(b.amount),
                                        spentAmount: _fmtCurrency(b.spent),
                                      );
                                    }),
                                    ..._kidInvestments.take(5).map((inv) {
                                      return _InvestmentInsightTile(
                                        title: inv.name,
                                        subtitle:
                                            '${inv.type} · ${inv.childName ?? 'Unassigned'}',
                                        amount: _fmtCurrency(inv.currentValue),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          const Text(
            'Kids Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.activeBlue.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.child_care, size: 14, color: AppColors.activeBlue),
                const SizedBox(width: 4),
                Text(
                  'Education · Money · Events',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.activeBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKidNameBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kid Name Lens',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Add kid names to tighten matching for expenses, planner events, and child-linked investments.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kidNameCtrl,
                  onSubmitted: (_) => _addKidName(),
                  decoration: const InputDecoration(
                    hintText: 'Enter kid name (e.g., Aarav)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addKidName,
                child: const Text('Add'),
              ),
            ],
          ),
          if (_kidNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kidNames.map((name) {
                return Chip(
                  label: Text(name),
                  onDeleted: () => _removeKidName(name),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats() {
    final budgetUsage = _kidBudgetTotal > 0
        ? (_kidBudgetSpent / _kidBudgetTotal).clamp(0.0, 1.0)
        : 0.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
        _StatCard(
          title: 'Money Sent',
          value: _fmtCurrency(_moneySentTotal),
          subtitle: '${_moneySentExpenses.length} entries',
          color: const Color(0xFF0EA5E9),
        ),
        const SizedBox(width: 10),
        _StatCard(
          title: 'Kid Expenses',
          value: _fmtCurrency(_kidExpenseTotal),
          subtitle: '${_kidTaggedExpenses.length} entries',
          color: AppColors.activeBlue,
        ),
        const SizedBox(width: 10),
        _StatCard(
          title: 'School Events',
          value: '${_kidPlannerEvents.length}',
          subtitle: 'Upcoming + active',
          color: const Color(0xFF9333EA),
        ),
        const SizedBox(width: 10),
        _StatCard(
          title: 'Budget Usage',
          value: _kidBudgetTotal > 0
              ? '${(budgetUsage * 100).toStringAsFixed(0)}%'
              : '—',
          subtitle: _kidBudgetTotal > 0
              ? '${_fmtCurrency(_kidBudgetSpent)} / ${_fmtCurrency(_kidBudgetTotal)}'
              : 'No kid budget found',
          color: const Color(0xFFF59E0B),
        ),
        const SizedBox(width: 10),
        _StatCard(
          title: 'Investments',
          value: _fmtCurrency(_kidInvestmentsTotal),
          subtitle: '${_kidInvestments.length} linked records',
          color: AppColors.scoreGood,
        ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightListCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyText;
  final List<Widget> children;

  const _InsightListCard({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  )
                : ListView.separated(
                    itemCount: children.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => children[index],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseInsightTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;

  const _ExpenseInsightTile({
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHoverLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BudgetInsightTile extends StatelessWidget {
  final String category;
  final String month;
  final String budgetAmount;
  final String spentAmount;

  const _BudgetInsightTile({
    required this.category,
    required this.month,
    required this.budgetAmount,
    required this.spentAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHoverLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.savings_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Month: $month · Spent: $spentAmount',
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            budgetAmount,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InvestmentInsightTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;

  const _InvestmentInsightTile({
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHoverLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.query_stats_rounded, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PlannerInsightTile extends StatelessWidget {
  final PlannerItem item;
  final String dateLabel;

  const _PlannerInsightTile({
    required this.item,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = PlannerItem.colorForType(item.type);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHoverLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(PlannerItem.iconForType(item.type), size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${PlannerItem.typeLabel(item.type)} · $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ],
            ),
          ),
        ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.scorePoor, size: 34),
            const SizedBox(height: 10),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
