import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/savings_goal.dart';
import '../services/auth_service.dart';
import '../services/savings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

// ── Error classification ──────────────────────────────────────────────────────

class _ErrorInfo {
  final String title;
  final String detail;
  final bool canRetry; // true = Retry button; false = Sign Out button

  const _ErrorInfo({
    required this.title,
    required this.detail,
    required this.canRetry,
  });
}

_ErrorInfo _buildFriendlyError(Object e) {
  if (e is SavingsException) {
    switch (e.type) {
      case SavingsErrorType.authExpired:
        return const _ErrorInfo(
          title: 'Session Expired',
          detail:
              'Your login session has expired. Please sign out and sign back in to continue.',
          canRetry: false,
        );
      case SavingsErrorType.authInvalid:
        return const _ErrorInfo(
          title: 'Sign-in Required',
          detail:
              'Your session is no longer valid. Please sign out and sign back in.',
          canRetry: false,
        );
      case SavingsErrorType.networkError:
        return const _ErrorInfo(
          title: 'No Connection',
          detail:
              'Could not reach the server. Check your internet connection and try again.',
          canRetry: true,
        );
      case SavingsErrorType.serverError:
        return const _ErrorInfo(
          title: 'Server Error',
          detail:
              'Something went wrong on the server. Please try again in a moment.',
          canRetry: true,
        );
      case SavingsErrorType.notFound:
        return const _ErrorInfo(
          title: 'Service Unavailable',
          detail:
              'The savings service could not be reached. Please try again later.',
          canRetry: true,
        );
      case SavingsErrorType.unknown:
        return _ErrorInfo(
          title: 'Unexpected Error',
          detail: e.message,
          canRetry: true,
        );
    }
  }
  if (e is AppAuthException) {
    return const _ErrorInfo(
      title: 'Sign-in Required',
      detail: 'Please sign out and sign back in to continue.',
      canRetry: false,
    );
  }
  return _ErrorInfo(
    title: 'Unexpected Error',
    detail: e.toString(),
    canRetry: true,
  );
}

class SavingsGoalsScreen extends StatefulWidget {
  const SavingsGoalsScreen({super.key});

  @override
  State<SavingsGoalsScreen> createState() => _SavingsGoalsScreenState();
}

class _SavingsGoalsScreenState extends State<SavingsGoalsScreen> {
  final SavingsService _savingsService = SavingsService();

