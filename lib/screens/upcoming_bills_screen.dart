import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../services/bill_service.dart';
import '../theme/app_colors.dart';

// ── Main Screen ───────────────────────────────────────────────────────────────

class UpcomingBillsScreen extends StatefulWidget {
  const UpcomingBillsScreen({super.key});

  @override
  State<UpcomingBillsScreen> createState() => _UpcomingBillsScreenState();
}

enum _Filter { all, overdue, upcoming, paid }

class _UpcomingBillsScreenState extends State<UpcomingBillsScreen> {
  final BillService _service = BillService();
  late List<Bill> _bills;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _bills = List<Bill>.of(_service.getBills()));

  List<Bill> get _filtered {
    switch (_filter) {
      case _Filter.overdue:
        return _bills.where((b) => b.status == BillStatus.overdue).toList();
      case _Filter.upcoming:
        return _bills
            .where((b) =>
                b.status == BillStatus.upcoming ||
                b.status == BillStatus.pending)
            .toList();
      case _Filter.paid:
        return _bills.where((b) => b.isPaid).toList();
      case _Filter.all:
        return List<Bill>.of(_bills);
    }
  }

  List<Bill> get _sortedBills {
    final list = _filtered;
    list.sort((a, b) {
      if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
      return a.dueDate.compareTo(b.dueDate);
    });
    return list;
  }

  double get _totalDue => _bills
      .where((b) => !b.isPaid)
      .fold(0.0, (s, b) => s + b.amount);

  double get _overdueTotal => _service.overdueTotal;

  double get _paidThisMonth => _service.paidThisMonth;

  int get _overdueCount =>
      _bills.where((b) => b.status == BillStatus.overdue).length;

  int get _dueThisWeek => _bills
      .where((b) =>
          !b.isPaid &&
          b.daysUntilDue >= 0 &&
          b.daysUntilDue <= 7)
      .length;

  void _togglePaid(Bill bill) {
    if (bill.isPaid) {
      _service.markUnpaid(bill.id);
    } else {
      _service.markPaid(bill.id);
    }
    _refresh();
  }

  void _deleteBill(Bill bill) {
    _service.deleteBill(bill.id);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${bill.name} removed'),
        action: SnackBarAction(label: 'Undo', onPressed: () {
          _service.addBill(bill);
          _refresh();
        }),
      ),
    );
  }

  String _formatCurrency(double value) {
    final abs = value.abs().toStringAsFixed(0);
    final chars = abs.split('');
    final out = <String>[];
    for (int i = 0; i < chars.length; i++) {
      final idxFromEnd = chars.length - i;
      out.add(chars[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) out.add(',');
    }
    return 'Rs ${out.join()}';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _dueLabel(Bill bill) {
    if (bill.isPaid) return 'Paid';
    final days = bill.daysUntilDue;
    if (days < 0) return 'Overdue ${days.abs()}d';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'Due in ${days}d';
  }

  Color _dueLabelColor(Bill bill) {
    if (bill.isPaid) return const Color(0xFF16A34A);
    final days = bill.daysUntilDue;
    if (days < 0) return const Color(0xFFDC2626);
    if (days <= 3) return const Color(0xFFD97706);
    if (days <= 7) return const Color(0xFF2563EB);
    return const Color(0xFF64748B);
  }

  Future<void> _showAddBillDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    BillCategory category = BillCategory.other;
    BillFrequency frequency = BillFrequency.monthly;
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    bool isRecurring = true;

    final created = await showDialog<Bill>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Bill'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Bill Name'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: providerCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Provider / Biller'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<BillCategory>(
                            value: category,
                            decoration:
                                const InputDecoration(labelText: 'Category'),
                            items: BillCategory.values
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(Bill.categoryLabel(c)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setDlg(() => category = v ?? category),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<BillFrequency>(
                            value: frequency,
                            decoration:
                                const InputDecoration(labelText: 'Frequency'),
                            items: BillFrequency.values
                                .map((f) => DropdownMenuItem(
                                      value: f,
                                      child:
                                          Text(Bill.frequencyLabel(f)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setDlg(() => frequency = v ?? frequency),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Amount (Rs)', prefixText: 'Rs '),
                      validator: (v) {
                        final d = double.tryParse((v ?? '').trim());
                        if (d == null || d <= 0) return 'Enter valid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Due Date'),
                      subtitle: Text(_formatDate(dueDate)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 30)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                          initialDate: dueDate,
                        );
                        if (picked != null) setDlg(() => dueDate = picked);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recurring'),
                      value: isRecurring,
                      onChanged: (v) => setDlg(() => isRecurring = v),
                    ),
                    TextFormField(
                      controller: notesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Notes (optional)'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(ctx).pop(
                  Bill(
                    id:
                        'bill-${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    category: category,
                    provider: providerCtrl.text.trim(),
                    amount: double.parse(amountCtrl.text.trim()),
                    dueDate: dueDate,
                    isRecurring: isRecurring,
                    frequency: frequency,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Save Bill'),
            ),
          ],
        ),
      ),
    );

    if (created != null) {
      _service.addBill(created);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${created.name} added')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme, isDark),
                  const SizedBox(height: 24),
                  _buildSummaryRow(isDark),
                  const SizedBox(height: 24),
                  _buildFilterRow(theme, isDark),
                  const SizedBox(height: 16),
                  _buildBillsList(isDark, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upcoming Bills',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Track recurring payments, due dates, and stay ahead of your obligations.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _showAddBillDialog,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Bill'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(bool isDark) {
    final cards = [
      _SumCard(
        label: 'Total Due',
        value: _formatCurrency(_totalDue),
        icon: Icons.account_balance_wallet_outlined,
        iconBg: const Color(0xFFDBEAFE),
        iconColor: const Color(0xFF2563EB),
        isDark: isDark,
      ),
      _SumCard(
        label: '${_overdueCount} Overdue',
        value: _formatCurrency(_overdueTotal),
        icon: Icons.warning_amber_rounded,
        iconBg: const Color(0xFFFEE2E2),
        iconColor: const Color(0xFFDC2626),
        isDark: isDark,
        alert: _overdueCount > 0,
      ),
      _SumCard(
        label: 'Due This Week',
        value: '$_dueThisWeek bills',
        icon: Icons.event_outlined,
        iconBg: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFD97706),
        isDark: isDark,
      ),
      _SumCard(
        label: 'Paid This Month',
        value: _formatCurrency(_paidThisMonth),
        icon: Icons.check_circle_outline_rounded,
        iconBg: const Color(0xFFDCFCE7),
        iconColor: const Color(0xFF16A34A),
        isDark: isDark,
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards
          .map((c) => SizedBox(
                width: 230,
                child: c,
              ))
          .toList(),
    );
  }

  Widget _buildFilterRow(ThemeData theme, bool isDark) {
    final filters = [
      (_Filter.all, 'All Bills'),
      (_Filter.overdue, 'Overdue'),
      (_Filter.upcoming, 'Due Soon'),
      (_Filter.paid, 'Paid'),
    ];

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final isActive = _filter == f.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: FilterChip(
                      label: Text(f.$2),
                      selected: isActive,
                      onSelected: (_) =>
                          setState(() => _filter = f.$1),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? AppColors.primary
                            : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: isActive
                            ? AppColors.primary
                            : const Color(0xFFE2E8F0),
                      ),
                      backgroundColor:
                          isDark ? AppColors.surfaceDark : Colors.white,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_sortedBills.length} items',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildBillsList(bool isDark, ThemeData theme) {
    final bills = _sortedBills;
    if (bills.isEmpty) {
      return _buildEmpty(isDark);
    }

    // Group bills: overdue → due this week → this month → later → paid
    final overdue =
        bills.where((b) => b.status == BillStatus.overdue).toList();
    final dueSoon =
        bills.where((b) => b.status == BillStatus.upcoming).toList();
    final pending = bills
        .where((b) => b.status == BillStatus.pending)
        .toList();
    final paid =
        bills.where((b) => b.status == BillStatus.paid).toList();

    final sections = <Widget>[];

    if (overdue.isNotEmpty) {
      sections.add(
          _buildGroup('Overdue', overdue, isDark, theme, const Color(0xFFDC2626)));
    }
    if (dueSoon.isNotEmpty) {
      sections.add(
          _buildGroup('Due This Week', dueSoon, isDark, theme, const Color(0xFFD97706)));
    }
    if (pending.isNotEmpty) {
      sections.add(
          _buildGroup('Upcoming', pending, isDark, theme, const Color(0xFF2563EB)));
    }
    if (paid.isNotEmpty) {
      sections.add(
          _buildGroup('Paid', paid, isDark, theme, const Color(0xFF16A34A)));
    }

    return Column(children: sections);
  }

  Widget _buildGroup(String label, List<Bill> bills, bool isDark,
      ThemeData theme, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${bills.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...bills.map((b) => _BillCard(
              bill: b,
              isDark: isDark,
              dueLabel: _dueLabel(b),
              dueLabelColor: _dueLabelColor(b),
              formatCurrency: _formatCurrency,
              formatDate: _formatDate,
              onTogglePaid: () => _togglePaid(b),
              onDelete: () => _deleteBill(b),
            )),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 52),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.grey800
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 52, color: Colors.grey[400]),
          const SizedBox(height: 14),
          const Text(
            'No bills match this filter',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Add Bill" to track a new payment',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ── Summary Card ──────────────────────────────────────────────────────────────

class _SumCard extends StatelessWidget {
  const _SumCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.isDark,
    this.alert = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final bool isDark;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alert
              ? const Color(0xFFFECACA)
              : isDark
                  ? AppColors.grey800
                  : const Color(0xFFE2E8F0),
          width: alert ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bill Card ─────────────────────────────────────────────────────────────────

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.isDark,
    required this.dueLabel,
    required this.dueLabelColor,
    required this.formatCurrency,
    required this.formatDate,
    required this.onTogglePaid,
    required this.onDelete,
  });

  final Bill bill;
  final bool isDark;
  final String dueLabel;
  final Color dueLabelColor;
  final String Function(double) formatCurrency;
  final String Function(DateTime) formatDate;
  final VoidCallback onTogglePaid;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final iconBg = Bill.categoryBgColor(bill.category);
    final iconColor = Bill.categoryIconColor(bill.category);
    final icon = Bill.categoryIcon(bill.category);

    return Dismissible(
      key: ValueKey(bill.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFDC2626)),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark
              : bill.isPaid
                  ? const Color(0xFFF8FAFC)
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: bill.status == BillStatus.overdue
                ? const Color(0xFFFECACA)
                : isDark
                    ? AppColors.grey800
                    : const Color(0xFFE2E8F0),
          ),
          boxShadow: bill.isPaid
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bill.isPaid ? const Color(0xFFF1F5F9) : iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: bill.isPaid
                    ? const Color(0xFF94A3B8)
                    : iconColor,
              ),
            ),
            const SizedBox(width: 14),

            // Name + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bill.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: bill.isPaid
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF0F172A),
                            decoration: bill.isPaid
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Amount
                      Text(
                        formatCurrency(bill.amount),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: bill.isPaid
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (bill.provider.isNotEmpty) ...[
                        Text(
                          bill.provider,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const Text(
                          ' · ',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                      Text(
                        Bill.categoryLabel(bill.category),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const Spacer(),
                      // Due badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: dueLabelColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dueLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: dueLabelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 11, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        formatDate(bill.dueDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (bill.isRecurring) ...[
                        Icon(Icons.repeat_rounded,
                            size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          Bill.frequencyLabel(bill.frequency),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Mark paid toggle
            GestureDetector(
              onTap: onTogglePaid,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bill.isPaid
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: bill.isPaid
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: Icon(
                  bill.isPaid ? Icons.check_rounded : Icons.check_rounded,
                  size: 16,
                  color: bill.isPaid
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
