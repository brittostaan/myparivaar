import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../models/planner_item.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/family_planner_service.dart';
import '../services/family_service.dart';
import '../services/investment_service.dart';
import '../theme/app_colors.dart';

class ParentsDashboardScreen extends StatefulWidget {
  const ParentsDashboardScreen({super.key});

  @override
  State<ParentsDashboardScreen> createState() => _ParentsDashboardScreenState();
}

class _ParentsDashboardScreenState extends State<ParentsDashboardScreen> {
  final ExpenseService _expenseService = ExpenseService();
  final BudgetService _budgetService = BudgetService();
  final FamilyPlannerService _plannerService = FamilyPlannerService();
  final InvestmentService _investmentService = InvestmentService();

  final TextEditingController _parentAliasCtrl = TextEditingController();

  List<Member> _members = [];
  List<String> _parentNames = [];
  List<Expense> _expenses = [];
  List<Budget> _budgets = [];
  List<PlannerItem> _plannerItems = [];
  List<Investment> _investments = [];

  bool _isLoading = true;
  String? _error;

  static const List<String> _parentKeywords = [
    'mom',
    'mother',
    'dad',
    'father',
    'amma',
    'appa',
    'mummy',
    'papa',
    'parent',
    'parents',
  ];

  static const List<String> _healthKeywords = [
    'health',
    'checkup',
    'doctor',
    'hospital',
    'clinic',
    'medical',
    'medicine',
    'medicines',
    'lab',
    'test',
    'scan',
    'xray',
    'dental',
    'vision',
    'eye',
    'physio',
    'surgery',
  ];

  static const List<String> _insuranceKeywords = [
    'insurance',
    'medical insurance',
    'health insurance',
    'mediclaim',
    'policy',
    'premium',
    'renew',
    'renewal',
    'cover',
    'coverage',
    'retirement',
    'pension',
  ];

