import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/admin_models.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../models/admin_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/app_header.dart';

class AdminCenterScreen extends StatefulWidget {
  const AdminCenterScreen({super.key});

  @override
  State<AdminCenterScreen> createState() => _AdminCenterScreenState();
}

class _AdminCenterScreenState extends State<AdminCenterScreen> {
  late AdminService _adminService;
  int _selectedTabIndex = 0;
  final TextEditingController _householdSearchController = TextEditingController();
  final TextEditingController _householdNotesController = TextEditingController();
  List<AdminHouseholdSummary> _households = [];
  AdminHouseholdDetail? _selectedHousehold;
  String? _selectedHouseholdId;
  bool _householdsLoading = false;
  bool _householdsLoaded = false;
  bool _suspendedOnly = false;
  String? _householdsError;

  // Staff tab state
  List<AdminStaff> _staff = [];
  bool _staffLoading = false;
  bool _staffLoaded = false;
  String? _staffError;

  // Users tab state
  final TextEditingController _usersSearchController = TextEditingController();
  List<AdminUser> _users = [];
  bool _usersLoading = false;
  bool _usersLoaded = false;
  String? _usersError;

  // Approvals tab state
  List<AdminApprovalRequest> _approvals = [];
  bool _approvalsLoading = false;
  bool _approvalsLoaded = false;
  String _approvalsStatusFilter = 'pending';
  String? _approvalsError;

  @override
  void initState() {
    super.initState();
    _adminService = context.read<AdminService>();
    _loadStats();
  }

  @override
  void dispose() {
    _householdSearchController.dispose();
    _householdNotesController.dispose();
    _usersSearchController.dispose();
    super.dispose();
  }

  void _loadStats() {
    _adminService.fetchStats();
  }

  Future<void> _selectTab(int index) async {
    setState(() {
      _selectedTabIndex = index;
    });

    if (index == 1 && !_householdsLoaded && !_householdsLoading) {
      await _loadHouseholds();
    }

    if (index == 2 && !_usersLoaded && !_usersLoading) {
      await _loadUsers();
    }

    if (index == 7 && _adminService.auditLogs.isEmpty && !_adminService.isLoading) {
      await _adminService.fetchAuditLogs();
    }

    if (index == 8 && !_staffLoaded && !_staffLoading) {
      await _loadStaff();
    }

    if (index == 9 && !_approvalsLoaded && !_approvalsLoading) {
      await _loadApprovals();
    }
  }

  Future<void> _loadHouseholds() async {
    setState(() {
      _householdsLoading = true;
      _householdsError = null;
    });

    try {
      final households = await _adminService.fetchHouseholds(
        query: _householdSearchController.text,
        suspendedOnly: _suspendedOnly,
      );

      setState(() {
        _households = households;
        _householdsLoaded = true;
        _householdsLoading = false;
      });

      final selectedId = _selectedHouseholdId;
      if (selectedId != null && households.any((row) => row.id == selectedId)) {
        await _loadHouseholdDetail(selectedId);
      } else if (households.isNotEmpty) {
        await _loadHouseholdDetail(households.first.id);
      } else {
        setState(() {
          _selectedHousehold = null;
          _selectedHouseholdId = null;
          _householdNotesController.clear();
        });
      }
    } catch (e) {
      setState(() {
        _householdsLoading = false;
        _householdsError = e.toString();
      });
    }
  }

