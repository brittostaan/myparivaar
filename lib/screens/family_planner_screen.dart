import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/planner_item.dart';
import '../services/auth_service.dart';
import '../services/family_planner_service.dart';
import '../theme/app_colors.dart';

class FamilyPlannerScreen extends StatefulWidget {
  const FamilyPlannerScreen({super.key});

  @override
  State<FamilyPlannerScreen> createState() => _FamilyPlannerScreenState();
}

enum _PlannerFilter {
  all,
  today,
  upcoming,
  thisMonth,
  completed,
}

class _FamilyPlannerScreenState extends State<FamilyPlannerScreen> {
  final FamilyPlannerService _service = FamilyPlannerService();

  List<PlannerItem> _items = [];
  bool _isLoading = false;
  String? _error;

  _PlannerFilter _activeFilter = _PlannerFilter.all;
  PlannerItemType? _activeType;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<T> _callPlanner<T>(
    Future<T> Function(String supabaseUrl, String token) fn,
  ) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final url = auth.supabaseUrl;

    try {
      final token = await auth.getIdToken();
      return await fn(url, token);
    } on FamilyPlannerException catch (e) {
      if (e.type != FamilyPlannerErrorType.authExpired) rethrow;
      try {
        final freshToken = await auth.getIdToken(true);
        return await fn(url, freshToken);
      } on AppAuthException {
        throw const FamilyPlannerException(
          'Your session could not be renewed. Please sign out and sign back in.',
          type: FamilyPlannerErrorType.authInvalid,
        );
      }
    } on AppAuthException {
      throw const FamilyPlannerException(
        'You are not signed in. Please sign in to continue.',
        type: FamilyPlannerErrorType.authInvalid,
      );
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _callPlanner(
        (url, token) => _service.getItems(supabaseUrl: url, idToken: token),
      );

      if (!mounted) return;
      setState(() {
        _items = items..sort((a, b) => a.startDate.compareTo(b.startDate));
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

  Future<void> _openItemDialog({PlannerItem? existing}) async {
    final result = await showDialog<_PlannerFormResult>(
      context: context,
      builder: (_) => _PlannerItemDialog(existing: existing),
    );

    if (result == null || !mounted) return;

    try {
      await _callPlanner(
        (url, token) => _service.upsertItem(
          supabaseUrl: url,
          idToken: token,
          id: existing?.id,
          type: result.type,
          title: result.title,
          description: result.description,
          startDate: result.startDate,
          endDate: result.endDate,
          isAllDay: result.isAllDay,
          isRecurringYearly: result.isRecurringYearly,
          priority: result.priority,
          location: result.location,
        ),
      );

      if (!mounted) return;
      await _loadItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? 'Planner item created'
              : 'Planner item updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save planner item: $e')),
      );
    }
  }

  Future<void> _toggleCompleted(PlannerItem item, bool isCompleted) async {
    try {
      await _callPlanner(
        (url, token) => _service.setCompleted(
          supabaseUrl: url,
          idToken: token,
          itemId: item.id,
          isCompleted: isCompleted,
        ),
      );
      if (!mounted) return;
      await _loadItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _deleteItem(PlannerItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Planner Item'),
        content: Text('Delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.scorePoor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await _callPlanner(
        (url, token) => _service.deleteItem(
          supabaseUrl: url,
          idToken: token,
          itemId: item.id,
        ),
      );
      if (!mounted) return;
      await _loadItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Planner item deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete planner item: $e')),
      );
    }
  }

