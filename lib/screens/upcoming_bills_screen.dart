import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bill.dart';
import '../services/auth_service.dart';
import '../services/bill_service.dart';
import '../services/family_service.dart';
import '../services/ai_service.dart';
import '../theme/app_colors.dart';
import '../utils/tag_utils.dart';
import '../widgets/tag_input_section.dart';
import '../widgets/tag_wrap.dart';

class UpcomingBillsScreen extends StatefulWidget {
  const UpcomingBillsScreen({super.key});

  @override
  State<UpcomingBillsScreen> createState() => _UpcomingBillsScreenState();
}

enum _BillFilter { all, upcoming, overdue, paid }

class _UpcomingBillsScreenState extends State<UpcomingBillsScreen> {
  final BillService _billService = BillService();

  List<Bill> _bills = [];
  List<String> _tagSuggestions = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBills();
    _loadTagSuggestions();
  }

  Future<void> _loadTagSuggestions() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final familyService = FamilyService(
        supabaseUrl: auth.supabaseUrl,
        authService: auth,
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

  _BillFilter _activeFilter = _BillFilter.all;

  Future<T> _callBills<T>(
    Future<T> Function(String supabaseUrl, String token) fn,
  ) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final url = auth.supabaseUrl;

    try {
      final token = await auth.getIdToken();
      return await fn(url, token);
    } on BillException catch (e) {
      if (e.type != BillErrorType.authExpired) rethrow;
      try {
        final freshToken = await auth.getIdToken(true);
        return await fn(url, freshToken);
      } on AppAuthException {
        throw const BillException(
          'Your session could not be renewed. Please sign out and sign back in.',
          type: BillErrorType.authInvalid,
        );
      }
    } on AppAuthException {
      throw const BillException(
        'You are not signed in. Please sign in to continue.',
        type: BillErrorType.authInvalid,
      );
    }
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bills = await _callBills(
        (url, token) => _billService.getBills(
          supabaseUrl: url,
          idToken: token,
        ),
      );

      if (!mounted) return;
      setState(() {
        _bills = bills..sort((a, b) => a.dueDate.compareTo(b.dueDate));
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

  Future<void> _showBillDialog({Bill? existing}) async {
    final result = await showDialog<_BillFormResult>(
      context: context,
      builder: (context) => _BillFormDialog(
        existing: existing,
        tagSuggestions: _tagSuggestions,
      ),
    );

    if (result == null || !mounted) return;

    try {
      await _callBills(
        (url, token) => _billService.upsertBill(
          supabaseUrl: url,
          idToken: token,
          id: existing?.id,
          name: result.name,
          provider: result.provider,
          category: result.category,
          frequency: result.frequency,
          amount: result.amount,
          dueDate: result.dueDate,
          isRecurring: result.isRecurring,
          notes: result.notes,
          tags: result.tags,
        ),
      );
      if (!mounted) return;
      await _loadBills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Bill added' : 'Bill updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save bill: $e')),
      );
    }
  }

  Future<void> _setPaid(Bill bill, bool paid) async {
    try {
      await _callBills(
        (url, token) => _billService.setPaidStatus(
          supabaseUrl: url,
          idToken: token,
          billId: bill.id,
          isPaid: paid,
        ),
      );
      if (!mounted) return;
      await _loadBills();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update bill: $e')),
      );
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Delete "${bill.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await _callBills(
        (url, token) => _billService.deleteBill(
          supabaseUrl: url,
          idToken: token,
          billId: bill.id,
        ),
      );
      if (!mounted) return;
      await _loadBills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete bill: $e')),
      );
    }
  }

  List<Bill> get _filteredBills {
    switch (_activeFilter) {
      case _BillFilter.upcoming:
        return _bills.where((b) => b.isUpcoming).toList();
      case _BillFilter.overdue:
        return _bills.where((b) => b.isOverdue).toList();
      case _BillFilter.paid:
        return _bills.where((b) => b.isPaid).toList();
      case _BillFilter.all:
        return _bills;
    }
  }

  String _formatCurrency(double amount) => 'Rs ${amount.toStringAsFixed(2)}';

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
    final upcoming = _bills.where((b) => b.isUpcoming).toList();
    final overdue = _bills.where((b) => b.isOverdue).toList();
    final paid = _bills.where((b) => b.isPaid).toList();

    final dueTotal = upcoming.fold<double>(0, (sum, b) => sum + b.amount);
    final overdueTotal = overdue.fold<double>(0, (sum, b) => sum + b.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Action Pane ──────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Upcoming Bills',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _showBillDialog(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Bill'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildBillViewTab('Current Month', Icons.calendar_month, true),
                      const SizedBox(width: 6),
                      _buildBillViewTab('Historical', Icons.history, false, comingSoon: true),
                      const SizedBox(width: 6),
                      _buildBillViewTab('Analytics', Icons.insights, false, comingSoon: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatCard(label: 'Due', value: _formatCurrency(dueTotal)),
                      _StatCard(label: 'Overdue', value: _formatCurrency(overdueTotal)),
                      _StatCard(label: 'Upcoming', value: upcoming.length.toString()),
                      _StatCard(label: 'Paid', value: paid.length.toString()),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _ErrorState(error: _error!, onRetry: _loadBills)
                        : _filteredBills.isEmpty
                            ? const _EmptyState()
                            : ListView.separated(
                                itemCount: _filteredBills.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final bill = _filteredBills[index];
                                  final statusColor = bill.isPaid
                                      ? const Color(0xFF16A34A)
                                      : bill.isOverdue
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF2563EB);

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      leading: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Bill.iconForCategory(bill.category),
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                      title: Text(
                                        bill.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                Text(
                                                  bill.provider?.trim().isNotEmpty == true
                                                      ? bill.provider!
                                                      : Bill.categoryLabel(bill.category),
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                                Text(
                                                  _formatDate(bill.dueDate),
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: Text(
                                                    bill.isPaid
                                                        ? 'Paid'
                                                        : bill.isOverdue
                                                            ? 'Overdue'
                                                            : '${bill.daysUntilDue}d left',
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (bill.tags.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              TagWrap(tags: bill.tags),
                                            ],
                                          ],
                                        ),
                                      ),
                                      trailing: SizedBox(
                                        width: 124,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatCurrency(bill.amount),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: bill.isPaid ? 'Mark unpaid' : 'Mark paid',
                                                  onPressed: () => _setPaid(bill, !bill.isPaid),
                                                  icon: Icon(
                                                    bill.isPaid
                                                        ? Icons.check_circle
                                                        : Icons.radio_button_unchecked,
                                                    color: bill.isPaid
                                                        ? const Color(0xFF16A34A)
                                                        : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  onSelected: (value) {
                                                    if (value == 'edit') {
                                                      _showBillDialog(existing: bill);
                                                    } else if (value == 'delete') {
                                                      _deleteBill(bill);
                                                    }
                                                  },
                                                  itemBuilder: (context) => const [
                                                    PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text('Edit'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete'),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillViewTab(String label, IconData icon, bool active, {bool comingSoon = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: active ? Border(bottom: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: active ? Theme.of(context).colorScheme.primary : Colors.grey[500]),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Theme.of(context).colorScheme.primary : Colors.grey[600],
            ),
          ),
          if (comingSoon) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_outline, size: 11, color: Colors.grey[400]),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 30, color: Colors.redAccent),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 34, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'No bills yet',
              style: TextStyle(
                color: Colors.grey[800],
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add your recurring and upcoming payments to stay ahead.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillFormResult {
  final String name;
  final String? provider;
  final BillCategory category;
  final BillFrequency frequency;
  final double amount;
  final DateTime dueDate;
  final bool isRecurring;
  final String? notes;
  final List<String> tags;

  const _BillFormResult({
    required this.name,
    required this.provider,
    required this.category,
    required this.frequency,
    required this.amount,
    required this.dueDate,
    required this.isRecurring,
    required this.notes,
    required this.tags,
  });
}

class _BillFormDialog extends StatefulWidget {
  final Bill? existing;
  final List<String> tagSuggestions;

  const _BillFormDialog({this.existing, this.tagSuggestions = const []});

  @override
  State<_BillFormDialog> createState() => _BillFormDialogState();
}

class _BillFormDialogState extends State<_BillFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _providerCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _tagsCtrl;

  late BillCategory _category;
  late BillFrequency _frequency;
  late DateTime _dueDate;
  late bool _isRecurring;
  bool _isCategorizing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _providerCtrl = TextEditingController(text: existing?.provider ?? '');
    _amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');
    _tagsCtrl = TextEditingController(text: joinTags(existing?.tags));

    _category = existing?.category ?? BillCategory.utilities;
    _frequency = existing?.frequency ?? BillFrequency.monthly;
    _dueDate = existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    _isRecurring = existing?.isRecurring ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _providerCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;

    Navigator.of(context).pop(
      _BillFormResult(
        name: _nameCtrl.text.trim(),
        provider: _providerCtrl.text.trim().isEmpty ? null : _providerCtrl.text.trim(),
        category: _category,
        frequency: _frequency,
        amount: amount,
        dueDate: _dueDate,
        isRecurring: _isRecurring,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        tags: parseTags(_tagsCtrl.text),
      ),
    );
  }

  Future<void> _autoCategorize() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isCategorizing = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().categorizeExpense(
        description: name,
        amount: double.tryParse(_amountCtrl.text.trim()),
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      final cat = (result['category'] as String?)?.toLowerCase() ?? '';
      // Map AI category to BillCategory
      final mapping = {
        'rent': BillCategory.rent,
        'utilities': BillCategory.utilities,
        'internet': BillCategory.internet,
        'insurance': BillCategory.insurance,
        'credit card': BillCategory.creditCard,
        'creditcard': BillCategory.creditCard,
        'subscription': BillCategory.subscription,
        'loan': BillCategory.loan,
        'school': BillCategory.school,
        'education': BillCategory.school,
      };
      setState(() {
        _category = mapping[cat] ?? BillCategory.other;
        _isCategorizing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCategorizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Bill' : 'Add Bill'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Bill Name'),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Name is required';
                    if (v.length > 100) return 'Max 100 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _providerCtrl,
                  decoration: const InputDecoration(labelText: 'Provider (optional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<BillCategory>(
                        value: _category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: BillCategory.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(Bill.categoryLabel(c)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _category = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_isCategorizing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        onPressed: _autoCategorize,
                        icon: Icon(Icons.auto_awesome, size: 18, color: Colors.deepPurple),
                        tooltip: 'AI auto-categorize',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<BillFrequency>(
                        value: _frequency,
                        decoration: const InputDecoration(labelText: 'Frequency'),
                        items: BillFrequency.values
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(Bill.frequencyLabel(f)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _frequency = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (value) {
                    final amount = double.tryParse((value ?? '').trim());
                    if (amount == null || amount <= 0) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Due date: ${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    TextButton(
                      onPressed: _pickDate,
                      child: const Text('Pick Date'),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isRecurring,
                  title: const Text('Recurring bill'),
                  onChanged: (value) => setState(() => _isRecurring = value),
                ),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                const SizedBox(height: 10),
                TagInputSection(
                  controller: _tagsCtrl,
                  suggestions: widget.tagSuggestions,
                  helperText:
                      'Use family names or keywords like dad, insurance, school, trip.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Add Bill'),
        ),
      ],
    );
  }
}