  Future<void> _loadStaff() async {
    setState(() {
      _staffLoading = true;
      _staffError = null;
    });
    try {
      final result = await _adminService.fetchStaff();
      setState(() {
        _staff = result;
        _staffLoaded = true;
        _staffLoading = false;
      });
    } catch (e) {
      setState(() {
        _staffLoading = false;
        _staffError = e.toString();
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final result = await _adminService.fetchUsers(
        query: _usersSearchController.text,
      );
      setState(() {
        _users = result;
        _usersLoaded = true;
        _usersLoading = false;
      });
    } catch (e) {
      setState(() {
        _usersLoading = false;
        _usersError = e.toString();
      });
    }
  }

  Future<void> _loadApprovals() async {
    setState(() {
      _approvalsLoading = true;
      _approvalsError = null;
    });
    try {
      final result = await _adminService.fetchApprovalRequests(
        status: _approvalsStatusFilter == 'all' ? null : _approvalsStatusFilter,
      );
      setState(() {
        _approvals = result;
        _approvalsLoaded = true;
        _approvalsLoading = false;
      });
    } catch (e) {
      setState(() {
        _approvalsLoading = false;
        _approvalsError = e.toString();
      });
    }
  }

  Future<void> _loadHouseholdDetail(String householdId) async {
    setState(() {
      _selectedHouseholdId = householdId;
    });

    try {
      final detail = await _adminService.fetchHouseholdDetail(householdId);
      if (!mounted) return;

      setState(() {
        _selectedHousehold = detail;
        _householdNotesController.text = detail.adminNotes ?? '';
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load household details: $e')),
      );
    }
  }

  Future<void> _saveHouseholdNotes() async {
    final detail = _selectedHousehold;
    if (detail == null) return;

    try {
      final updated = await _adminService.updateHouseholdNotes(
        householdId: detail.id,
        notes: _householdNotesController.text,
      );

      if (!mounted) return;
      setState(() {
        _selectedHousehold = updated;
        _householdNotesController.text = updated.adminNotes ?? '';
      });

      await _loadHouseholds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin notes updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update notes: $e')),
      );
    }
  }

  Future<void> _toggleHouseholdSuspension({required bool suspend}) async {
    final detail = _selectedHousehold;
    if (detail == null) return;

    final reasonController = TextEditingController();
    final actionLabel = suspend ? 'Suspend' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('$actionLabel Household'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Household: ${detail.name}'),
              const SizedBox(height: 12),
              const Text('Reason (required for audit log):'),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter reason',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    final reason = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || reason.isEmpty) {
      return;
    }

    try {
      final updated = suspend
          ? await _adminService.suspendHousehold(
              householdId: detail.id,
              reason: reason,
            )
          : await _adminService.reactivateHousehold(
              householdId: detail.id,
              reason: reason,
            );

      if (!mounted) return;
      setState(() {
        _selectedHousehold = updated;
        _householdNotesController.text = updated.adminNotes ?? '';
      });
      await _loadHouseholds();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Household ${suspend ? 'suspended' : 'reactivated'} successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update household status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final adminService = context.watch<AdminService>();

    // Permission check
    final isAdmin = user?.isPlatformAdmin == true;
    final canViewHouseholds = user?.hasAdminPermission(AdminPermissions.viewHouseholds) == true;
    final canViewUsers = user?.hasAdminPermission(AdminPermissions.viewUsers) == true;
    final canViewAnalytics = user?.hasAdminPermission(AdminPermissions.viewAnalytics) == true;
    final canViewAuditLogs = user?.hasAdminPermission(AdminPermissions.viewAuditLogs) == true;
    final canManageFeatures = user?.hasAdminPermission(AdminPermissions.manageFeatures) == true;
    final canManageStaff = user?.hasAdminPermission(AdminPermissions.manageStaff) == true;
    final canManageHouseholds = user?.hasAdminPermission(AdminPermissions.manageHouseholds) == true;
    final canManageSecurity = user?.hasAdminPermission(AdminPermissions.manageSecurity) == true;

    if (!isAdmin) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.adminPanel,
                size: 64,
                color: AppColors.grey400,
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin Access Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only super admins and support staff can access this center.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Admin Center',
              avatarIcon: AppIcons.adminPanel,
              showViewModeSelector: false,
              showSettingsButton: false,
              showNotifications: false,
            ),
            Expanded(
              child: Row(
                children: [
                  // Sidebar
                  Container(
                    width: 256,
                    color: const Color(0xFFF8FAFC),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Admin info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: AppColors.grey200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.displayName ?? 'Admin',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user?.role == 'super_admin' ? 'Super Admin' : 'Support Staff',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.grey600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Navigation items
                            _NavItem(
                              label: 'Dashboard',
                              icon: Icons.dashboard_rounded,
                              isSelected: _selectedTabIndex == 0,
                              onTap: () => _selectTab(0),
                            ),
                            if (canViewHouseholds)
                              _NavItem(
                                label: 'Households',
                                icon: Icons.home_work_outlined,
                                isSelected: _selectedTabIndex == 1,
                                onTap: () => _selectTab(1),
                              ),
                            if (canViewUsers)
                              _NavItem(
                                label: 'Users',
                                icon: Icons.people_outlined,
                                isSelected: _selectedTabIndex == 2,
                                onTap: () => _selectTab(2),
                              ),
                            _NavItem(
                              label: 'Subscriptions',
                              icon: Icons.card_membership_outlined,
                              isSelected: _selectedTabIndex == 3,
                              onTap: () => _selectTab(3),
                            ),
                            _NavItem(
                              label: 'Plans',
                              icon: Icons.layers_outlined,
                              isSelected: _selectedTabIndex == 4,
                              onTap: () => _selectTab(4),
                            ),
                            if (canManageFeatures)
                              _NavItem(
                                label: 'Features',
                                icon: Icons.toggle_on_outlined,
                                isSelected: _selectedTabIndex == 5,
                                onTap: () => _selectTab(5),
                              ),
                            if (canViewAnalytics)
                              _NavItem(
                                label: 'Analytics',
                                icon: Icons.analytics_outlined,
                                isSelected: _selectedTabIndex == 6,
                                onTap: () => _selectTab(6),
                              ),
                            if (canViewAuditLogs)
                              _NavItem(
                                label: 'Audit Logs',
                                icon: Icons.history_outlined,
                                isSelected: _selectedTabIndex == 7,
                                onTap: () => _selectTab(7),
                              ),
                            if (canManageStaff || canManageSecurity) ...[
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              if (canManageStaff)
                                _NavItem(
                                  label: 'Staff',
                                  icon: Icons.admin_panel_settings_outlined,
                                  isSelected: _selectedTabIndex == 8,
                                  onTap: () => _selectTab(8),
                                ),
                              if (canManageSecurity)
                                _NavItem(
                                  label: 'Approvals',
                                  icon: Icons.approval_outlined,
                                  isSelected: _selectedTabIndex == 9,
                                  onTap: () => _selectTab(9),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Main content
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: _buildContent(adminService, canManageHouseholds),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AdminService adminService, bool canManageHouseholds) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildDashboard(adminService);
      case 1:
        return _buildHouseholdsTab(canManageHouseholds);
      case 2:
        return _buildUsersTab();
      case 3:
        return _buildPlaceholder('Subscriptions', 'Coming in Phase 3');
      case 4:
        return _buildPlaceholder('Plans', 'Coming in Phase 3');
      case 5:
        return _buildPlaceholder('Feature Toggles', 'Coming in Phase 4');
      case 6:
        return _buildPlaceholder('Analytics & Reports', 'Coming in Phase 5');
      case 7:
        return _buildAuditLogs(adminService);
      case 8:
        return _buildStaffTab();
      case 9:
        return _buildApprovalsTab();
      default:
        return _buildPlaceholder('Unknown', 'Unknown section');
    }
  }

  Widget _buildHouseholdsTab(bool canManageHouseholds) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Households Management',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _householdSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search households by name',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _loadHouseholds(),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Suspended only'),
                selected: _suspendedOnly,
                onSelected: (value) {
                  setState(() {
                    _suspendedOnly = value;
                  });
                  _loadHouseholds();
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _householdsLoading ? null : _loadHouseholds,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _buildHouseholdListPanel(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: _buildHouseholdDetailPanel(canManageHouseholds),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHouseholdListPanel() {
    if (_householdsLoading && _households.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_householdsError != null && _households.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _householdsError!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadHouseholds,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_households.isEmpty) {
      return _buildPanelCard(
        child: const Center(
          child: Text('No households found for this filter.'),
        ),
      );
    }

    return _buildPanelCard(
      child: ListView.separated(
        itemCount: _households.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final household = _households[index];
          final selected = household.id == _selectedHouseholdId;
          return ListTile(
            selected: selected,
            selectedTileColor: const Color(0xFFEFF6FF),
            title: Text(
              household.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${household.activeMemberCount}/${household.memberCount} active members • ${household.plan.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _StatusChip(
              label: household.suspended ? 'Suspended' : 'Active',
              color: household.suspended ? const Color(0xFFB91C1C) : const Color(0xFF047857),
            ),
            onTap: () => _loadHouseholdDetail(household.id),
          );
        },
      ),
    );
  }

  Widget _buildHouseholdDetailPanel(bool canManageHouseholds) {
    final household = _selectedHousehold;
    if (household == null) {
      return _buildPanelCard(
        child: const Center(
          child: Text('Select a household to view details.'),
        ),
      );
    }

    return _buildPanelCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    household.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusChip(
                  label: household.suspended ? 'Suspended' : 'Active',
                  color: household.suspended ? const Color(0xFFB91C1C) : const Color(0xFF047857),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Household ID: ${household.id}', style: const TextStyle(color: AppColors.grey600)),
            const SizedBox(height: 4),
            Text('Plan: ${household.plan.toUpperCase()}', style: const TextStyle(color: AppColors.grey600)),
            const SizedBox(height: 4),
            Text(
              'Members: ${household.activeMemberCount}/${household.memberCount} active',
              style: const TextStyle(color: AppColors.grey600),
            ),
            if (household.suspended && (household.suspensionReason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Text(
                'Suspension reason: ${household.suspensionReason}',
                style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 16),
            if (canManageHouseholds)
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: household.suspended
                        ? () => _toggleHouseholdSuspension(suspend: false)
                        : () => _toggleHouseholdSuspension(suspend: true),
                    icon: Icon(household.suspended ? Icons.restart_alt : Icons.block),
                    label: Text(household.suspended ? 'Reactivate' : 'Suspend'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          household.suspended ? const Color(0xFF2563EB) : const Color(0xFFB91C1C),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _loadHouseholdDetail(household.id),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const Text(
              'Admin Notes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _householdNotesController,
              enabled: canManageHouseholds,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Internal notes visible to admins only',
              ),
            ),
            const SizedBox(height: 8),
            if (canManageHouseholds)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saveHouseholdNotes,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Notes'),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Members',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (household.members.isEmpty)
              const Text('No members found')
            else
              ...household.members.map((member) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.displayName ?? member.email ?? 'Unknown member'),
                  subtitle: Text('${member.role}${member.email != null ? ' • ${member.email}' : ''}'),
                  trailing: _StatusChip(
                    label: member.isActive ? 'Active' : 'Disabled',
                    color: member.isActive ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.grey200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _buildDashboard(AdminService adminService) {
    if (adminService.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = adminService.stats;
    if (stats == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Unable to load admin statistics'),
            if (adminService.error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  adminService.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                adminService.fetchStats();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Dashboard',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          // Stats grid
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _StatCard(
                label: 'Total Households',
                value: stats.totalHouseholds.toString(),
                icon: Icons.home_work_outlined,
                color: const Color(0xFF3B82F6),
              ),
              _StatCard(
                label: 'Active Subscriptions',
                value: stats.activeSubscriptions.toString(),
                icon: Icons.card_membership_outlined,
                color: const Color(0xFF10B981),
              ),
              _StatCard(
                label: 'Total Users',
                value: stats.totalUsers.toString(),
                icon: Icons.people_outlined,
                color: const Color(0xFF8B5CF6),
              ),
              _StatCard(
                label: 'AI Usage (This Month)',
                value: stats.aiUsageThisMonth.toString(),
                icon: Icons.smart_toy_outlined,
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Last activity
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: AppColors.grey200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last Admin Activity',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (stats.lastAuditAction != null)
                  Text(
                    'Last action: ${stats.lastAuditAction!.toString().split('.')[0]}',
                    style: const TextStyle(
                      color: AppColors.grey600,
                      fontSize: 14,
                    ),
                  )
                else
                  const Text(
                    'No recent activity',
                    style: TextStyle(
                      color: AppColors.grey600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogs(AdminService adminService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Audit Logs',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          if (adminService.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (adminService.auditLogs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No audit logs found'),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: adminService.auditLogs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final log = adminService.auditLogs[index];
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getActionColor(log.action),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              log.action[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${log.actionLabel} ${log.resourceLabel}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'By: ${log.adminEmail}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.grey600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          log.createdAt.toString().split('.')[0],
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Users Management Tab ───────────────────────────────────────────────────

  Widget _buildUsersTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Users Management',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usersSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (_) => _loadUsers(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _usersLoading ? null : _loadUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildUsersPanel()),
        ],
      ),
    );
  }

  Widget _buildUsersPanel() {
    if (_usersLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_usersError != null && _users.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_usersError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadUsers, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return _buildPanelCard(child: const Center(child: Text('No users found.')));
    }

    return _buildPanelCard(
      child: ListView.separated(
        itemCount: _users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final u = _users[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: u.isPlatformAdmin
                  ? const Color(0xFFDBEAFE)
                  : const Color(0xFFF3F4F6),
              child: Icon(
                u.isPlatformAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                size: 20,
                color: u.isPlatformAdmin
                    ? const Color(0xFF3B82F6)
                    : AppColors.grey600,
              ),
            ),
            title: Text(
              u.displayName ?? u.email ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${u.email ?? ''}${u.householdName != null ? ' • ${u.householdName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusChip(
                  label: u.displayRoleName,
                  color: u.isPlatformAdmin
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF047857),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: u.isActive ? 'Active' : 'Inactive',
                  color: u.isActive
                      ? const Color(0xFF047857)
                      : const Color(0xFF9CA3AF),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Staff Management Tab ───────────────────────────────────────────────────

  Widget _buildStaffTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Staff Management',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: _staffLoading ? null : () => _showAddStaffDialog(),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add Staff'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _staffLoading ? null : _loadStaff,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'All staff mutations require a second super admin to approve (dual-approval).',
            style: TextStyle(fontSize: 12, color: AppColors.grey600),
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildStaffPanel()),
        ],
      ),
    );
  }

  Widget _buildStaffPanel() {
    if (_staffLoading && _staff.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_staffError != null && _staff.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_staffError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadStaff, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_staff.isEmpty) {
      return _buildPanelCard(child: const Center(child: Text('No staff members found.')));
    }

    return _buildPanelCard(
      child: ListView.separated(
        itemCount: _staff.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final s = _staff[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: s.isSuperAdmin
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFDBEAFE),
              child: Icon(
                Icons.admin_panel_settings_outlined,
                size: 20,
                color: s.isSuperAdmin
                    ? const Color(0xFFD97706)
                    : const Color(0xFF3B82F6),
              ),
            ),
            title: Text(
              s.displayName ?? s.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${s.email}  •  Scope: ${s.isGlobalScope ? 'Global' : s.staffScope}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusChip(
                  label: s.isSuperAdmin ? 'Super Admin' : 'Support Staff',
                  color: s.isSuperAdmin
                      ? const Color(0xFFD97706)
                      : const Color(0xFF3B82F6),
                ),
                if (!s.isSuperAdmin) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Update scope',
                    onPressed: () => _showUpdateScopeDialog(s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove_outlined, size: 18),
                    tooltip: 'Remove staff access',
                    color: const Color(0xFFB91C1C),
                    onPressed: () => _confirmRemoveStaff(s),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddStaffDialog() async {
    final emailCtrl = TextEditingController();
    final scopeCtrl = TextEditingController(text: 'global');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Support Staff'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Email is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: scopeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scope (\"global\" or household UUID)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Scope is required' : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'This action requires a second super admin to approve before taking effect.',
                style: TextStyle(fontSize: 12, color: AppColors.grey600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Submit for Approval'),
          ),
        ],
      ),
    );

    final email = emailCtrl.text.trim();
    final scope = scopeCtrl.text.trim();
    emailCtrl.dispose();
    scopeCtrl.dispose();

    if (confirmed != true) return;

    try {
      await _adminService.addStaff(email: email, initialScope: scope);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approval request submitted. A second super admin must approve.'),
        ),
      );
      await _loadStaff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _showUpdateScopeDialog(AdminStaff staff) async {
    final scopeCtrl = TextEditingController(text: staff.staffScope);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update Scope — ${staff.displayName ?? staff.email}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: scopeCtrl,
            decoration: const InputDecoration(
              labelText: 'New scope (\"global\" or household UUID)',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Scope is required' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Submit for Approval'),
          ),
        ],
      ),
    );

    final newScope = scopeCtrl.text.trim();
    scopeCtrl.dispose();

    if (confirmed != true) return;

    try {
      await _adminService.updateStaffScope(
        staffUserId: staff.id,
        staffScope: newScope,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scope change request submitted for approval.')),
      );
      await _loadStaff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _confirmRemoveStaff(AdminStaff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff Access'),
        content: Text(
          'Remove support staff access from ${staff.displayName ?? staff.email}?\n\n'
          'This requires a second super admin to approve.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit for Approval'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _adminService.removeStaff(staff.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removal request submitted for approval.')),
      );
      await _loadStaff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  // ── Approvals Queue Tab ────────────────────────────────────────────────────

  Widget _buildApprovalsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Approval Queue',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Staff mutations submitted by other super admins awaiting your decision.',
            style: TextStyle(fontSize: 13, color: AppColors.grey600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Status filter
              ...['pending', 'approved', 'rejected', 'all'].map((status) {
                final selected = _approvalsStatusFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status == 'all' ? 'All' : _capitalize(status)),
                    selected: selected,
                    onSelected: (_) async {
                      setState(() {
                        _approvalsStatusFilter = status;
                        _approvalsLoaded = false;
                      });
                      await _loadApprovals();
                    },
                  ),
                );
              }),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _approvalsLoading ? null : _loadApprovals,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildApprovalsPanel()),
        ],
      ),
    );
  }

  Widget _buildApprovalsPanel() {
    if (_approvalsLoading && _approvals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_approvalsError != null && _approvals.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_approvalsError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadApprovals, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_approvals.isEmpty) {
      return _buildPanelCard(
        child: Center(
          child: Text('No ${_approvalsStatusFilter == 'all' ? '' : _approvalsStatusFilter + ' '}requests found.'),
        ),
      );
    }

    return _buildPanelCard(
      child: ListView.separated(
        itemCount: _approvals.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final req = _approvals[index];
          return _buildApprovalRow(req);
        },
      ),
    );
  }

  Widget _buildApprovalRow(AdminApprovalRequest req) {
    final statusColor = _approvalStatusColor(req.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.assignment_outlined, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatActionType(req.actionType),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Requested by: ${req.requestedByEmail}',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey600),
                ),
                if (req.reason != null && req.reason!.isNotEmpty)
                  Text(
                    'Reason: ${req.reason}',
                    style: const TextStyle(fontSize: 12, color: AppColors.grey600),
                  ),
                if (req.decidedAt != null)
                  Text(
                    'Decided by: ${req.approvedByEmail ?? 'Unknown'} at '
                    '${req.decidedAt!.toString().split('.')[0]}',
                    style: const TextStyle(fontSize: 12, color: AppColors.grey600),
                  ),
                Text(
                  'Submitted: ${req.requestedAt.toString().split('.')[0]}',
                  style: const TextStyle(fontSize: 11, color: AppColors.grey400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusChip(label: _capitalize(req.status), color: statusColor),
              if (req.isPending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _handleApprovalDecision(req, approve: false),
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                        side: const BorderSide(color: Color(0xFFB91C1C)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () => _handleApprovalDecision(req, approve: true),
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprovalDecision(
    AdminApprovalRequest req, {
    required bool approve,
  }) async {
    final action = approve ? 'Approve' : 'Reject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Request'),
        content: Text(
          '$action "${_formatActionType(req.actionType)}" submitted by ${req.requestedByEmail}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  approve ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (approve) {
        await _adminService.approveApprovalRequest(approvalRequestId: req.id);
      } else {
        await _adminService.rejectApprovalRequest(approvalRequestId: req.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request ${approve ? 'approved' : 'rejected'} successfully.')),
      );
      setState(() {
        _approvalsLoaded = false;
      });
      await _loadApprovals();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Color _approvalStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'approved':
        return const Color(0xFF047857);
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return AppColors.grey600;
    }
  }

  String _formatActionType(String actionType) {
    return actionType
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _buildPlaceholder(String title, String subtitle) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: [
                Icon(
                  AppIcons.info,
                  size: 64,
                  color: AppColors.grey400,
                ),
                const SizedBox(height: 16),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.grey600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'create':
        return const Color(0xFF10B981);
      case 'update':
        return const Color(0xFF3B82F6);
      case 'delete':
        return const Color(0xFFEF4444);
      case 'suspend':
        return const Color(0xFFF59E0B);
      default:
        return AppColors.grey600;
    }
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? const Color(0xFF3B82F6) : AppColors.grey600,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? const Color(0xFF3B82F6) : AppColors.grey700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.grey200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
