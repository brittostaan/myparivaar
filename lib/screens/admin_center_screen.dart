import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/admin_models.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../models/admin_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/admin_household_detail_tabs.dart';
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

  // Subscriptions tab state
  List<AdminSubscription> _subscriptions = [];
  bool _subscriptionsLoading = false;
  bool _subscriptionsLoaded = false;
  String _subscriptionsStatusFilter = 'active';
  String? _subscriptionsError;

  // Plans tab state
  List<AdminPlan> _plansList = [];
  bool _plansLoading = false;
  bool _plansLoaded = false;
  String? _plansError;

  // Feature Flags tab state
  List<AdminFeatureFlag> _featureFlags = [];
  bool _featureFlagsLoading = false;
  bool _featureFlagsLoaded = false;
  String? _featureFlagsError;
  String _featureFlagsFilter = 'all'; // 'all', 'ai', 'finance', 'integration', 'general'

  // Analytics tab state
  AdminAnalyticsOverview? _analyticsOverview;
  List<SubscriptionTrend> _subscriptionTrends = [];
  List<HouseholdTrend> _householdTrends = [];
  List<AdminActivitySummary> _adminActivity = [];
  List<AIUsageTrend> _aiUsageTrends = [];
  bool _analyticsLoading = false;
  bool _analyticsLoaded = false;
  String? _analyticsError;

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

    if (index == 3 && !_subscriptionsLoaded && !_subscriptionsLoading) {
      await _loadSubscriptions();
    }

    if (index == 4 && !_plansLoaded && !_plansLoading) {
      await _loadPlans();
    }

    if (index == 5 && !_featureFlagsLoaded && !_featureFlagsLoading) {
      await _loadFeatureFlags();
    }

    if (index == 6 && !_analyticsLoaded && !_analyticsLoading) {
      await _loadAnalytics();
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

  Future<void> _loadSubscriptions() async {
    setState(() {
      _subscriptionsLoading = true;
      _subscriptionsError = null;
    });
    try {
      final result = await _adminService.fetchSubscriptions(
        status: _subscriptionsStatusFilter == 'all' ? null : _subscriptionsStatusFilter,
      );
      setState(() {
        _subscriptions = result;
        _subscriptionsLoaded = true;
        _subscriptionsLoading = false;
      });
    } catch (e) {
      setState(() {
        _subscriptionsLoading = false;
        _subscriptionsError = e.toString();
      });
    }
  }

  Future<void> _loadPlans() async {
    setState(() {
      _plansLoading = true;
      _plansError = null;
    });
    try {
      final result = await _adminService.fetchPlans();
      setState(() {
        _plansList = result;
        _plansLoaded = true;
        _plansLoading = false;
      });
    } catch (e) {
      setState(() {
        _plansLoading = false;
        _plansError = e.toString();
      });
    }
  }

  Future<void> _loadFeatureFlags() async {
    setState(() {
      _featureFlagsLoading = true;
      _featureFlagsError = null;
    });
    try {
      final result = await _adminService.fetchFeatureFlags();
      setState(() {
        _featureFlags = result;
        _featureFlagsLoaded = true;
        _featureFlagsLoading = false;
      });
    } catch (e) {
      setState(() {
        _featureFlagsLoading = false;
        _featureFlagsError = e.toString();
      });
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _analyticsLoading = true;
      _analyticsError = null;
    });
    try {
      await Future.wait([
        _adminService.fetchAnalyticsOverview().then((ov) {
          if (mounted) {
            setState(() {
              _analyticsOverview = ov;
            });
          }
        }),
        _adminService.fetchSubscriptionTrends().then((trends) {
          if (mounted) {
            setState(() {
              _subscriptionTrends = trends;
            });
          }
        }),
        _adminService.fetchHouseholdTrends().then((trends) {
          if (mounted) {
            setState(() {
              _householdTrends = trends;
            });
          }
        }),
        _adminService.fetchAdminActivity().then((activity) {
          if (mounted) {
            setState(() {
              _adminActivity = activity;
            });
          }
        }),
        _adminService.fetchAIUsageTrends().then((trends) {
          if (mounted) {
            setState(() {
              _aiUsageTrends = trends;
            });
          }
        }),
      ]);
      if (mounted) {
        setState(() {
          _analyticsLoaded = true;
          _analyticsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyticsLoading = false;
          _analyticsError = e.toString();
        });
      }
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
        return _buildUsersTab(
          user?.hasAdminPermission(AdminPermissions.manageUsers) == true,
        );
      case 3:
        return _buildSubscriptionsTab();
      case 4:
        return _buildPlansTab();
      case 5:
        return _buildFeatureFlagsTab();
      case 6:
        return _buildAnalyticsTab();
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
      child: AdminHouseholdDetailTabs(
        household: household,
        adminService: _adminService,
        canManage: canManageHouseholds,
        notesController: _householdNotesController,
        onSuspendToggle: () => _toggleHouseholdSuspension(
          suspend: !household.suspended,
        ),
        onReload: () => _loadHouseholdDetail(household.id),
        onSaveNotes: _saveHouseholdNotes,
        onChangePlan: _changeHouseholdPlan,
        onToggleFeatureOverride: _toggleHouseholdFeatureOverride,
      ),
    );
  }

  Future<void> _changeHouseholdPlan(String householdId, String planName) async {
    try {
      await _adminService.changePlan(
        householdId: householdId,
        planName: planName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan changed to $planName'),
            backgroundColor: const Color(0xFF047857),
          ),
        );
        _loadHouseholdDetail(householdId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change plan: $e'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
    }
  }

  Future<void> _toggleHouseholdFeatureOverride(
      String householdId, String flagId, bool isEnabled) async {
    try {
      await _adminService.setHouseholdOverride(
        householdId: householdId,
        flagId: flagId,
        isEnabled: isEnabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feature override ${isEnabled ? 'enabled' : 'disabled'}'),
            backgroundColor: const Color(0xFF047857),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set override: $e'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
    }
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

  Widget _buildUsersTab(bool canManageUsers) {
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
          Expanded(child: _buildUsersPanel(canManageUsers)),
        ],
      ),
    );
  }

  Widget _buildUsersPanel(bool canManageUsers) {
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
          final isSuperAdmin = u.role == 'super_admin' || u.staffRole == 'super_admin';
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
                if (canManageUsers && !isSuperAdmin)
                  _UserActiveToggle(
                    isActive: u.isActive,
                    onToggle: () => _toggleUserActive(u),
                  )
                else
                  _StatusChip(
                    label: u.isActive ? 'Active' : 'Inactive',
                    color: u.isActive
                        ? const Color(0xFF047857)
                        : const Color(0xFF9CA3AF),
                  ),
                if (canManageUsers && !isSuperAdmin) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'Manage',
                    onSelected: (value) {
                      if (value == 'toggle_active') {
                        _toggleUserActive(u);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'toggle_active',
                        child: Row(
                          children: [
                            Icon(
                              u.isActive ? Icons.block : Icons.check_circle_outline,
                              size: 18,
                              color: u.isActive
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF047857),
                            ),
                            const SizedBox(width: 8),
                            Text(u.isActive ? 'Disable User' : 'Enable User'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleUserActive(AdminUser user) async {
    final newState = !user.isActive;
    final action = newState ? 'enable' : 'disable';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${newState ? 'Enable' : 'Disable'} User'),
        content: Text(
          'Are you sure you want to $action ${user.displayName ?? user.email ?? 'this user'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: newState
                  ? const Color(0xFF047857)
                  : const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(newState ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _adminService.toggleUserActive(
        userId: user.id,
        isActive: newState,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User ${newState ? 'enabled' : 'disabled'} successfully'),
          backgroundColor: const Color(0xFF047857),
        ),
      );
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to $action user: $e'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
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
                  label: s.displayRoleName,
                  color: s.isSuperAdmin
                      ? const Color(0xFFD97706)
                      : s.isCustomerService
                          ? const Color(0xFF7C3AED)
                          : s.isReader
                              ? const Color(0xFF6B7280)
                              : s.isBillingService
                                  ? const Color(0xFF0891B2)
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
    String selectedRole = 'support_staff';

    final roleOptions = {
      'support_staff': 'Support Staff',
      'customer_service': 'Customer Service',
      'reader': 'Reader',
      'billing_service': 'Billing Service',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Staff Member'),
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
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: roleOptions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedRole = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: scopeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Scope ("global" or household UUID)',
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
      ),
    );

    final email = emailCtrl.text.trim();
    final scope = scopeCtrl.text.trim();
    emailCtrl.dispose();
    scopeCtrl.dispose();

    if (confirmed != true) return;

    try {
      await _adminService.addStaff(
        email: email,
        initialScope: scope,
        staffRole: selectedRole,
      );
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

  // ── Subscriptions Tab ──────────────────────────────────────────────────────

  Widget _buildSubscriptionsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subscriptions',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ...['active', 'cancelled', 'expired', 'all'].map((s) {
                final selected = _subscriptionsStatusFilter == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s == 'all' ? 'All' : _capitalize(s)),
                    selected: selected,
                    onSelected: (_) async {
                      setState(() {
                        _subscriptionsStatusFilter = s;
                        _subscriptionsLoaded = false;
                      });
                      await _loadSubscriptions();
                    },
                  ),
                );
              }),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _subscriptionsLoading ? null : _loadSubscriptions,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildSubscriptionsPanel()),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsPanel() {
    if (_subscriptionsLoading && _subscriptions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_subscriptionsError != null && _subscriptions.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_subscriptionsError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadSubscriptions, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_subscriptions.isEmpty) {
      return _buildPanelCard(child: Center(
        child: Text('No ${_subscriptionsStatusFilter == 'all' ? '' : '$_subscriptionsStatusFilter '}subscriptions found.'),
      ));
    }

    return _buildPanelCard(
      child: ListView.separated(
        itemCount: _subscriptions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final sub = _subscriptions[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: sub.isActive
                  ? const Color(0xFFD1FAE5)
                  : const Color(0xFFF3F4F6),
              child: Icon(
                Icons.card_membership_outlined,
                size: 20,
                color: sub.isActive
                    ? const Color(0xFF047857)
                    : AppColors.grey400,
              ),
            ),
            title: Text(
              sub.householdName ?? sub.householdId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${sub.planDisplayName ?? sub.planName ?? 'Unknown plan'} • '
              'Started: ${sub.startedAt.toString().substring(0, 10)}',
              style: const TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusChip(
                  label: sub.planName?.toUpperCase() ?? 'UNKNOWN',
                  color: (sub.planName == 'paid')
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF3B82F6),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: sub.statusLabel,
                  color: sub.isActive
                      ? const Color(0xFF047857)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'change_plan') {
                      _showChangePlanDialog(sub);
                    } else if (value == 'cancel') {
                      _confirmCancelSubscription(sub);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'change_plan',
                      child: Text('Change Plan'),
                    ),
                    if (sub.isActive)
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text(
                          'Cancel Subscription',
                          style: TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChangePlanDialog(AdminSubscription sub) async {
    final availablePlans = _plansList.isNotEmpty
        ? _plansList
        : await _adminService.fetchPlans().onError((_, __) => []);

    if (!mounted) return;

    String selectedPlan = sub.planName ?? 'free';
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Change Plan — ${sub.householdName ?? sub.householdId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select new plan:'),
              const SizedBox(height: 8),
              if (availablePlans.isEmpty)
                const Text('No plans available', style: TextStyle(color: AppColors.grey600))
              else
                ...availablePlans.map((p) => RadioListTile<String>(
                  value: p.name,
                  groupValue: selectedPlan,
                  title: Text(p.displayName),
                  subtitle: Text(p.isFree ? 'Free' : '₹${p.priceMonthly.toStringAsFixed(0)}/mo'),
                  onChanged: (v) {
                    if (v != null) setLocalState(() => selectedPlan = v);
                  },
                )),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
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
              onPressed: selectedPlan == sub.planName
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Change Plan'),
            ),
          ],
        ),
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;

    try {
      await _adminService.changePlan(
        householdId: sub.householdId,
        planName: selectedPlan,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan changed successfully.')),
      );
      setState(() => _subscriptionsLoaded = false);
      await _loadSubscriptions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _confirmCancelSubscription(AdminSubscription sub) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cancel ${sub.planDisplayName ?? sub.planName} subscription for '
                '${sub.householdName ?? sub.householdId}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;

    try {
      await _adminService.cancelSubscription(
        subscriptionId: sub.id,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription cancelled.')),
      );
      setState(() => _subscriptionsLoaded = false);
      await _loadSubscriptions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  // ── Plans Tab ──────────────────────────────────────────────────────────────

  Widget _buildPlansTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Plans',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _plansLoading ? null : _loadPlans,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Platform subscription plan definitions and limits.',
            style: TextStyle(fontSize: 13, color: AppColors.grey600),
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildPlansPanel()),
        ],
      ),
    );
  }

  Widget _buildPlansPanel() {
    if (_plansLoading && _plansList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_plansError != null && _plansList.isEmpty) {
      return _buildPanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_plansError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadPlans, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_plansList.isEmpty) {
      return _buildPanelCard(child: const Center(child: Text('No plans found.')));
    }

    return SingleChildScrollView(
      child: Column(
        children: _plansList.map(_buildPlanCard).toList(),
      ),
    );
  }

  Widget _buildPlanCard(AdminPlan plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: plan.isFree ? AppColors.grey200 : const Color(0xFF8B5CF6),
          width: plan.isFree ? 1 : 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: plan.isActive ? 'Active' : 'Inactive',
                            color: plan.isActive
                                ? const Color(0xFF047857)
                                : AppColors.grey400,
                          ),
                        ],
                      ),
                      if (plan.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          plan.description!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        plan.isFree
                            ? 'Free'
                            : '₹${plan.priceMonthly.toStringAsFixed(0)}/month  •  ₹${plan.priceYearly.toStringAsFixed(0)}/year',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: plan.isFree
                              ? AppColors.grey600
                              : const Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showEditPlanDialog(plan),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Limits'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _PlanLimitItem(
                  icon: Icons.people_outlined,
                  label: 'Family Members',
                  value: '${plan.maxFamilyMembers}',
                ),
                _PlanLimitItem(
                  icon: Icons.summarize_outlined,
                  label: 'AI Summaries / week',
                  value: '${plan.aiWeeklySummaries}',
                ),
                _PlanLimitItem(
                  icon: Icons.chat_bubble_outline,
                  label: 'AI Chat / month',
                  value: '${plan.aiChatQueries}',
                ),
                _PlanLimitItem(
                  icon: Icons.upload_file_outlined,
                  label: 'CSV Import',
                  value: plan.csvImportEnabled ? 'Enabled' : 'Disabled',
                  positive: plan.csvImportEnabled,
                ),
                _PlanLimitItem(
                  icon: Icons.email_outlined,
                  label: 'Email Ingestion',
                  value: plan.emailIngestionEnabled ? 'Enabled' : 'Disabled',
                  positive: plan.emailIngestionEnabled,
                ),
                _PlanLimitItem(
                  icon: Icons.mic_outlined,
                  label: 'Voice Features',
                  value: plan.voiceFeaturesEnabled ? 'Enabled' : 'Disabled',
                  positive: plan.voiceFeaturesEnabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditPlanDialog(AdminPlan plan) async {
    final displayNameCtrl = TextEditingController(text: plan.displayName);
    final descCtrl = TextEditingController(text: plan.description ?? '');
    final priceMonthlyCtrl =
        TextEditingController(text: plan.priceMonthly.toStringAsFixed(2));
    final priceYearlyCtrl =
        TextEditingController(text: plan.priceYearly.toStringAsFixed(2));
    final maxMembersCtrl =
        TextEditingController(text: plan.maxFamilyMembers.toString());
    final aiSummariesCtrl =
        TextEditingController(text: plan.aiWeeklySummaries.toString());
    final aiChatCtrl =
        TextEditingController(text: plan.aiChatQueries.toString());
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${plan.displayName}'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: priceMonthlyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Price/month (₹)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            double.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: priceYearlyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Price/year (₹)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            double.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: maxMembersCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Max members',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            int.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: aiSummariesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'AI summaries/week',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            int.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: aiChatCtrl,
                        decoration: const InputDecoration(
                          labelText: 'AI chat/month',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            int.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
              ],
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
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final displayNameVal = displayNameCtrl.text.trim();
    final descVal = descCtrl.text.trim();
    final priceMonthly = double.tryParse(priceMonthlyCtrl.text.trim());
    final priceYearly = double.tryParse(priceYearlyCtrl.text.trim());
    final maxMembers = int.tryParse(maxMembersCtrl.text.trim());
    final aiSummaries = int.tryParse(aiSummariesCtrl.text.trim());
    final aiChat = int.tryParse(aiChatCtrl.text.trim());

    for (final c in [
      displayNameCtrl, descCtrl, priceMonthlyCtrl, priceYearlyCtrl,
      maxMembersCtrl, aiSummariesCtrl, aiChatCtrl,
    ]) {
      c.dispose();
    }

    if (confirmed != true) return;

    try {
      await _adminService.updatePlan(
        planId: plan.id,
        displayName: displayNameVal,
        description: descVal.isEmpty ? null : descVal,
        priceMonthly: priceMonthly,
        priceYearly: priceYearly,
        maxFamilyMembers: maxMembers,
        aiWeeklySummaries: aiSummaries,
        aiChatQueries: aiChat,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan updated successfully.')),
      );
      setState(() {
        _plansLoaded = false;
      });
      await _loadPlans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  // ── Feature Flags Tab ──────────────────────────────────────────────────────

  Widget _buildFeatureFlagsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Feature Flags',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Manage platform-wide feature toggles and household-specific overrides.',
            style: TextStyle(fontSize: 13, color: AppColors.grey600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in ['all', 'ai', 'finance', 'integration', 'general'])
                      FilterChip(
                        label: Text(category == 'all' ? 'All' : category.capitalizeFirst()),
                        selected: _featureFlagsFilter == category,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _featureFlagsFilter = category;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loadFeatureFlags,
                icon: const Icon(Icons.refresh_outlined, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildFeatureFlagsPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureFlagsPanel() {
    if (_featureFlagsLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_featureFlagsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error loading feature flags',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _featureFlagsError!,
              style: const TextStyle(fontSize: 13, color: AppColors.grey600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_featureFlags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.toggle_off_outlined, size: 48, color: AppColors.grey400),
            const SizedBox(height: 16),
            const Text(
              'No feature flags',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final filtered = _featureFlagsFilter == 'all'
        ? _featureFlags
        : _featureFlags.where((f) => f.category == _featureFlagsFilter).toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          for (int i = 0; i < filtered.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FeatureFlagRow(
              flag: filtered[i],
              onToggle: (isEnabled) => _handleToggleFlag(filtered[i], isEnabled),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleToggleFlag(AdminFeatureFlag flag, bool isEnabled) async {
    try {
      await _adminService.toggleFlag(flagId: flag.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${flag.displayName} toggled successfully'),
        ),
      );
      setState(() {
        _featureFlagsLoaded = false;
      });
      await _loadFeatureFlags();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  // ── Analytics & Reports Tab ────────────────────────────────────────────────

  Widget _buildAnalyticsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analytics & Reports',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Platform-wide usage statistics, trends, and admin activity monitoring.',
            style: TextStyle(fontSize: 13, color: AppColors.grey600),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildAnalyticsPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsPanel() {
    if (_analyticsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_analyticsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text('Error loading analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_analyticsError!, style: const TextStyle(fontSize: 13, color: AppColors.grey600), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadAnalytics, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Overview metrics
          if (_analyticsOverview != null)
            _buildAnalyticsOverviewCards(_analyticsOverview!),

          const SizedBox(height: 24),

          // Trends sections
          if (_subscriptionTrends.isNotEmpty) ...[
            _buildSubscriptionTrendsSection(),
            const SizedBox(height: 24),
          ],

          if (_householdTrends.isNotEmpty) ...[
            _buildHouseholdTrendsSection(),
            const SizedBox(height: 24),
          ],

          if (_aiUsageTrends.isNotEmpty) ...[
            _buildAIUsageTrendsSection(),
            const SizedBox(height: 24),
          ],

          if (_adminActivity.isNotEmpty)
            _buildAdminActivitySection(),
        ],
      ),
    );
  }

  Widget _buildAnalyticsOverviewCards(AdminAnalyticsOverview overview) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _AnalyticsCard(
          title: 'Total Households',
          value: overview.totalHouseholds.toString(),
          icon: Icons.home_work_outlined,
          color: const Color(0xFF3B82F6),
        ),
        _AnalyticsCard(
          title: 'Active Subscriptions',
          value: overview.activeSubscriptions.toString(),
          icon: Icons.card_membership_outlined,
          color: const Color(0xFF10B981),
        ),
        _AnalyticsCard(
          title: 'Total Users',
          value: overview.totalUsers.toString(),
          icon: Icons.people_outlined,
          color: const Color(0xFF8B5CF6),
        ),
        _AnalyticsCard(
          title: 'AI Usage (Month)',
          value: overview.aiUsageThisMonth.toString(),
          icon: Icons.smart_toy_outlined,
          color: const Color(0xFFF59E0B),
        ),
        _AnalyticsCard(
          title: 'Churn Rate',
          value: '${overview.churnRateLastMonth.toStringAsFixed(1)}%',
          icon: Icons.trending_down_outlined,
          color: const Color(0xFFEF4444),
        ),
        _AnalyticsCard(
          title: 'Period',
          value: overview.period,
          icon: Icons.calendar_month_outlined,
          color: AppColors.grey600,
        ),
      ],
    );
  }

  Widget _buildSubscriptionTrendsSection() {
    final lastSix = _subscriptionTrends.length > 6 ? _subscriptionTrends.sublist(_subscriptionTrends.length - 6) : _subscriptionTrends;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Subscription Trends (Last 6 Months)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: AppColors.grey200), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final trend in lastSix) ...[
                  _MiniTrendCard(
                    month: trend.month,
                    label1: 'Active: ${trend.activeSubscriptions}',
                    label2: 'New: ${trend.newSubscriptions}',
                    label3: 'Cancelled: ${trend.cancelledSubscriptions}',
                  ),
                  const SizedBox(width: 12),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHouseholdTrendsSection() {
    final lastSix = _householdTrends.length > 6 ? _householdTrends.sublist(_householdTrends.length - 6) : _householdTrends;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Household Trends (Last 6 Months)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: AppColors.grey200), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final trend in lastSix) ...[
                  _MiniTrendCard(
                    month: trend.month,
                    label1: 'New: ${trend.newHouseholds}',
                    label2: 'Active: ${trend.activeHouseholds}',
                    label3: 'Suspended: ${trend.suspendedHouseholds}',
                  ),
                  const SizedBox(width: 12),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAIUsageTrendsSection() {
    final lastSix = _aiUsageTrends.length > 6 ? _aiUsageTrends.sublist(_aiUsageTrends.length - 6) : _aiUsageTrends;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI Usage Trends (Last 6 Months)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: AppColors.grey200), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final trend in lastSix) ...[
                  _MiniTrendCard(
                    month: trend.month,
                    label1: 'Queries: ${trend.totalChatQueries}',
                    label2: 'Summaries: ${trend.totalSummariesGenerated}',
                    label3: 'Avg/User: ${trend.averageQueriesPerUser.toStringAsFixed(1)}',
                  ),
                  const SizedBox(width: 12),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Admin Activity (Last 30 Days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (final admin in _adminActivity.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.grey100, borderRadius: BorderRadius.circular(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(admin.adminEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${admin.actionCount} actions', style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final action in admin.topActions.take(3))
                        Chip(
                          label: Text('${action.action}: ${action.count}', style: const TextStyle(fontSize: 11)),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
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

class _UserActiveToggle extends StatelessWidget {
  const _UserActiveToggle({
    required this.isActive,
    required this.onToggle,
  });

  final bool isActive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (isActive ? const Color(0xFF047857) : const Color(0xFFB91C1C))
              .withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (isActive ? const Color(0xFF047857) : const Color(0xFFB91C1C))
                .withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: isActive ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            ),
            const SizedBox(width: 4),
            Text(
              isActive ? 'Active' : 'Disabled',
              style: TextStyle(
                color: isActive ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanLimitItem extends StatelessWidget {
  const _PlanLimitItem({
    required this.icon,
    required this.label,
    required this.value,
    this.positive = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? const Color(0xFF047857) : AppColors.grey400;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.grey600),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Row widget for displaying a single feature flag with toggle
class _FeatureFlagRow extends StatelessWidget {
  const _FeatureFlagRow({
    required this.flag,
    required this.onToggle,
  });

  final AdminFeatureFlag flag;
  final Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      flag.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (flag.isBeta)
                      const Chip(
                        label: Text('Beta', style: TextStyle(fontSize: 11)),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      flag.category.capitalizeFirst(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grey600,
                      ),
                    ),
                  ],
                ),
                if (flag.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    flag.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.grey600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: flag.isEnabled,
            onChanged: (value) => onToggle(value),
            activeColor: const Color(0xFF0EA5E9),
          ),
        ],
      ),
    );
  }
}

/// Card widget for displaying a single analytics metric
class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
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
      constraints: const BoxConstraints(minWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: AppColors.grey600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }
}

/// Mini trend card for horizontal scrolling trend displays
class _MiniTrendCard extends StatelessWidget {
  const _MiniTrendCard({
    required this.month,
    required this.label1,
    required this.label2,
    required this.label3,
  });

  final String month;
  final String label1;
  final String label2;
  final String label3;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: AppColors.grey200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            month,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(label1, style: const TextStyle(fontSize: 11, color: AppColors.grey600)),
          const SizedBox(height: 4),
          Text(label2, style: const TextStyle(fontSize: 11, color: AppColors.grey600)),
          const SizedBox(height: 4),
          Text(label3, style: const TextStyle(fontSize: 11, color: AppColors.grey600)),
        ],
      ),
    );
  }
}

extension on String {
  String capitalizeFirst() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
