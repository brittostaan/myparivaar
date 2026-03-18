import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/investment.dart';
import '../models/member.dart';
import '../services/auth_service.dart';
import '../services/family_service.dart';
import '../services/investment_service.dart';
import '../theme/app_colors.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final InvestmentService _investmentService = InvestmentService();

  final List<String> _types = const [
    'Insurance',
    'Mutual Fund',
    'Equity',
    'Fixed Deposit',
    'Gold',
    'Bonds',
    'Retirement',
    'Other',
  ];

  final List<String> _frequencies = const [
    'Monthly',
    'Quarterly',
    'Half-Yearly',
    'Yearly',
    'One-time',
  ];

  List<Investment> _investments = [];
  List<String> _childOptions = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScreenData();
  }

  Future<void> _loadScreenData() async {
    await _loadInvestments();
    if (!mounted) return;
    await _loadChildOptions();
  }

  Future<T> _callInvestments<T>(
    Future<T> Function(String supabaseUrl, String token) fn,
  ) async {
    final auth = context.read<AuthService>();
    final url = auth.supabaseUrl;

    try {
      final token = await auth.getIdToken();
      return await fn(url, token);
    } on InvestmentException catch (e) {
      if (e.type != InvestmentErrorType.authExpired) rethrow;
      final freshToken = await auth.getIdToken(true);
      return await fn(url, freshToken);
    }
  }

  Future<void> _loadInvestments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _callInvestments(
        (url, token) => _investmentService.getInvestments(
          supabaseUrl: url,
          idToken: token,
        ),
      );

      if (!mounted) return;
      setState(() {
        _investments = items;
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

  Future<void> _loadChildOptions() async {
    final auth = context.read<AuthService>();
    final familyService = FamilyService(
      supabaseUrl: auth.supabaseUrl,
      authService: auth,
    );

    List<Member> members = const [];
    try {
      members = await familyService.fetchMembers();
    } catch (_) {
      members = const [];
    }

    if (!mounted) return;

    final names = <String>{
      for (final member in members)
        if ((member.displayName ?? '').trim().isNotEmpty)
          member.displayName!.trim(),
      for (final investment in _investments)
        if ((investment.childName ?? '').trim().isNotEmpty)
          investment.childName!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      _childOptions = names;
    });
  }

  double get _totalInvested =>
      _investments.fold(0.0, (sum, inv) => sum + inv.amountInvested);

  double get _currentValue =>
      _investments.fold(0.0, (sum, inv) => sum + inv.currentValue);

  double get _totalReturns => _currentValue - _totalInvested;

  int get _dueSoonCount {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 14));
    return _investments.where((inv) {
      if (inv.dueDate == null) return false;
      final due = _atMidnight(inv.dueDate!);
      return !due.isBefore(_atMidnight(now)) &&
          !due.isAfter(_atMidnight(horizon));
    }).length;
  }

  int get _overdueCount {
    final today = _atMidnight(DateTime.now());
    return _investments.where((inv) {
      if (inv.dueDate == null) return false;
      return _atMidnight(inv.dueDate!).isBefore(today);
    }).length;
  }

  DateTime _atMidnight(DateTime date) => DateTime(date.year, date.month, date.day);

  String _formatCurrency(double value) {
    final sign = value < 0 ? '-' : '';
    final abs = value.abs().toStringAsFixed(0);
    final chars = abs.split('');
    final out = <String>[];
    for (int i = 0; i < chars.length; i++) {
      final idxFromEnd = chars.length - i;
      out.add(chars[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) out.add(',');
    }
    return '${sign}Rs ${out.join()}';
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
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _dueLabel(Investment inv) {
    if (inv.dueDate == null) return 'No due date';
    final today = _atMidnight(DateTime.now());
    final due = _atMidnight(inv.dueDate!);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Overdue by ${diff.abs()}d';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due in ${diff}d';
  }

  Color _dueColor(Investment inv) {
    if (inv.dueDate == null) return const Color(0xFF64748B);
    final today = _atMidnight(DateTime.now());
    final due = _atMidnight(inv.dueDate!);
    final diff = due.difference(today).inDays;
    if (diff < 0) return const Color(0xFFDC2626);
    if (diff <= 7) return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'insurance':
        return Icons.verified_user_outlined;
      case 'mutual fund':
        return Icons.stacked_line_chart;
      case 'equity':
        return Icons.candlestick_chart;
      case 'fixed deposit':
        return Icons.account_balance_outlined;
      case 'gold':
        return Icons.workspace_premium_outlined;
      case 'retirement':
        return Icons.elderly_outlined;
      default:
        return Icons.pie_chart_outline;
    }
  }

  Future<void> _saveInvestment({Investment? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final providerCtrl = TextEditingController(text: existing?.provider ?? '');
    final investedCtrl = TextEditingController(
      text: existing?.amountInvested.toStringAsFixed(2) ?? '',
    );
    final currentCtrl = TextEditingController(
      text: existing?.currentValue.toStringAsFixed(2) ?? '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    String type = existing?.type ?? _types.first;
    String frequency = existing?.frequency ?? _frequencies.first;
    InvestmentRiskLevel risk = existing?.riskLevel ?? InvestmentRiskLevel.medium;
    DateTime? dueDate = existing?.dueDate;
    DateTime? maturityDate = existing?.maturityDate;
    String? selectedChildName = existing?.childName?.trim().isNotEmpty == true
        ? existing!.childName!.trim()
        : null;

    final dialogChildOptions = <String>{
      ..._childOptions,
      if (selectedChildName != null) selectedChildName,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    Future<void> pickDate({required bool isDue, required StateSetter setDialog}) async {
      final initial = (isDue ? dueDate : maturityDate) ?? DateTime.now();
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: initial,
      );
      if (picked != null) {
        setDialog(() {
          if (isDue) {
            dueDate = picked;
          } else {
            maturityDate = picked;
          }
        });
      }
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Investment' : 'Edit Investment'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Investment Name'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String?>(
                          initialValue: selectedChildName,
                          decoration: InputDecoration(
                            labelText: 'Linked Child / Family Member (optional)',
                            helperText: dialogChildOptions.isEmpty
                                ? 'Add member names first to link investments cleanly.'
                                : 'Used by Kids Dashboard for exact matching.',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No linked child'),
                            ),
                            ...dialogChildOptions.map(
                              (name) => DropdownMenuItem<String?>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialog(() => selectedChildName = value);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: providerCtrl,
                          decoration: const InputDecoration(labelText: 'Provider / Institution'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: type,
                                items: _types
                                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                    .toList(),
                                decoration: const InputDecoration(labelText: 'Type'),
                                onChanged: (v) => setDialog(() => type = v ?? _types.first),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<InvestmentRiskLevel>(
                                initialValue: risk,
                                items: InvestmentRiskLevel.values
                                    .map((r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(Investment.riskLevelLabel(r)),
                                        ))
                                    .toList(),
                                decoration: const InputDecoration(labelText: 'Risk'),
                                onChanged: (v) {
                                  if (v != null) setDialog(() => risk = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: investedCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Invested Amount'),
                                validator: (v) {
                                  final d = double.tryParse((v ?? '').trim());
                                  if (d == null || d < 0) return 'Enter valid amount';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: currentCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Current Value'),
                                validator: (v) {
                                  final d = double.tryParse((v ?? '').trim());
                                  if (d == null || d < 0) return 'Enter valid amount';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: frequency,
                          decoration: const InputDecoration(labelText: 'Contribution Frequency'),
                          items: _frequencies
                              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                              .toList(),
                          onChanged: (v) => setDialog(() => frequency = v ?? _frequencies.first),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => pickDate(isDue: true, setDialog: setDialog),
                                    icon: const Icon(Icons.event_available_outlined, size: 18),
                                    label: Text(dueDate == null
                                        ? 'Set Due Date'
                                        : 'Due: ${_formatDate(dueDate!)}'),
                                  ),
                                  if (dueDate != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () => setDialog(() => dueDate = null),
                                        child: const Text('Clear due date'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => pickDate(isDue: false, setDialog: setDialog),
                                    icon: const Icon(Icons.timelapse_outlined, size: 18),
                                    label: Text(maturityDate == null
                                        ? 'Set Maturity'
                                        : 'Maturity: ${_formatDate(maturityDate!)}'),
                                  ),
                                  if (maturityDate != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () => setDialog(() => maturityDate = null),
                                        child: const Text('Clear maturity'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: notesCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Notes (optional)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(existing == null ? 'Save Investment' : 'Update Investment'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) return;

    try {
      await _callInvestments(
        (url, token) => _investmentService.upsertInvestment(
          supabaseUrl: url,
          idToken: token,
          id: existing?.id,
          name: nameCtrl.text.trim(),
          type: type,
          provider: providerCtrl.text.trim(),
          amountInvested: double.parse(investedCtrl.text.trim()),
          currentValue: double.parse(currentCtrl.text.trim()),
          dueDate: dueDate,
          maturityDate: maturityDate,
          frequency: frequency,
          riskLevel: risk,
          notes: notesCtrl.text.trim(),
          childName: selectedChildName,
        ),
      );

      if (!mounted) return;
      await _loadScreenData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Investment added successfully'
                : 'Investment updated successfully',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Failed to add investment: $e'
                : 'Failed to update investment: $e',
          ),
        ),
      );
    }
  }

  Future<void> _addInvestment() => _saveInvestment();

  Future<void> _editInvestment(Investment investment) =>
      _saveInvestment(existing: investment);

  Future<void> _deleteInvestment(Investment investment) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Investment'),
        content: Text('Delete "${investment.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await _callInvestments(
        (url, token) => _investmentService.deleteInvestment(
          supabaseUrl: url,
          idToken: token,
          investmentId: investment.id,
        ),
      );

      if (!mounted) return;
      await _loadScreenData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Investment deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete investment: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWebDesktop = kIsWeb && MediaQuery.of(context).size.width >= 980;
    final dueSorted = [..._investments]
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 34, color: Color(0xFFDC2626)),
                          const SizedBox(height: 10),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _loadInvestments,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Investments',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Track portfolio, due dates, and child-linked investments.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _addInvestment,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add Investment'),
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
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _metricCard(
                                  label: 'Total Invested',
                                  value: _formatCurrency(_totalInvested),
                                  icon: Icons.account_balance_wallet_outlined,
                                  tint: const Color(0xFF0EA5E9),
                                ),
                                _metricCard(
                                  label: 'Current Value',
                                  value: _formatCurrency(_currentValue),
                                  icon: Icons.pie_chart_outline,
                                  tint: const Color(0xFF10B981),
                                ),
                                _metricCard(
                                  label: 'Net Returns',
                                  value: _formatCurrency(_totalReturns),
                                  icon: _totalReturns >= 0
                                      ? Icons.trending_up_rounded
                                      : Icons.trending_down_rounded,
                                  tint: _totalReturns >= 0
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                ),
                                _metricCard(
                                  label: 'Upcoming Due (14d)',
                                  value: '$_dueSoonCount',
                                  icon: Icons.event_note_outlined,
                                  tint: const Color(0xFFD97706),
                                  secondary: _overdueCount > 0
                                      ? 'Overdue: $_overdueCount'
                                      : 'No overdue',
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _buildForecastedInvestmentsCard(),
                            const SizedBox(height: 18),
                            if (_investments.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Text(
                                  'No investments yet. Add your first investment to start tracking.',
                                  style: TextStyle(color: Color(0xFF64748B)),
                                ),
                              )
                            else if (isWebDesktop)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 2, child: _portfolioCard()),
                                  const SizedBox(width: 14),
                                  Expanded(child: _dueTrackerCard(dueSorted)),
                                ],
                              )
                            else ...[
                              _portfolioCard(),
                              const SizedBox(height: 14),
                              _dueTrackerCard(dueSorted),
                            ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color tint,
    String? secondary,
  }) {
    return Container(
      width: 272,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: 4),
            Text(
              secondary,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForecastedInvestmentsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFECFDF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Forecasted Investments',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatCurrency(_currentValue),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total portfolio value based on your current investments and market trends.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFF059669),
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Investment Portfolio',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Live household investments from backend',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          ..._investments.map((inv) {
            final diff = inv.netReturns;
            final positive = diff >= 0;
            final due = _dueLabel(inv);
            final dueColor = _dueColor(inv);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _iconForType(inv.type),
                          size: 18,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inv.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${inv.type} - ${inv.provider?.isNotEmpty == true ? inv.provider : 'Provider not set'}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _editInvestment(inv);
                          if (value == 'delete') _deleteInvestment(inv);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _kv('Invested', _formatCurrency(inv.amountInvested)),
                      _kv('Value', _formatCurrency(inv.currentValue)),
                      _kv(
                        'Returns',
                        '${positive ? '+' : '-'}${_formatCurrency(diff.abs())}',
                        color: positive
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                      _kv('Frequency', inv.frequency),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: dueColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          due,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: dueColor,
                          ),
                        ),
                      ),
                      _metaChip(
                        Icons.shield_outlined,
                        'Risk: ${Investment.riskLevelLabel(inv.riskLevel)}',
                      ),
                      if (inv.childName != null && inv.childName!.isNotEmpty)
                        _metaChip(Icons.child_care_outlined, 'Child: ${inv.childName}'),
                      if (inv.maturityDate != null)
                        _metaChip(
                          Icons.event_repeat_outlined,
                          'Maturity: ${_formatDate(inv.maturityDate!)}',
                        ),
                    ],
                  ),
                  if (inv.notes != null && inv.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      inv.notes!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
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

  Widget _dueTrackerCard(List<Investment> sorted) {
    final dueItems = sorted.where((e) => e.dueDate != null).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Due Date Radar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Premiums, SIPs, and renewals that need attention',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          if (dueItems.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No due dates configured yet. Add due dates while creating investments.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            )
          else
            ...dueItems.map((inv) {
              final color = _dueColor(inv);
              final due = inv.dueDate!;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withOpacity(0.08),
                  border: Border.all(color: color.withOpacity(0.32)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.alarm_rounded, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${inv.type} - ${inv.frequency}',
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDate(due),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        Text(
                          _dueLabel(inv),
                          style: TextStyle(fontSize: 10, color: color),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _kv(String key, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key,
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color ?? const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 10, color: Color(0xFF334155)),
          ),
        ],
      ),
    );
  }
}
