import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/app_header.dart';

// ── Feature tags ─────────────────────────────────────────────────────────────

const _featureTags = [
  'general',
  'dashboard',
  'expenses',
  'budget',
  'investments',
  'bills',
  'reports',
  'ai',
  'email',
  'family',
  'admin',
  'savings',
  'planner',
  'ux',
  'infra',
];

const _statusMeta = <String, _StatusMeta>{
  'open': _StatusMeta('Open', Color(0xFF6366F1), Icons.radio_button_unchecked),
  'in_progress': _StatusMeta('In Progress', Color(0xFFF59E0B), Icons.pending_outlined),
  'done': _StatusMeta('Done', Color(0xFF10B981), Icons.check_circle_outline),
  'rejected': _StatusMeta('Rejected', Color(0xFFEF4444), Icons.cancel_outlined),
  'parked': _StatusMeta('Parked', Color(0xFF6B7280), Icons.pause_circle_outline),
};

const _priorityMeta = <String, _PriorityMeta>{
  'low': _PriorityMeta('Low', Color(0xFF94A3B8), Icons.arrow_downward),
  'medium': _PriorityMeta('Medium', Color(0xFF3B82F6), Icons.remove),
  'high': _PriorityMeta('High', Color(0xFFF97316), Icons.arrow_upward),
  'critical': _PriorityMeta('Critical', AppColors.scorePoor, Icons.priority_high),
};

class _StatusMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusMeta(this.label, this.color, this.icon);
}

class _PriorityMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _PriorityMeta(this.label, this.color, this.icon);
}

// ── Screen ───────────────────────────────────────────────────────────────────

class IdeaBoardScreen extends StatefulWidget {
  final String supabaseUrl;
  const IdeaBoardScreen({super.key, required this.supabaseUrl});

  @override
  State<IdeaBoardScreen> createState() => _IdeaBoardScreenState();
}

class _IdeaBoardScreenState extends State<IdeaBoardScreen> {
  List<Map<String, dynamic>> _ideas = [];
  bool _loading = true;
  String? _error;

  // Filters
  String _statusFilter = 'all';
  String _tagFilter = 'all';
  String _viewMode = 'board'; // 'board' or 'list'