  List<SavingsGoal> _goals = [];
  bool _isLoading = false;
  _ErrorInfo? _errorInfo;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  /// Calls [fn] with a fresh token. On a 401, force-refreshes the token and
  /// retries once. If the retry also fails with an auth error, throws a
  /// [SavingsException] with type [SavingsErrorType.authInvalid] and a
  /// human-readable message instead of the raw Supabase gateway JSON.
  Future<T> _callSavings<T>(
    Future<T> Function(String supabaseUrl, String token) fn,
  ) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final url = auth.supabaseUrl;
    try {
      final token = await auth.getIdToken();
      return await fn(url, token);
    } on SavingsException catch (e) {
      if (e.type != SavingsErrorType.authExpired) rethrow;
      // Token may have expired — force a refresh and retry once.
      try {
        final freshToken = await auth.getIdToken(true);
        return await fn(url, freshToken);
      } on AppAuthException {
        // Refresh token itself is dead — user must sign in again.
        throw const SavingsException(
          'Your session could not be renewed. Please sign out and sign back in.',
          type: SavingsErrorType.authInvalid,
        );
      } on SavingsException catch (retryEx) {
        if (retryEx.type == SavingsErrorType.authExpired ||
            retryEx.type == SavingsErrorType.authInvalid) {
          throw const SavingsException(
            'Your session could not be renewed. Please sign out and sign back in.',
            type: SavingsErrorType.authInvalid,
          );
        }
        rethrow;
      }
    } on AppAuthException {
      throw const SavingsException(
        'You are not signed in. Please sign in to continue.',
        type: SavingsErrorType.authInvalid,
      );
    }
  }

  Future<void> _loadGoals() async {
    final gen = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorInfo = null;
    });

    try {
      final goals = await _callSavings(
        (url, token) => _savingsService.getGoals(
          supabaseUrl: url,
          idToken: token,
        ),
      );

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _goals = goals;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _errorInfo = _buildFriendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _addOrEditGoal({SavingsGoal? existing}) async {
    final result = await showDialog<_GoalFormResult>(
      context: context,
      builder: (context) => _GoalFormDialog(existing: existing),
    );

    if (result == null || !mounted) return;

    try {
      await _callSavings(
        (url, token) => _savingsService.upsertGoal(
          supabaseUrl: url,
          idToken: token,
          id: existing?.id,
          name: result.name,
          targetAmount: result.targetAmount,
          targetDate: result.targetDate,
          notes: result.notes,
        ),
      );
      if (!mounted) return;
      await _loadGoals();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Savings goal created successfully'
                : 'Savings goal updated successfully',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final info = _buildFriendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${info.title}: ${info.detail}')),
      );
    }
  }

  Future<void> _deleteGoal(SavingsGoal goal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal'),
        content: Text('Delete "${goal.name}"? This action cannot be undone.'),
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

    if (confirm != true || !mounted) return;

    try {
      await _callSavings(
        (url, token) => _savingsService.deleteGoal(
          supabaseUrl: url,
          idToken: token,
          goalId: goal.id,
        ),
      );
      if (!mounted) return;
      await _loadGoals();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Savings goal deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      final info = _buildFriendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${info.title}: ${info.detail}')),
      );
    }
  }

  Future<void> _contribute(SavingsGoal goal) async {
    final result = await showDialog<_ContributionResult>(
      context: context,
      builder: (context) => _ContributeDialog(goal: goal),
    );

    if (result == null || !mounted) return;

    try {
      await _callSavings(
        (url, token) => _savingsService.contribute(
          supabaseUrl: url,
          idToken: token,
          goalId: goal.id,
          amount: result.amount,
        ),
      );
      if (!mounted) return;
      await _loadGoals();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.amount > 0
                ? 'Rs ${result.amount.toStringAsFixed(2)} added to "${goal.name}"'
                : 'Rs ${result.amount.abs().toStringAsFixed(2)} withdrawn from "${goal.name}"',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final info = _buildFriendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${info.title}: ${info.detail}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSaved = _goals.fold<double>(0, (s, g) => s + g.currentAmount);
    final totalTarget = _goals.fold<double>(0, (s, g) => s + g.targetAmount);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Savings Goals',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track your financial targets and progress',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _addOrEditGoal(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Goal'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isLoading && _errorInfo == null && _goals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _SummaryCard(
                    totalSaved: totalSaved, totalTarget: totalTarget),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorInfo != null) {
      final info = _errorInfo!;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                info.canRetry ? AppIcons.error : Icons.lock_outline,
                size: 52,
                color: info.canRetry ? AppColors.error : AppColors.warning,
              ),
              const SizedBox(height: 12),
              Text(
                info.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                info.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.grey600),
              ),
              const SizedBox(height: 20),
              if (info.canRetry)
                ElevatedButton.icon(
                  onPressed: _loadGoals,
                  icon: const Icon(AppIcons.refresh),
                  label: const Text('Retry'),
                )
              else
                ElevatedButton.icon(
                  onPressed: () async {
                    final auth = Provider.of<AuthService>(
                        context,
                        listen: false);
                    await auth.signOut();
                    if (!mounted) return;
                    Navigator.of(context)
                        .pushReplacementNamed('/login');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_goals.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.savings_outlined, size: 64, color: AppColors.grey400),
            SizedBox(height: 12),
            Text(
              'No savings goals yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Tap \'Add Goal\' to create your first savings goal'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGoals,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        itemCount: _goals.length,
        itemBuilder: (context, index) {
          final goal = _goals[index];
          return _GoalCard(
            goal: goal,
            onEdit: () => _addOrEditGoal(existing: goal),
            onDelete: () => _deleteGoal(goal),
            onContribute: () => _contribute(goal),
          );
        },
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double totalSaved;
  final double totalTarget;

  const _SummaryCard(
      {required this.totalSaved, required this.totalTarget});

  @override
  Widget build(BuildContext context) {
    final remaining = (totalTarget - totalSaved).clamp(0.0, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Target',
                value: 'Rs ${totalTarget.toStringAsFixed(0)}',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'Saved',
                value: 'Rs ${totalSaved.toStringAsFixed(0)}',
                valueColor: AppColors.successDark,
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'Remaining',
                value: 'Rs ${remaining.toStringAsFixed(0)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Metric({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor),
        ),
      ],
    );
  }
}

