import 'package:flutter/material.dart';
import '../models/admin_models.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';
import 'package:intl/intl.dart';

/// Tabbed detail panel shown when a household is selected in the
/// admin Households Management screen.
class AdminHouseholdDetailTabs extends StatefulWidget {
  const AdminHouseholdDetailTabs({
    super.key,
    required this.household,
    required this.adminService,
    required this.canManage,
    required this.notesController,
    required this.onSuspendToggle,
    required this.onReload,
    required this.onSaveNotes,
    required this.onChangePlan,
    required this.onToggleFeatureOverride,
    this.onUserTap,
  });

  final AdminHouseholdDetail household;
  final AdminService adminService;
  final bool canManage;
  final TextEditingController notesController;
  final VoidCallback onSuspendToggle;
  final VoidCallback onReload;
  final VoidCallback onSaveNotes;
  final void Function(String householdId, String planName) onChangePlan;
  final void Function(String householdId, String flagId, bool isEnabled)
      onToggleFeatureOverride;
  final void Function(AdminUser user)? onUserTap;

  @override
  State<AdminHouseholdDetailTabs> createState() =>
      _AdminHouseholdDetailTabsState();
}

class _AdminHouseholdDetailTabsState extends State<AdminHouseholdDetailTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Scoped data
  List<AdminUser>? _users;
  List<AdminSubscription>? _subscriptions;
  List<AdminFeatureFlag>? _featureFlags;
  List<AuditLog>? _auditLogs;
  List<AdminPlan>? _plans;

  Map<String, dynamic>? _aiSettings;
  Map<String, dynamic>? _aiUsage;
  bool _aiSettingsLoading = false;
  String? _aiSettingsError;
  bool _aiSettingsSaving = false;

  bool _usersLoading = false;
  bool _subscriptionsLoading = false;
  bool _featuresLoading = false;
  bool _auditLoading = false;
  bool _plansLoading = false;

  String? _usersError;
  String? _subscriptionsError;
  String? _featuresError;
  String? _auditError;

  String? _lastLoadedHouseholdId;

  static const _tabs = [
    Tab(text: 'Overview'),
    Tab(text: 'Users'),
    Tab(text: 'Subscription'),
    Tab(text: 'Features'),
    Tab(text: 'Analytics'),
    Tab(text: 'Audit Logs'),
    Tab(text: 'AI Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(AdminHouseholdDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.household.id != widget.household.id) {
      // Reset data when household changes
      _users = null;
      _subscriptions = null;
      _featureFlags = null;
      _auditLogs = null;
      _plans = null;
      _aiSettings = null;
      _aiUsage = null;
      _usersError = null;
      _subscriptionsError = null;
      _featuresError = null;
      _auditError = null;
      _aiSettingsError = null;
      _lastLoadedHouseholdId = null;
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadDataForTab(_tabController.index);
    }
  }

  Future<void> _loadDataForTab(int index) async {
    final hid = widget.household.id;
    switch (index) {
      case 1: // Users
        if (_users == null && !_usersLoading) _loadUsers(hid);
        break;
      case 2: // Subscription
        if (_subscriptions == null && !_subscriptionsLoading) {
          _loadSubscriptions(hid);
          if (_plans == null && !_plansLoading) _loadPlans();
        }
        break;
      case 3: // Features
        if (_featureFlags == null && !_featuresLoading) _loadFeatures(hid);
        break;
      case 4: // Analytics — uses overview data from household detail
        break;
      case 5: // Audit Logs
        if (_auditLogs == null && !_auditLoading) _loadAuditLogs(hid);
        break;
      case 6: // AI Settings
        if (_aiSettings == null && !_aiSettingsLoading) _loadAISettings(hid);
        break;
    }
  }

  Future<void> _loadUsers(String hid) async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await widget.adminService.fetchHouseholdUsers(hid);
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) setState(() => _usersError = '$e');
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _loadSubscriptions(String hid) async {
    setState(() {
      _subscriptionsLoading = true;
      _subscriptionsError = null;
    });
    try {
      final subs =
          await widget.adminService.fetchHouseholdSubscriptions(hid);
      if (mounted) setState(() => _subscriptions = subs);
    } catch (e) {
      if (mounted) setState(() => _subscriptionsError = '$e');
    } finally {
      if (mounted) setState(() => _subscriptionsLoading = false);
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _plansLoading = true);
    try {
      final plans = await widget.adminService.fetchPlans();
      if (mounted) setState(() => _plans = plans);
    } catch (_) {}
    if (mounted) setState(() => _plansLoading = false);
  }

  Future<void> _loadFeatures(String hid) async {
    setState(() {
      _featuresLoading = true;
      _featuresError = null;
    });
    try {
      final flags =
          await widget.adminService.fetchHouseholdFeatureFlags(hid);
      if (mounted) setState(() => _featureFlags = flags);
    } catch (e) {
      if (mounted) setState(() => _featuresError = '$e');
    } finally {
      if (mounted) setState(() => _featuresLoading = false);
    }
  }

  Future<void> _loadAISettings(String hid) async {
    setState(() {
      _aiSettingsLoading = true;
      _aiSettingsError = null;
    });
    try {
      final data = await widget.adminService.fetchHouseholdAISettings(hid);
      if (mounted) {
        setState(() {
          _aiSettings = data['ai_settings'] as Map<String, dynamic>?;
          _aiUsage = data['ai_usage'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _aiSettingsError = '$e');
    } finally {
      if (mounted) setState(() => _aiSettingsLoading = false);
    }
  }

  Future<void> _saveAISetting(String key, dynamic value) async {
    setState(() => _aiSettingsSaving = true);
    try {
      final data = await widget.adminService.updateHouseholdAISettings(
        householdId: widget.household.id,
        aiEnabled: key == 'ai_enabled' ? value as bool : null,
        chatQueriesLimit: key == 'chat_queries_limit' ? value as int : null,
        weeklySummariesLimit: key == 'weekly_summaries_limit' ? value as int : null,
        budgetAnalysisLimit: key == 'budget_analysis_limit' ? value as int : null,
        anomalyDetectionLimit: key == 'anomaly_detection_limit' ? value as int : null,
        simulatorLimit: key == 'simulator_limit' ? value as int : null,
      );
      if (mounted) {
        setState(() {
          _aiSettings = data['ai_settings'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _aiSettingsSaving = false);
    }
  }

  Future<void> _loadAuditLogs(String hid) async {
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final logs = await widget.adminService.fetchHouseholdAuditLogs(hid);
      if (mounted) setState(() => _auditLogs = logs);
    } catch (e) {
      if (mounted) setState(() => _auditError = '$e');
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = widget.household;
    return Column(
      children: [
        // ── Header row ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                household.name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            _StatusChip(
              label: household.suspended ? 'Suspended' : 'Active',
              color: household.suspended
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF047857),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'ID: ${household.id}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.grey600),
          ),
        ),
        const SizedBox(height: 12),

        // ── Tab bar ────────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: AppColors.grey600,
          indicatorColor: const Color(0xFF2563EB),
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: _tabs,
        ),
        const Divider(height: 1),

        // ── Tab content ────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildUsersTab(),
              _buildSubscriptionTab(),
              _buildFeaturesTab(),
              _buildAnalyticsTab(),
              _buildAuditLogsTab(),
              _buildAISettingsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 0: Overview
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    final h = widget.household;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Plan', h.plan.toUpperCase()),
          _infoRow('Members',
              '${h.activeMemberCount}/${h.memberCount} active'),
          _infoRow('Created', _formatDate(h.createdAt)),
          _infoRow('Updated', _formatDate(h.updatedAt)),
          if (h.suspended &&
              (h.suspensionReason?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Suspension reason: ${h.suspensionReason}',
                style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w500),
              ),
            ),
          const SizedBox(height: 16),

          // Action buttons
          if (widget.canManage)
            Row(
              children: [
                FilledButton.icon(
                  onPressed: widget.onSuspendToggle,
                  icon: Icon(h.suspended
                      ? Icons.restart_alt
                      : Icons.block),
                  label: Text(
                      h.suspended ? 'Reactivate' : 'Suspend'),
                  style: FilledButton.styleFrom(
                    backgroundColor: h.suspended
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onReload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Admin notes
          const Text('Admin Notes',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: widget.notesController,
            enabled: widget.canManage,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Internal notes visible to admins only',
            ),
          ),
          const SizedBox(height: 8),
          if (widget.canManage)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.onSaveNotes,
                icon: const Icon(Icons.save),
                label: const Text('Save Notes'),
              ),
            ),
          const SizedBox(height: 20),

          // Members list
          const Text('Members',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (h.members.isEmpty)
            const Text('No members found')
          else
            ...h.members.map((member) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.displayName ??
                      member.email ??
                      'Unknown member'),
                  subtitle: Text(
                      '${member.role}${member.email != null ? ' • ${member.email}' : ''}'),
                  trailing: _StatusChip(
                    label: member.isActive ? 'Active' : 'Disabled',
                    color: member.isActive
                        ? const Color(0xFF047857)
                        : const Color(0xFFB91C1C),
                  ),
                )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: Users
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildUsersTab() {
    if (_usersLoading) return const Center(child: CircularProgressIndicator());
    if (_usersError != null) return _errorRetry(_usersError!, () => _loadUsers(widget.household.id));
    if (_users == null) return const Center(child: Text('Loading...'));
    if (_users!.isEmpty) return const Center(child: Text('No users in this household.'));

    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: _users!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final user = _users![i];
        return ListTile(
          onTap: widget.onUserTap != null ? () => widget.onUserTap!(user) : null,
          leading: CircleAvatar(
            backgroundColor: user.isActive
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEE2E2),
            child: Icon(
              user.role == 'admin' ? Icons.admin_panel_settings : Icons.person,
              size: 20,
              color: user.isActive
                  ? const Color(0xFF047857)
                  : const Color(0xFFB91C1C),
            ),
          ),
          title: Text(user.displayName ?? user.email ?? 'Unknown'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user.email != null) Text(user.email!, style: const TextStyle(fontSize: 12)),
              Text(
                '${user.displayRoleName} • Joined ${_formatDate(user.createdAt)}',
                style: const TextStyle(fontSize: 12, color: AppColors.grey600),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusChip(
                label: user.isActive ? 'Active' : 'Disabled',
                color: user.isActive
                    ? const Color(0xFF047857)
                    : const Color(0xFFB91C1C),
              ),
              if (widget.onUserTap != null) ...[                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20, color: AppColors.grey600),
              ],
            ],
          ),
          isThreeLine: true,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: Subscription
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSubscriptionTab() {
    if (_subscriptionsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_subscriptionsError != null) {
      return _errorRetry(
          _subscriptionsError!, () => _loadSubscriptions(widget.household.id));
    }
    if (_subscriptions == null) return const Center(child: Text('Loading...'));

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Plan: ${widget.household.plan.toUpperCase()}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          if (_subscriptions!.isEmpty)
            const Text('No subscription records found.')
          else
            ..._subscriptions!.map((sub) => _buildSubscriptionCard(sub)),

          const SizedBox(height: 20),

          // Change plan section
          if (widget.canManage) ...[
            const Divider(),
            const SizedBox(height: 12),
            const Text('Change Plan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_plans != null)
              Wrap(
                spacing: 8,
                children: _plans!
                    .where((p) => p.name != widget.household.plan)
                    .map((plan) => OutlinedButton(
                          onPressed: () => widget.onChangePlan(
                              widget.household.id, plan.name),
                          child: Text('Switch to ${plan.displayName}'),
                        ))
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(AdminSubscription sub) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  sub.planDisplayName ?? sub.planName ?? 'Unknown Plan',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _StatusChip(
                  label: sub.statusLabel,
                  color: sub.isActive
                      ? const Color(0xFF047857)
                      : sub.isCancelled
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF92400E),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Billing', sub.billingCycle),
            _infoRow(
                'Amount',
                '${sub.currency} ${sub.amountPaid.toStringAsFixed(2)}'),
            _infoRow('Started', _formatDate(sub.startedAt)),
            if (sub.expiresAt != null)
              _infoRow('Expires', _formatDate(sub.expiresAt!)),
            if (sub.cancelledAt != null)
              _infoRow('Cancelled', _formatDate(sub.cancelledAt!)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: Features
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFeaturesTab() {
    if (_featuresLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_featuresError != null) {
      return _errorRetry(
          _featuresError!, () => _loadFeatures(widget.household.id));
    }
    if (_featureFlags == null) return const Center(child: Text('Loading...'));
    if (_featureFlags!.isEmpty) {
      return const Center(child: Text('No feature flags configured.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: _featureFlags!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final flag = _featureFlags![i];
        final hasOverride = flag.householdOverride != null;
        final effectivelyOn = flag.effectivelyEnabled;

        return ListTile(
          title: Row(
            children: [
              Expanded(child: Text(flag.displayName)),
              if (flag.isBeta)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('BETA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E))),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (flag.description != null)
                Text(flag.description!,
                    style: const TextStyle(fontSize: 12)),
              Row(
                children: [
                  Text(
                    'Global: ${flag.isEnabled ? 'ON' : 'OFF'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: flag.isEnabled
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                  if (hasOverride) ...[
                    const Text(' • ', style: TextStyle(fontSize: 12)),
                    Text(
                      'Override: ${flag.householdOverride!.isEnabled ? 'ON' : 'OFF'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: flag.householdOverride!.isEnabled
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: widget.canManage
              ? Switch(
                  value: effectivelyOn,
                  onChanged: (value) {
                    widget.onToggleFeatureOverride(
                      widget.household.id,
                      flag.id,
                      value,
                    );
                    // Refresh after toggle
                    Future.delayed(const Duration(milliseconds: 500), () {
                      _loadFeatures(widget.household.id);
                    });
                  },
                )
              : _StatusChip(
                  label: effectivelyOn ? 'ON' : 'OFF',
                  color: effectivelyOn
                      ? const Color(0xFF047857)
                      : const Color(0xFFB91C1C),
                ),
          isThreeLine: true,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: Analytics
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAnalyticsTab() {
    final h = widget.household;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Household Analytics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildStatGrid([
            _StatItem('Plan', h.plan.toUpperCase(), Icons.card_membership),
            _StatItem('Members', '${h.activeMemberCount}/${h.memberCount}',
                Icons.group),
            _StatItem('Status', h.suspended ? 'Suspended' : 'Active',
                Icons.info_outline),
            _StatItem('Created', _formatDate(h.createdAt), Icons.calendar_today),
          ]),
          const SizedBox(height: 20),
          const Text('Subscription History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_subscriptions != null && _subscriptions!.isNotEmpty)
            ..._subscriptions!.map((sub) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    sub.isActive ? Icons.check_circle : Icons.cancel,
                    color: sub.isActive
                        ? const Color(0xFF047857)
                        : const Color(0xFFB91C1C),
                    size: 20,
                  ),
                  title: Text(
                    '${sub.planDisplayName ?? sub.planName ?? "Plan"} - ${sub.statusLabel}',
                  ),
                  subtitle: Text(
                    '${sub.billingCycle} • ${sub.currency} ${sub.amountPaid.toStringAsFixed(0)} • Since ${_formatDate(sub.startedAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ))
          else
            const Text('No subscription data available. Switch to Subscription tab to load.',
                style: TextStyle(color: AppColors.grey600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatGrid(List<_StatItem> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map((item) => SizedBox(
                width: 160,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.grey200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, size: 20, color: AppColors.grey600),
                      const SizedBox(height: 8),
                      Text(item.value,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(item.label,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.grey600)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 5: Audit Logs
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAuditLogsTab() {
    if (_auditLoading) return const Center(child: CircularProgressIndicator());
    if (_auditError != null) {
      return _errorRetry(
          _auditError!, () => _loadAuditLogs(widget.household.id));
    }
    if (_auditLogs == null) return const Center(child: Text('Loading...'));
    if (_auditLogs!.isEmpty) {
      return const Center(child: Text('No audit log entries for this household.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: _auditLogs!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final log = _auditLogs![i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: _actionColor(log.action).withValues(alpha: 0.15),
            child: Icon(
              _actionIcon(log.action),
              size: 16,
              color: _actionColor(log.action),
            ),
          ),
          title: Text(
            '${log.actionLabel} ${log.resourceLabel}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${log.adminEmail} • ${_formatDateTime(log.createdAt)}',
            style: const TextStyle(fontSize: 12, color: AppColors.grey600),
          ),
          trailing: log.description != null
              ? SizedBox(
                  width: 120,
                  child: Text(
                    log.description!,
                    style: const TextStyle(fontSize: 11, color: AppColors.grey600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                )
              : null,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 6: AI Settings
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAISettingsTab() {
    if (_aiSettingsLoading) return const Center(child: CircularProgressIndicator());
    if (_aiSettingsError != null) {
      return _errorRetry(
          _aiSettingsError!, () => _loadAISettings(widget.household.id));
    }
    if (_aiSettings == null) return const Center(child: Text('Loading...'));

    final settings = _aiSettings!;
    final usage = _aiUsage ?? {};
    final aiEnabled = settings['ai_enabled'] as bool? ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Master toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: aiEnabled ? const Color(0xFF2563EB) : AppColors.grey600,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI Features',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          aiEnabled
                              ? 'AI features are enabled for this household'
                              : 'AI features are disabled for this household',
                          style: TextStyle(
                            fontSize: 13,
                            color: aiEnabled ? const Color(0xFF047857) : AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_aiSettingsSaving)
                    const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (widget.canManage)
                    Switch(
                      value: aiEnabled,
                      onChanged: (value) => _saveAISetting('ai_enabled', value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Usage Limits
          const Text('Usage Limits (per month)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          _buildLimitRow(
            icon: Icons.chat_bubble_outline,
            label: 'AI Chat Queries',
            settingKey: 'chat_queries_limit',
            currentLimit: (settings['chat_queries_limit'] as num?)?.toInt() ?? 5,
            currentUsage: (usage['chat_count'] as num?)?.toInt() ?? 0,
            enabled: aiEnabled,
          ),
          _buildLimitRow(
            icon: Icons.summarize_outlined,
            label: 'Weekly Summaries',
            settingKey: 'weekly_summaries_limit',
            currentLimit: (settings['weekly_summaries_limit'] as num?)?.toInt() ?? 1,
            currentUsage: usage['summary_generated_at'] != null ? 1 : 0,
            enabled: aiEnabled,
            suffix: '/week',
          ),
          _buildLimitRow(
            icon: Icons.analytics_outlined,
            label: 'Budget Analysis',
            settingKey: 'budget_analysis_limit',
            currentLimit: (settings['budget_analysis_limit'] as num?)?.toInt() ?? 10,
            currentUsage: (usage['budget_analysis_count'] as num?)?.toInt() ?? 0,
            enabled: aiEnabled,
          ),
          _buildLimitRow(
            icon: Icons.warning_amber_outlined,
            label: 'Anomaly Detection',
            settingKey: 'anomaly_detection_limit',
            currentLimit: (settings['anomaly_detection_limit'] as num?)?.toInt() ?? 5,
            currentUsage: (usage['anomaly_count'] as num?)?.toInt() ?? 0,
            enabled: aiEnabled,
          ),
          _buildLimitRow(
            icon: Icons.trending_up,
            label: 'Financial Simulator',
            settingKey: 'simulator_limit',
            currentLimit: (settings['simulator_limit'] as num?)?.toInt() ?? 5,
            currentUsage: (usage['simulator_count'] as num?)?.toInt() ?? 0,
            enabled: aiEnabled,
          ),

          const SizedBox(height: 20),

          // Quick presets
          if (widget.canManage && aiEnabled) ...[
            const Text('Quick Presets',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetButton('Free Tier', {
                  'chat_queries_limit': 5,
                  'weekly_summaries_limit': 1,
                  'budget_analysis_limit': 10,
                  'anomaly_detection_limit': 5,
                  'simulator_limit': 5,
                }),
                _presetButton('Premium', {
                  'chat_queries_limit': 50,
                  'weekly_summaries_limit': 7,
                  'budget_analysis_limit': 50,
                  'anomaly_detection_limit': 30,
                  'simulator_limit': 30,
                }),
                _presetButton('Unlimited', {
                  'chat_queries_limit': 9999,
                  'weekly_summaries_limit': 9999,
                  'budget_analysis_limit': 9999,
                  'anomaly_detection_limit': 9999,
                  'simulator_limit': 9999,
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLimitRow({
    required IconData icon,
    required String label,
    required String settingKey,
    required int currentLimit,
    required int currentUsage,
    required bool enabled,
    String suffix = '/month',
  }) {
    final usagePercent = currentLimit > 0 ? (currentUsage / currentLimit).clamp(0.0, 1.0) : 0.0;
    final isOverLimit = currentLimit > 0 && currentUsage >= currentLimit;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? const Color(0xFF2563EB) : AppColors.grey400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled ? null : AppColors.grey400,
                      )),
                  const SizedBox(height: 4),
                  // Usage bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usagePercent,
                      backgroundColor: AppColors.grey200,
                      valueColor: AlwaysStoppedAnimation(
                        isOverLimit
                            ? const Color(0xFFB91C1C)
                            : enabled
                                ? const Color(0xFF2563EB)
                                : AppColors.grey400,
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$currentUsage / $currentLimit used $suffix',
                    style: TextStyle(
                      fontSize: 11,
                      color: isOverLimit ? const Color(0xFFB91C1C) : AppColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.canManage && enabled) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: _aiSettingsSaving || currentLimit <= 0
                    ? null
                    : () => _saveAISetting(settingKey, currentLimit - 1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Decrease limit',
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$currentLimit',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _aiSettingsSaving
                    ? null
                    : () => _saveAISetting(settingKey, currentLimit + 1),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Increase limit',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String label, Map<String, int> limits) {
    return OutlinedButton(
      onPressed: _aiSettingsSaving
          ? null
          : () async {
              setState(() => _aiSettingsSaving = true);
              try {
                final data = await widget.adminService.updateHouseholdAISettings(
                  householdId: widget.household.id,
                  chatQueriesLimit: limits['chat_queries_limit'],
                  weeklySummariesLimit: limits['weekly_summaries_limit'],
                  budgetAnalysisLimit: limits['budget_analysis_limit'],
                  anomalyDetectionLimit: limits['anomaly_detection_limit'],
                  simulatorLimit: limits['simulator_limit'],
                );
                if (mounted) {
                  setState(() {
                    _aiSettings = data['ai_settings'] as Map<String, dynamic>?;
                  });
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to apply preset: $e'), backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) setState(() => _aiSettingsSaving = false);
              }
            },
      child: Text(label),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.grey600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _errorRetry(String error, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    try {
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return dt.toIso8601String().substring(0, 10);
    }
  }

  String _formatDateTime(DateTime dt) {
    try {
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {
      return dt.toIso8601String().substring(0, 16);
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'suspend':
        return const Color(0xFFB91C1C);
      case 'unsuspend':
      case 'create':
        return const Color(0xFF047857);
      case 'delete':
        return const Color(0xFFB91C1C);
      case 'update':
      case 'upgrade_plan':
      case 'downgrade_plan':
        return const Color(0xFF2563EB);
      default:
        return AppColors.grey600;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'suspend':
        return Icons.block;
      case 'unsuspend':
        return Icons.restart_alt;
      case 'create':
        return Icons.add_circle_outline;
      case 'delete':
        return Icons.delete_outline;
      case 'update':
        return Icons.edit;
      case 'upgrade_plan':
        return Icons.arrow_upward;
      case 'downgrade_plan':
        return Icons.arrow_downward;
      default:
        return Icons.info_outline;
    }
  }
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