  /// All known tags: predefined + any custom ones from existing ideas.
  List<String> get _allTags {
    final custom = _ideas
        .map((i) => (i['feature_tag'] as String?) ?? 'general')
        .where((t) => !_featureTags.contains(t))
        .toSet();
    return [..._featureTags, ...custom];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── API helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = await auth.getIdToken(true);
    final resp = await http.post(
      Uri.parse('${widget.supabaseUrl}/functions/v1/idea-board'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Request failed (${resp.statusCode})');
    }
    return data;
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _call({'action': 'list'});
      setState(() {
        _ideas = List<Map<String, dynamic>>.from(data['ideas'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _createIdea(Map<String, dynamic> idea) async {
    try {
      final data = await _call({'action': 'create', ...idea});
      setState(() => _ideas.insert(0, Map<String, dynamic>.from(data['idea'])));
    } catch (e) {
      _showSnack('Failed to create: $e');
    }
  }

  Future<void> _updateIdea(String id, Map<String, dynamic> updates) async {
    try {
      final data = await _call({'action': 'update', 'id': id, ...updates});
      setState(() {
        final idx = _ideas.indexWhere((i) => i['id'] == id);
        if (idx >= 0) {
          final old = _ideas[idx];
          _ideas[idx] = {...Map<String, dynamic>.from(data['idea']), 'comments': old['comments'] ?? []};
        }
      });
    } catch (e) {
      _showSnack('Failed to update: $e');
    }
  }

  Future<void> _deleteIdea(String id) async {
    try {
      await _call({'action': 'delete', 'id': id});
      setState(() => _ideas.removeWhere((i) => i['id'] == id));
    } catch (e) {
      _showSnack('Failed to delete: $e');
    }
  }

  Future<void> _addComment(String ideaId, String text) async {
    try {
      final data = await _call({'action': 'add_comment', 'idea_id': ideaId, 'comment': text});
      setState(() {
        final idx = _ideas.indexWhere((i) => i['id'] == ideaId);
        if (idx >= 0) {
          final comments = List<Map<String, dynamic>>.from(_ideas[idx]['comments'] ?? []);
          comments.add(Map<String, dynamic>.from(data['comment']));
          _ideas[idx] = {..._ideas[idx], 'comments': comments};
        }
      });
    } catch (e) {
      _showSnack('Failed to add comment: $e');
    }
  }

  Future<void> _deleteComment(String ideaId, String commentId) async {
    try {
      await _call({'action': 'delete_comment', 'comment_id': commentId});
      setState(() {
        final idx = _ideas.indexWhere((i) => i['id'] == ideaId);
        if (idx >= 0) {
          final comments = List<Map<String, dynamic>>.from(_ideas[idx]['comments'] ?? []);
          comments.removeWhere((c) => c['id'] == commentId);
          _ideas[idx] = {..._ideas[idx], 'comments': comments};
        }
      });
    } catch (e) {
      _showSnack('Failed to delete comment: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Filtered ideas ──────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    return _ideas.where((i) {
      if (_statusFilter != 'all' && i['status'] != _statusFilter) return false;
      if (_tagFilter != 'all' && i['feature_tag'] != _tagFilter) return false;
      return true;
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _groupedByStatus {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final status in ['open', 'in_progress', 'done', 'parked', 'rejected']) {
      map[status] = _filtered.where((i) => i['status'] == status).toList();
    }
    return map;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final isPlatformAdmin = user?.isPlatformAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.surfaceHoverLight,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Feature Board',
              avatarIcon: Icons.lightbulb_outline,
              showViewModeSelector: false,
              showSettingsButton: false,
              showNotifications: false,
            ),
            Expanded(
              child: Row(
                children: [
                  if (isPlatformAdmin) _buildSidebar(context),
                  Expanded(
                    child: Column(
                      children: [
                        _buildToolbar(),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                                  ? _buildError()
                                  : _viewMode == 'board'
                                      ? _buildBoard()
                                      : _buildListView(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(AppIcons.add),
        label: const Text('New Feature'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 256,
      color: AppColors.surfaceHoverLight,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sidebarNavItem(context, 'Dashboard', Icons.dashboard_rounded, '/admin-center'),
              _sidebarNavItem(context, 'Households', Icons.home_work_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Users', Icons.people_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Subscriptions', Icons.card_membership_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Plans', Icons.layers_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Features', Icons.toggle_on_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Analytics', Icons.analytics_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Audit Logs', Icons.history_outlined, '/admin-center'),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _sidebarNavItem(context, 'Staff', Icons.admin_panel_settings_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Approvals', Icons.approval_outlined, '/admin-center'),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _sidebarNavItem(context, 'AI', Icons.psychology_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Email Admin', Icons.email_outlined, '/admin-center'),
              _sidebarNavItem(context, 'Payment Gateways', Icons.payment_outlined, '/admin-center'),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _buildSelectedNavItem('Feature Board', Icons.lightbulb_outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarNavItem(BuildContext context, String label, IconData icon, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushReplacementNamed(context, route),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.grey600),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(fontSize: 14, color: AppColors.grey600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedNavItem(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Toolbar ─────────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Stats
          _statChip('Total', _ideas.length, AppColors.primary),
          const SizedBox(width: 8),
          _statChip('Open', _ideas.where((i) => i['status'] == 'open').length, const Color(0xFF6366F1)),
          const SizedBox(width: 8),
          _statChip('In Progress', _ideas.where((i) => i['status'] == 'in_progress').length, const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          _statChip('Done', _ideas.where((i) => i['status'] == 'done').length, const Color(0xFF10B981)),
          const Spacer(),
          // Tag filter
          _buildDropdown(
            value: _tagFilter,
            items: ['all', ..._allTags],
            labelBuilder: (v) => v == 'all' ? 'All Tags' : '#$v',
            onChanged: (v) => setState(() => _tagFilter = v),
          ),
          const SizedBox(width: 8),
          // Status filter
          _buildDropdown(
            value: _statusFilter,
            items: ['all', ..._statusMeta.keys],
            labelBuilder: (v) => v == 'all' ? 'All Status' : _statusMeta[v]!.label,
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
          const SizedBox(width: 8),
          // View toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'board', icon: Icon(Icons.view_column_outlined, size: 18)),
              ButtonSegment(value: 'list', icon: Icon(Icons.view_list_outlined, size: 18)),
            ],
            selected: {_viewMode},
            onSelectionChanged: (v) => setState(() => _viewMode = v.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(AppIcons.refresh, size: 20),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required String Function(String) labelBuilder,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          items: items.map((v) => DropdownMenuItem(value: v, child: Text(labelBuilder(v)))).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }

  // ── Error ───────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.error, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Unknown error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(AppIcons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Board View (Kanban) ─────────────────────────────────────────────────

  Widget _buildBoard() {
    final grouped = _groupedByStatus;
    final columns = ['open', 'in_progress', 'done', 'parked', 'rejected'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns.map((status) {
          final meta = _statusMeta[status]!;
          final items = grouped[status] ?? [];
          return Container(
            width: 320,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Column header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: meta.color.withOpacity(0.08),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(bottom: BorderSide(color: meta.color.withOpacity(0.3), width: 2)),
                  ),
                  child: Row(
                    children: [
                      Icon(meta.icon, color: meta.color, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        meta.label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: meta.color, fontSize: 14),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: meta.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${items.length}',
                          style: TextStyle(color: meta.color, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                // Cards
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHoverLight,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No ideas',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: items.length,
                            itemBuilder: (_, i) => _buildCard(items[i]),
                          ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── List View ───────────────────────────────────────────────────────────

  Widget _buildListView() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No ideas yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Tap "New Idea" to add your first one', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildCard(items[i]),
    );
  }

  // ── Idea Card ───────────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> idea) {
    final status = _statusMeta[idea['status']] ?? _statusMeta['open']!;
    final priority = _priorityMeta[idea['priority']] ?? _priorityMeta['medium']!;
    final tag = idea['feature_tag'] as String? ?? 'general';
    final comments = List<Map<String, dynamic>>.from(idea['comments'] ?? []);
    final isPinned = idea['is_pinned'] == true;
    final desc = idea['description'] as String?;
    final createdAt = DateTime.tryParse(idea['created_at'] ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isPinned ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPinned
            ? const BorderSide(color: Color(0xFFFBBF24), width: 1.5)
            : BorderSide.none,
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailDialog(idea),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: priority + pin + actions
              Row(
                children: [
                  // Priority badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: priority.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(priority.icon, color: priority.color, size: 12),
                        const SizedBox(width: 3),
                        Text(priority.label, style: TextStyle(color: priority.color, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (isPinned) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.push_pin, size: 14, color: Color(0xFFFBBF24)),
                  ],
                  const Spacer(),
                  // Quick status change
                  PopupMenuButton<String>(
                    icon: Icon(status.icon, color: status.color, size: 18),
                    tooltip: 'Change status',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    itemBuilder: (_) => _statusMeta.entries.map((e) {
                      return PopupMenuItem(
                        value: e.key,
                        child: Row(
                          children: [
                            Icon(e.value.icon, color: e.value.color, size: 16),
                            const SizedBox(width: 8),
                            Text(e.value.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onSelected: (s) => _updateIdea(idea['id'], {'status': s}),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                idea['title'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  decoration: idea['status'] == 'done' ? TextDecoration.lineThrough : null,
                  color: idea['status'] == 'done' ? Colors.grey : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              // Footer: date + comments count
              Row(
                children: [
                  if (createdAt != null)
                    Text(
                      '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  const Spacer(),
                  if (comments.isNotEmpty) ...[
                    Icon(AppIcons.chat, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(
                      '${comments.length}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tag Field (Dropdown + custom option) ─────────────────────────────

  Widget _buildTagField(String currentTag, ValueChanged<String> onChanged) {
    final isCustom = !_featureTags.contains(currentTag) && currentTag != '_custom_';
    // If the current tag is a known one, use it in dropdown; otherwise show custom input
    final dropdownValue = isCustom ? '_custom_' : currentTag;

    return _TagFieldWidget(
      allTags: _allTags,
      initialTag: currentTag,
      initialDropdownValue: dropdownValue,
      isInitiallyCustom: isCustom,
      onChanged: onChanged,
    );
  }

  // ── Create Dialog ───────────────────────────────────────────────────────

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String tag = 'general';
    String priority = 'medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lightbulb, color: Color(0xFFFBBF24), size: 24),
              SizedBox(width: 8),
              Text('New Idea'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'What\'s the idea?',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    maxLength: 300,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Add details, context, or user stories…',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  _buildTagField(tag, (v) => setDlg(() => tag = v)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _priorityMeta.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Row(
                          children: [
                            Icon(e.value.icon, color: e.value.color, size: 16),
                            const SizedBox(width: 6),
                            Text(e.value.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setDlg(() => priority = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                _createIdea({
                  'title': title,
                  'description': descCtrl.text.trim(),
                  'feature_tag': tag,
                  'priority': priority,
                });
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Detail / Edit Dialog ────────────────────────────────────────────────

  void _showDetailDialog(Map<String, dynamic> idea) {
    final comments = List<Map<String, dynamic>>.from(idea['comments'] ?? []);
    final commentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // Re-read idea from state in case it was updated
          final current = _ideas.firstWhere(
            (i) => i['id'] == idea['id'],
            orElse: () => idea,
          );
          final curComments = List<Map<String, dynamic>>.from(current['comments'] ?? comments);
          final status = _statusMeta[current['status']] ?? _statusMeta['open']!;
          final priority = _priorityMeta[current['priority']] ?? _priorityMeta['medium']!;
          final tag = current['feature_tag'] as String? ?? 'general';

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, color: status.color, size: 16),
                      const SizedBox(width: 4),
                      Text(status.label, style: TextStyle(color: status.color, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: priority.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(priority.icon, color: priority.color, size: 14),
                      const SizedBox(width: 4),
                      Text(priority.label, style: TextStyle(color: priority.color, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('#$tag', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                // Actions
                IconButton(
                  icon: Icon(
                    current['is_pinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
                    color: current['is_pinned'] == true ? const Color(0xFFFBBF24) : Colors.grey,
                    size: 20,
                  ),
                  onPressed: () {
                    _updateIdea(current['id'], {'is_pinned': !(current['is_pinned'] == true)});
                    setDlg(() {});
                  },
                  tooltip: 'Pin / Unpin',
                ),
                IconButton(
                  icon: const Icon(AppIcons.edit, size: 20),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showEditDialog(current);
                  },
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: Icon(AppIcons.delete, size: 20, color: AppColors.error),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete Idea?'),
                        content: const Text('This will remove the idea permanently.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && ctx.mounted) {
                      Navigator.pop(ctx);
                      _deleteIdea(current['id']);
                    }
                  },
                  tooltip: 'Delete',
                ),
              ],
            ),
            content: SizedBox(
              width: 560,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    current['title'] ?? '',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  if (current['description'] != null && (current['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      current['description'],
                      style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Status quick-change row
                  Wrap(
                    spacing: 6,
                    children: _statusMeta.entries.map((e) {
                      final isActive = current['status'] == e.key;
                      return ChoiceChip(
                        label: Text(e.value.label, style: TextStyle(fontSize: 12, color: isActive ? Colors.white : e.value.color)),
                        selected: isActive,
                        selectedColor: e.value.color,
                        backgroundColor: e.value.color.withOpacity(0.08),
                        onSelected: (_) {
                          _updateIdea(current['id'], {'status': e.key});
                          setDlg(() {});
                        },
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  // Comments header
                  Row(
                    children: [
                      Icon(AppIcons.chat, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Comments (${curComments.length})',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Comments list
                  Expanded(
                    child: curComments.isEmpty
                        ? Center(
                            child: Text('No comments yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                          )
                        : ListView.builder(
                            itemCount: curComments.length,
                            itemBuilder: (_, i) {
                              final c = curComments[i];
                              final cDate = DateTime.tryParse(c['created_at'] ?? '');
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHoverLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(c['body'] ?? '', style: const TextStyle(fontSize: 13, height: 1.4)),
                                          if (cDate != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                '${cDate.day}/${cDate.month}/${cDate.year} ${cDate.hour}:${cDate.minute.toString().padLeft(2, '0')}',
                                                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(AppIcons.delete, size: 16, color: Colors.grey.shade400),
                                      onPressed: () {
                                        _deleteComment(current['id'], c['id']);
                                        setDlg(() {});
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Delete comment',
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  // Add comment
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentCtrl,
                          decoration: InputDecoration(
                            hintText: 'Add a comment…',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            final text = v.trim();
                            if (text.isEmpty) return;
                            commentCtrl.clear();
                            _addComment(current['id'], text);
                            setDlg(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(AppIcons.send, color: AppColors.primary),
                        onPressed: () {
                          final text = commentCtrl.text.trim();
                          if (text.isEmpty) return;
                          commentCtrl.clear();
                          _addComment(current['id'], text);
                          setDlg(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  // ── Edit Dialog ─────────────────────────────────────────────────────────

  void _showEditDialog(Map<String, dynamic> idea) {
    final titleCtrl = TextEditingController(text: idea['title'] ?? '');
    final descCtrl = TextEditingController(text: idea['description'] ?? '');
    String tag = idea['feature_tag'] ?? 'general';
    String priority = idea['priority'] ?? 'medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(AppIcons.edit, size: 22),
              SizedBox(width: 8),
              Text('Edit Idea'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 300,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  _buildTagField(tag, (v) => setDlg(() => tag = v)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _priorityMeta.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Row(
                          children: [
                            Icon(e.value.icon, color: e.value.color, size: 16),
                            const SizedBox(width: 6),
                            Text(e.value.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setDlg(() => priority = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                _updateIdea(idea['id'], {
                  'title': title,
                  'description': descCtrl.text.trim(),
                  'feature_tag': tag,
                  'priority': priority,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tag Field Widget (Dropdown + Custom) ──────────────────────────────────────

class _TagFieldWidget extends StatefulWidget {
  final List<String> allTags;
  final String initialTag;
  final String initialDropdownValue;
  final bool isInitiallyCustom;
  final ValueChanged<String> onChanged;

  const _TagFieldWidget({
    required this.allTags,
    required this.initialTag,
    required this.initialDropdownValue,
    required this.isInitiallyCustom,
    required this.onChanged,
  });

  @override
  State<_TagFieldWidget> createState() => _TagFieldWidgetState();
}

class _TagFieldWidgetState extends State<_TagFieldWidget> {
  late String _dropdownValue;
  late bool _showCustom;
  late TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    _dropdownValue = widget.initialDropdownValue;
    _showCustom = widget.isInitiallyCustom;
    _customCtrl = TextEditingController(
      text: widget.isInitiallyCustom ? widget.initialTag : '',
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          value: _dropdownValue,
          decoration: const InputDecoration(
            labelText: 'Feature Tag',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            ...widget.allTags.map((t) => DropdownMenuItem(
              value: t,
              child: Text('#$t'),
            )),
            const DropdownMenuItem(
              value: '_custom_',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: AppColors.activeBlue),
                  SizedBox(width: 6),
                  Text('Custom tag…', style: TextStyle(color: AppColors.activeBlue, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _dropdownValue = v;
              _showCustom = v == '_custom_';
            });
            if (v != '_custom_') {
              widget.onChanged(v);
            }
          },
        ),
        if (_showCustom) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _customCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Custom Tag',
              hintText: 'e.g. onboarding, mobile, performance',
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '#',
            ),
            onChanged: (v) {
              final tag = v.trim();
              widget.onChanged(tag.isEmpty ? 'general' : tag);
            },
          ),
        ],
      ],
    );
  }
}