  static const List<String> _supportBudgetKeywords = [
    'medical',
    'health',
    'doctor',
    'hospital',
    'insurance',
    'care',
    'support',
    'pharmacy',
    'medicine',
    'wellness',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _parentAliasCtrl.dispose();
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

      List<Member> members = [];
      try {
        final auth = context.read<AuthService>();
        final familyService = FamilyService(
          supabaseUrl: auth.supabaseUrl,
          authService: auth,
        );
        members = await familyService.fetchMembers();
      } catch (_) {
        members = const [];
      }

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _budgets = allBudgets;
        _plannerItems = plannerItems;
        _investments = investments;
        _members = members;
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

  String _fmtCurrency(double amount) => 'Rs ${amount.toStringAsFixed(2)}';

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

  String _normalize(String input) => input.toLowerCase().trim();

  bool _containsAny(String source, List<String> keywords) {
    final text = _normalize(source);
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  bool _containsParentSignal(String source) {
    final text = _normalize(source);
    if (_containsAny(text, _parentKeywords)) return true;
    if (_parentNames.isEmpty) return false;
    for (final name in _parentNames) {
      if (text.contains(_normalize(name))) return true;
    }
    return false;
  }

  String _plannerBlob(PlannerItem item) {
    return '${item.title} ${item.description ?? ''} ${item.location ?? ''}'
        .toLowerCase();
  }

  String _expenseBlob(Expense expense) {
    return '${expense.category} ${expense.description} ${expense.notes ?? ''} ${expense.tags.join(' ')}'
        .toLowerCase();
  }

  String _investmentBlob(Investment investment) {
    return '${investment.name} ${investment.type} ${investment.provider ?? ''} ${investment.notes ?? ''}'
        .toLowerCase();
  }

  bool _isParentCarePlannerItem(PlannerItem item) {
    final text = _plannerBlob(item);
    return _containsParentSignal(text) &&
        (_containsAny(text, _healthKeywords) ||
            _containsAny(text, _insuranceKeywords) ||
            item.type == PlannerItemType.reminder ||
            item.type == PlannerItemType.task);
  }

  bool _isParentMilestonePlannerItem(PlannerItem item) {
    final text = _plannerBlob(item);
    return _containsParentSignal(text) &&
        (item.type == PlannerItemType.birthday ||
            item.type == PlannerItemType.anniversary ||
            item.type == PlannerItemType.event);
  }

  bool _isParentExpense(Expense expense) {
    final text = _expenseBlob(expense);
    return _containsParentSignal(text) &&
        (_containsAny(text, _healthKeywords) ||
            _containsAny(text, _insuranceKeywords) ||
            _containsAny(text, _supportBudgetKeywords));
  }

  bool _isParentBudget(Budget budget) {
    final text = '${budget.category} ${budget.tags.join(' ')}'.toLowerCase();
    return _containsParentSignal(text) ||
        _containsAny(text, _supportBudgetKeywords) ||
        _containsAny(text, _insuranceKeywords);
  }

  bool _isParentInvestment(Investment investment) {
    final text = _investmentBlob(investment);
    return (_containsParentSignal(text) ||
            investment.type.toLowerCase().contains('insurance')) &&
        (_containsAny(text, _insuranceKeywords) ||
            _containsAny(text, _healthKeywords) ||
            investment.type.toLowerCase().contains('insurance') ||
            investment.type.toLowerCase().contains('retirement'));
  }

  List<String> get _householdNameSuggestions {
    final names = <String>{
      for (final member in _members)
        if ((member.displayName ?? '').trim().isNotEmpty)
          member.displayName!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.where((name) {
      return !_parentNames.any((existing) => _normalize(existing) == _normalize(name));
    }).toList();
  }

  List<PlannerItem> get _careReminders {
    final now = DateTime.now();
    return _plannerItems
        .where(_isParentCarePlannerItem)
        .where((item) => !item.startDate.isBefore(now.subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<PlannerItem> get _familyMilestones {
    final now = DateTime.now();
    return _plannerItems
        .where(_isParentMilestonePlannerItem)
        .where((item) => !item.startDate.isBefore(now.subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<Expense> get _parentExpenses {
    return _expenses.where(_isParentExpense).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Budget> get _parentBudgets => _budgets.where(_isParentBudget).toList();

  List<Investment> get _parentInvestments {
    return _investments.where(_isParentInvestment).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  double get _parentExpenseTotal =>
      _parentExpenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  double get _parentBudgetTotal =>
      _parentBudgets.fold<double>(0, (sum, budget) => sum + budget.amount);

  double get _parentBudgetSpent =>
      _parentBudgets.fold<double>(0, (sum, budget) => sum + budget.spent);

  double get _parentInvestmentValue => _parentInvestments.fold<double>(
      0, (sum, investment) => sum + investment.currentValue);

  void _addParentName([String? value]) {
    final name = (value ?? _parentAliasCtrl.text).trim();
    if (name.isEmpty) return;

    final exists = _parentNames.any((existing) => _normalize(existing) == _normalize(name));
    if (exists) {
      _parentAliasCtrl.clear();
      return;
    }

    setState(() {
      _parentNames.add(name);
      _parentAliasCtrl.clear();
    });
  }

  void _removeParentName(String name) {
    setState(() {
      _parentNames.remove(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final budgetUsage = _parentBudgetTotal > 0
        ? (_parentBudgetSpent / _parentBudgetTotal).clamp(0.0, 1.0)
        : 0.0;

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
                        _buildParentLensBar(),
                        const SizedBox(height: 12),
                        _buildStats(budgetUsage),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Care & Health Reminders',
                                  subtitle:
                                      'Checkups, renewals, medicines, and support tasks for parents',
                                  emptyText:
                                      'No parent care reminders found in planner data.',
                                  children: _careReminders.take(8).map((item) {
                                    return _PlannerInsightTile(
                                      item: item,
                                      dateLabel: _formatDate(item.startDate),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Insurance & Parent Investments',
                                  subtitle:
                                      'Medical insurance, retirement, and parent-linked investment coverage',
                                  emptyText:
                                      'No parent-related investment coverage found yet.',
                                  children: _parentInvestments.take(8).map((investment) {
                                    return _InvestmentInsightTile(
                                      title: investment.name,
                                      subtitle:
                                          '${investment.type} · ${investment.provider?.isNotEmpty == true ? investment.provider : 'Provider not set'}',
                                      amount: _fmtCurrency(investment.currentValue),
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
                                  title: 'Parent Support Expenses',
                                  subtitle:
                                      'Medical, insurance, pharmacy, and care spending visible to children',
                                  emptyText: 'No parent-related expenses found.',
                                  children: _parentExpenses.take(8).map((expense) {
                                    return _ExpenseInsightTile(
                                      title: expense.description,
                                      subtitle:
                                          '${expense.category} · ${_formatDate(expense.date)}',
                                      amount: _fmtCurrency(expense.amount),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _InsightListCard(
                                  title: 'Parent Budgets & Family Moments',
                                  subtitle:
                                      'Budget coverage for care plus birthdays, anniversaries, and parent milestones',
                                  emptyText:
                                      'No parent budgets or milestones found yet.',
                                  children: [
                                    ..._parentBudgets.take(4).map((budget) {
                                      return _BudgetInsightTile(
                                        category: budget.category,
                                        month: budget.month,
                                        budgetAmount: _fmtCurrency(budget.amount),
                                        spentAmount: _fmtCurrency(budget.spent),
                                      );
                                    }),
                                    ..._familyMilestones.take(4).map((item) {
                                      return _PlannerInsightTile(
                                        item: item,
                                        dateLabel: _formatDate(item.startDate),
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
            'Parents Dashboard',
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
                const Icon(Icons.family_restroom, size: 14, color: AppColors.activeBlue),
                const SizedBox(width: 4),
                Text(
                  'Health · Insurance · Support',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.activeBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentLensBar() {
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
            'Parent Lens',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Add parent names or aliases like Mom and Dad to sharpen matching for planner reminders, expenses, and investments.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _parentAliasCtrl,
                  onSubmitted: (_) => _addParentName(),
                  decoration: const InputDecoration(
                    hintText: 'Enter parent name or alias (e.g., Mom, Dad, Kavitha)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addParentName,
                child: const Text('Add'),
              ),
            ],
          ),
          if (_householdNameSuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Household suggestions',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _householdNameSuggestions.take(6).map((name) {
                return ActionChip(
                  label: Text(name),
                  onPressed: () => _addParentName(name),
                );
              }).toList(),
            ),
          ],
          if (_parentNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _parentNames.map((name) {
                return Chip(
                  label: Text(name),
                  onDeleted: () => _removeParentName(name),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(double budgetUsage) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatCard(
            title: 'Care Reminders',
            value: '${_careReminders.length}',
            subtitle: 'Upcoming tasks and renewals',
            color: AppColors.activeBlue,
          ),
          const SizedBox(width: 10),
          _StatCard(
            title: 'Health Spend',
            value: _fmtCurrency(_parentExpenseTotal),
            subtitle: '${_parentExpenses.length} tracked expenses',
            color: AppColors.scorePoor,
          ),
          const SizedBox(width: 10),
          _StatCard(
            title: 'Coverage Value',
            value: _fmtCurrency(_parentInvestmentValue),
            subtitle: '${_parentInvestments.length} insurance or retirement records',
            color: AppColors.scoreGood,
          ),
          const SizedBox(width: 10),
          _StatCard(
            title: 'Budget Coverage',
            value: _parentBudgetTotal > 0
                ? '${(budgetUsage * 100).toStringAsFixed(0)}%'
                : '—',
            subtitle: _parentBudgetTotal > 0
                ? '${_fmtCurrency(_parentBudgetSpent)} / ${_fmtCurrency(_parentBudgetTotal)}'
                : 'No parent budget found',
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          _StatCard(
            title: 'Family Moments',
            value: '${_familyMilestones.length}',
            subtitle: 'Birthdays, anniversaries, and parent events',
            color: const Color(0xFF9333EA),
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
      width: 210,
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
          const Icon(Icons.health_and_safety_outlined, size: 16),
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