// ── Goal Card ─────────────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onContribute;

  const _GoalCard({
    required this.goal,
    required this.onEdit,
    required this.onDelete,
    required this.onContribute,
  });

  String _daysRemaining(DateTime target) {
    final diff = target.difference(DateTime.now()).inDays;
    if (diff < 0) return 'Past due';
    if (diff == 0) return 'Due today';
    return '$diff day${diff == 1 ? '' : 's'} left';
  }

  @override
  Widget build(BuildContext context) {
    final percent = goal.progressPercent;
    final progressColor = goal.isCompleted
        ? AppColors.successDark
        : (percent >= 80 ? AppColors.primaryDark : AppColors.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(
                  goal.isCompleted
                      ? AppIcons.checkCircleFilled
                      : Icons.savings_outlined,
                  color: goal.isCompleted
                      ? AppColors.successDark
                      : AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goal.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (goal.isCompleted)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Completed',
                        style: TextStyle(
                            color: AppColors.successDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                PopupMenuButton<_GoalAction>(
                  onSelected: (action) {
                    if (action == _GoalAction.edit) onEdit();
                    if (action == _GoalAction.delete) onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _GoalAction.edit,
                      child: Row(children: [
                        Icon(AppIcons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: _GoalAction.delete,
                      child: Row(children: [
                        Icon(AppIcons.delete,
                            size: 16, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: AppColors.error)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Amounts row
            Row(
              children: [
                Text(
                  'Rs ${goal.currentAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: progressColor,
                  ),
                ),
                Text(
                  ' / Rs ${goal.targetAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.grey600),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 10,
                backgroundColor: AppColors.grey200,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),

            const SizedBox(height: 4),

            // Progress label + target date
            Row(
              children: [
                Text(
                  '${percent.toStringAsFixed(0)}% saved',
                  style: TextStyle(
                      color: progressColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
                const Spacer(),
                if (goal.targetDate != null)
                  Text(
                    _daysRemaining(goal.targetDate!),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.grey600),
                  ),
              ],
            ),

            if (goal.notes != null && goal.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                goal.notes!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.grey600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),

            // Contribute button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onContribute,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Contribution'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GoalAction { edit, delete }

// ── Goal Form Dialog ──────────────────────────────────────────────────────────

class _GoalFormResult {
  final String name;
  final double targetAmount;
  final DateTime? targetDate;
  final String? notes;

  const _GoalFormResult({
    required this.name,
    required this.targetAmount,
    this.targetDate,
    this.notes,
  });
}

class _GoalFormDialog extends StatefulWidget {
  final SavingsGoal? existing;

  const _GoalFormDialog({this.existing});

  @override
  State<_GoalFormDialog> createState() => _GoalFormDialogState();
}

class _GoalFormDialogState extends State<_GoalFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  DateTime? _targetDate;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
    _amountController = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.targetAmount.toStringAsFixed(2),
    );
    _notesController =
        TextEditingController(text: widget.existing?.notes ?? '');
    _targetDate = widget.existing?.targetDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'New Savings Goal' : 'Edit Savings Goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Goal Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target Amount',
                prefixText: 'Rs ',
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Target Date (optional)',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(
                  _targetDate == null
                      ? 'No date set'
                      : '${_targetDate!.day.toString().padLeft(2, '0')} '
                          '${_monthName(_targetDate!.month)} '
                          '${_targetDate!.year}',
                  style: TextStyle(
                    color: _targetDate == null
                        ? AppColors.grey400
                        : null,
                  ),
                ),
              ),
            ),
            if (_targetDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _targetDate = null),
                  child: const Text('Clear date'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a goal name')),
              );
              return;
            }
            final amount =
                double.tryParse(_amountController.text.trim());
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Please enter a valid target amount')),
              );
              return;
            }
            Navigator.pop(
              context,
              _GoalFormResult(
                name: name,
                targetAmount: amount,
                targetDate: _targetDate,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[month - 1];
  }
}

// ── Contribute Dialog ─────────────────────────────────────────────────────────

class _ContributionResult {
  final double amount;
  const _ContributionResult(this.amount);
}

class _ContributeDialog extends StatefulWidget {
  final SavingsGoal goal;
  const _ContributeDialog({required this.goal});

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  final _amountController = TextEditingController();
  bool _isWithdrawal = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isWithdrawal ? 'Withdraw Funds' : 'Add Contribution'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Goal: ${widget.goal.name}',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.grey600),
          ),
          Text(
            'Current: Rs ${widget.goal.currentAmount.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.grey600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _isWithdrawal ? 'Withdrawal Amount' : 'Contribution Amount',
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _isWithdrawal,
                onChanged: (v) =>
                    setState(() => _isWithdrawal = v ?? false),
              ),
              const Text('Withdraw funds instead'),
            ],
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
            final amount =
                double.tryParse(_amountController.text.trim());
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Please enter a valid amount')),
              );
              return;
            }
            Navigator.pop(
              context,
              _ContributionResult(_isWithdrawal ? -amount : amount),
            );
          },
          child: Text(_isWithdrawal ? 'Withdraw' : 'Add'),
        ),
      ],
    );
  }
}