  List<PlannerItem> get _filteredItems {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    return _items.where((item) {
      if (_activeType != null && item.type != _activeType) {
        return false;
      }

      switch (_activeFilter) {
        case _PlannerFilter.today:
          return item.isToday;
        case _PlannerFilter.upcoming:
          return item.isUpcoming;
        case _PlannerFilter.thisMonth:
          final itemDate = DateTime(
            item.startDate.year,
            item.startDate.month,
            item.startDate.day,
          );
          return !itemDate.isBefore(startOfMonth) &&
              !itemDate.isAfter(endOfMonth);
        case _PlannerFilter.completed:
          return item.isCompleted;
        case _PlannerFilter.all:
          return true;
      }
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
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

  String _sectionTitleForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return _formatDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final upcomingCount = _items.where((i) => i.isUpcoming).length;
    final todayCount = _items.where((i) => i.isToday).length;
    final birthdays = _items.where((i) => i.type == PlannerItemType.birthday).length;
    final vacations = _items.where((i) => i.type == PlannerItemType.vacation).length;

    return Scaffold(
      backgroundColor: AppColors.surfaceHoverLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.borderLight),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    _buildOverviewCard(
                      upcomingCount: upcomingCount,
                      todayCount: todayCount,
                      birthdays: birthdays,
                      vacations: vacations,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? _ErrorState(error: _error!, onRetry: _loadItems)
                              : _buildTimeline(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Family Planner',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openItemDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Plan'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._PlannerFilter.values.map((f) {
                  final label = switch (f) {
                    _PlannerFilter.all => 'All',
                    _PlannerFilter.today => 'Today',
                    _PlannerFilter.upcoming => 'Upcoming',
                    _PlannerFilter.thisMonth => 'This Month',
                    _PlannerFilter.completed => 'Completed',
                  };
                  final icon = switch (f) {
                    _PlannerFilter.all => Icons.grid_view_rounded,
                    _PlannerFilter.today => Icons.today,
                    _PlannerFilter.upcoming => Icons.upcoming,
                    _PlannerFilter.thisMonth => Icons.calendar_month,
                    _PlannerFilter.completed => Icons.check_circle_outline,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildPlannerTab(label, icon, _activeFilter == f, onTap: () => setState(() => _activeFilter = f)),
                  );
                }),
                const SizedBox(width: 8),
                ...PlannerItemType.values.map((t) {
                  final label = t.name[0].toUpperCase() + t.name.substring(1);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildPlannerTab(
                      label,
                      Icons.label_outline,
                      _activeType == t,
                      onTap: () => setState(() => _activeType = (_activeType == t) ? null : t),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPlannerTab(String label, IconData icon, bool active, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.activeBlue.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border(bottom: BorderSide(color: AppColors.activeBlue, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? AppColors.activeBlue : Colors.grey[500]),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.activeBlue : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard({
    required int upcomingCount,
    required int todayCount,
    required int birthdays,
    required int vacations,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Family Pulse',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat('Upcoming', '$upcomingCount'),
              const SizedBox(width: 10),
              _miniStat('Today', '$todayCount'),
              const SizedBox(width: 10),
              _miniStat('Birthdays', '$birthdays'),
              const SizedBox(width: 10),
              _miniStat('Vacations', '$vacations'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHoverLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.slate500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(_PlannerFilter.all, 'All'),
              _filterChip(_PlannerFilter.today, 'Today'),
              _filterChip(_PlannerFilter.upcoming, 'Upcoming'),
              _filterChip(_PlannerFilter.thisMonth, 'This Month'),
              _filterChip(_PlannerFilter.completed, 'Completed'),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Types'),
                  selected: _activeType == null,
                  onSelected: (_) => setState(() => _activeType = null),
                ),
                const SizedBox(width: 8),
                ...PlannerItemType.values.map((type) {
                  final selected = _activeType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(PlannerItem.iconForType(type), size: 16),
                      label: Text(PlannerItem.typeLabel(type)),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _activeType = selected ? null : type),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_PlannerFilter filter, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _activeFilter == filter,
      onSelected: (_) => setState(() => _activeFilter = filter),
    );
  }

  Widget _buildTimeline() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return const _EmptyState();
    }

    final grouped = <String, List<PlannerItem>>{};
    for (final item in items) {
      final dateKey =
          '${item.startDate.year}-${item.startDate.month.toString().padLeft(2, '0')}-${item.startDate.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(item);
    }

    final sortedDateKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: sortedDateKeys.length,
      itemBuilder: (context, index) {
        final key = sortedDateKeys[index];
        final dayItems = grouped[key]!..sort((a, b) => a.startDate.compareTo(b.startDate));
        final dayDate = dayItems.first.startDate;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _sectionTitleForDate(dayDate),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              ...dayItems.map(_buildPlannerItem),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlannerItem(PlannerItem item) {
    final typeColor = PlannerItem.colorForType(item.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            PlannerItem.iconForType(item.type),
            color: typeColor,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration:
                      item.isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (item.isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${PlannerItem.typeLabel(item.type)} · ${PlannerItem.priorityLabel(item.priority)}',
                style: const TextStyle(fontSize: 12),
              ),
              if (item.location != null && item.location!.trim().isNotEmpty)
                Text(
                  'Location: ${item.location}',
                  style: const TextStyle(fontSize: 12),
                ),
              if (item.description != null && item.description!.trim().isNotEmpty)
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _openItemDialog(existing: item);
            } else if (value == 'delete') {
              _deleteItem(item);
            } else if (value == 'toggle') {
              _toggleCompleted(item, !item.isCompleted);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(item.isCompleted ? 'Mark Incomplete' : 'Mark Complete'),
            ),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _PlannerFormResult {
  final PlannerItemType type;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isAllDay;
  final bool isRecurringYearly;
  final PlannerPriority priority;
  final String? location;

  const _PlannerFormResult({
    required this.type,
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.isAllDay,
    required this.isRecurringYearly,
    required this.priority,
    required this.location,
  });
}

class _PlannerItemDialog extends StatefulWidget {
  final PlannerItem? existing;

  const _PlannerItemDialog({this.existing});

  @override
  State<_PlannerItemDialog> createState() => _PlannerItemDialogState();
}

class _PlannerItemDialogState extends State<_PlannerItemDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _locationCtrl;

  late PlannerItemType _type;
  late PlannerPriority _priority;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _isAllDay = true;
  bool _isRecurringYearly = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _descriptionCtrl = TextEditingController(text: existing?.description ?? '');
    _locationCtrl = TextEditingController(text: existing?.location ?? '');

    _type = existing?.type ?? PlannerItemType.event;
    _priority = existing?.priority ?? PlannerPriority.medium;
    _startDate = existing?.startDate ?? DateTime.now();
    _endDate = existing?.endDate;
    _isAllDay = existing?.isAllDay ?? true;
    _isRecurringYearly = existing?.isRecurringYearly ??
        (_type == PlannerItemType.birthday ||
            _type == PlannerItemType.anniversary);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
    }
  }

  String _fmtDate(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }

    Navigator.of(context).pop(
      _PlannerFormResult(
        type: _type,
        title: title,
        description: description.isEmpty ? null : description,
        startDate: _startDate,
        endDate: _endDate,
        isAllDay: _isAllDay,
        isRecurringYearly: _isRecurringYearly,
        priority: _priority,
        location: location.isEmpty ? null : location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecurringType =
        _type == PlannerItemType.birthday || _type == PlannerItemType.anniversary;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Planner Item' : 'Edit Planner Item'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PlannerItemType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: PlannerItemType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(PlannerItem.typeLabel(type)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _type = value;
                    if (_type == PlannerItemType.birthday ||
                        _type == PlannerItemType.anniversary) {
                      _isRecurringYearly = true;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationCtrl,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PlannerPriority>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: PlannerPriority.values.map((priority) {
                  return DropdownMenuItem(
                    value: priority,
                    child: Text(PlannerItem.priorityLabel(priority)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStartDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text('Start: ${_fmtDate(_startDate)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickEndDate,
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(
                        _endDate == null
                            ? 'Add end date'
                            : 'End: ${_fmtDate(_endDate!)}',
                      ),
                    ),
                  ),
                  if (_endDate != null)
                    IconButton(
                      tooltip: 'Clear end date',
                      onPressed: () => setState(() => _endDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isAllDay,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('All-day'),
                onChanged: (v) => setState(() => _isAllDay = v),
              ),
              SwitchListTile(
                value: _isRecurringYearly,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(isRecurringType
                    ? 'Repeat yearly (recommended for this type)'
                    : 'Repeat yearly'),
                onChanged: (v) => setState(() => _isRecurringYearly = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.scorePoor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
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
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 36, color: Color(0xFF94A3B8)),
            SizedBox(height: 10),
            Text(
              'No plans yet for this filter',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Add birthdays, vacations, and events so everyone in the family can stay aligned.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.slate500, fontSize: 12),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 32, color: AppColors.scorePoor),
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
