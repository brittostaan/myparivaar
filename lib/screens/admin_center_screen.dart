import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/admin_models.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../models/admin_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/admin_email_integration_panel.dart';
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

  // Email Integration tab state
  List<AdminEmailIntegrationAccount> _emailIntegrationAccounts = [];
  bool _emailIntegrationLoading = false;
  bool _emailIntegrationLoaded = false;
  String? _emailIntegrationError;
  Map<String, dynamic>? _emailIntegrationSummary;
  Map<String, dynamic>? _inboxInsightsData;
  List<Map<String, dynamic>> _oauthProviders = [];

  // Payment Gateways tab state
  List<Map<String, dynamic>> _paymentGatewaysList = [];
  bool _paymentGatewaysLoading = false;
  bool _paymentGatewaysLoaded = false;
  String? _paymentGatewaysError;

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

    if (index == 11 && !_emailIntegrationLoaded && !_emailIntegrationLoading) {
      await _loadEmailIntegrationAccounts();
    }

    if (index == 12 && !_paymentGatewaysLoaded && !_paymentGatewaysLoading) {
      await _loadPaymentGateways();
    }
  }

  Future<void> _loadEmailIntegrationAccounts() async {
    setState(() {
      _emailIntegrationLoading = true;
      _emailIntegrationError = null;
    });

    try {
      final results = await Future.wait([
        _adminService.fetchAdminEmailIntegrationAccounts(
          includeInactive: true,
        ),
        _adminService.fetchAdminEmailDashboardSummary(),
      ]);

      final result = results[0] as List<AdminEmailIntegrationAccount>;
      final summary = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _emailIntegrationAccounts = result;
        _emailIntegrationSummary = summary;
        _emailIntegrationLoaded = true;
        _emailIntegrationLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailIntegrationLoading = false;
        _emailIntegrationError = e.toString();
      });
    }

    // Load OAuth providers separately so a failure doesn't block the tab
    try {
      final providers = await _adminService.fetchOAuthProviders();
      if (mounted) setState(() => _oauthProviders = providers);
    } catch (_) {
      // OAuth provider loading failure is non-blocking
    }

    // Load inbox insights separately
    try {
      final insights = await _adminService.fetchEmailInboxInsights();
      if (mounted) setState(() => _inboxInsightsData = insights);
    } catch (_) {
      // Inbox insights loading failure is non-blocking
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
                            if (canManageFeatures) ...[
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              _NavItem(
                                label: 'AI',
                                icon: Icons.psychology_outlined,
                                isSelected: _selectedTabIndex == 10,
                                onTap: () => _selectTab(10),
                              ),
                              _NavItem(
                                label: 'Email Admin',
                                icon: Icons.email_outlined,
                                isSelected: _selectedTabIndex == 11,
                                onTap: () => _selectTab(11),
                              ),
                              _NavItem(
                                label: 'Payment Gateways',
                                icon: Icons.payment_outlined,
                                isSelected: _selectedTabIndex == 12,
                                onTap: () => _selectTab(12),
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            _NavItem(
                              label: 'Idea Board',
                              icon: Icons.lightbulb_outline,
                              isSelected: false,
                              onTap: () => Navigator.pushNamed(context, '/ideaboard'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Main content
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: _buildContent(adminService, canManageHouseholds, user?.hasAdminPermission(AdminPermissions.manageUsers) == true),
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

  Widget _buildContent(AdminService adminService, bool canManageHouseholds, bool canManageUsers) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildDashboard(adminService);
      case 1:
        return _buildHouseholdsTab(canManageHouseholds);
      case 2:
        return _buildUsersTab(canManageUsers);
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
      case 10:
        return _buildAITab();
      case 11:
        return _buildEmailIntegrationTab();
      case 12:
        return _buildPaymentGatewaysTab();
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
                  OutlinedButton.icon(
                    onPressed: () => _showUserManageDialog(u),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Manage'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
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

  Future<void> _showUserManageDialog(AdminUser user) async {
    // Fetch full user detail
    AdminUser? detailUser;
    String? loadError;

    try {
      detailUser = await _adminService.fetchUserDetail(user.id);
    } catch (e) {
      loadError = e.toString();
    }

    if (!mounted) return;

    if (loadError != null || detailUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load user details: ${loadError ?? "Unknown error"}'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
      return;
    }

    final u = detailUser;
    final firstNameCtrl = TextEditingController(text: u.firstName ?? '');
    final lastNameCtrl = TextEditingController(text: u.lastName ?? '');
    final displayNameCtrl = TextEditingController(text: u.displayName ?? '');
    final phoneCtrl = TextEditingController(text: u.phone ?? '');
    final dobCtrl = TextEditingController(
      text: u.dateOfBirth != null
          ? '${u.dateOfBirth!.year}-${u.dateOfBirth!.month.toString().padLeft(2, '0')}-${u.dateOfBirth!.day.toString().padLeft(2, '0')}'
          : '',
    );
    bool notificationsEnabled = u.notificationsEnabled;
    bool voiceEnabled = u.voiceEnabled;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: u.isPlatformAdmin
                              ? const Color(0xFFDBEAFE)
                              : const Color(0xFFF3F4F6),
                          child: Icon(
                            u.isPlatformAdmin
                                ? Icons.admin_panel_settings_outlined
                                : Icons.person_outline,
                            size: 28,
                            color: u.isPlatformAdmin
                                ? const Color(0xFF3B82F6)
                                : AppColors.grey600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u.displayName ?? u.email ?? 'Unknown User',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                u.email ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.grey600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(
                          label: u.displayRoleName,
                          color: u.isPlatformAdmin
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF047857),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(
                          label: u.isActive ? 'Active' : 'Disabled',
                          color: u.isActive
                              ? const Color(0xFF047857)
                              : const Color(0xFFB91C1C),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Meta info
                    Wrap(
                      spacing: 16,
                      children: [
                        Text(
                          'ID: ${u.id.substring(0, 8)}...',
                          style: const TextStyle(fontSize: 11, color: AppColors.grey600),
                        ),
                        if (u.householdName != null)
                          Text(
                            'Household: ${u.householdName}',
                            style: const TextStyle(fontSize: 11, color: AppColors.grey600),
                          ),
                        Text(
                          'Joined: ${u.createdAt.year}-${u.createdAt.month.toString().padLeft(2, '0')}-${u.createdAt.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: AppColors.grey600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // User Profile Section
                    const Text(
                      'User Profile',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: firstNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'First Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: lastNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Last Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        hintText: u.email ?? 'No email',
                      ),
                      controller: TextEditingController(text: u.email ?? ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dobCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date of Birth (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: u.dateOfBirth ?? DateTime(1990),
                          firstDate: DateTime(1920),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            dobCtrl.text =
                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Settings Section
                    const Text(
                      'Settings',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Notifications'),
                      subtitle: const Text('Push notifications enabled'),
                      value: notificationsEnabled,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => notificationsEnabled = v),
                    ),
                    SwitchListTile(
                      title: const Text('Voice Features'),
                      subtitle: const Text('Voice input and commands'),
                      value: voiceEnabled,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => voiceEnabled = v),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Actions
                    const Text(
                      'Account Actions',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _toggleUserActive(u);
                          },
                          icon: Icon(
                            u.isActive ? Icons.block : Icons.check_circle_outline,
                            size: 18,
                            color: u.isActive
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF047857),
                          ),
                          label: Text(u.isActive ? 'Disable User' : 'Enable User'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: u.isActive
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF047857),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showResetPasswordConfirm(ctx, u),
                          icon: const Icon(Icons.lock_reset, size: 18),
                          label: const Text('Reset Password'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Footer buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  setDialogState(() => saving = true);
                                  try {
                                    await _adminService.updateUser(
                                      userId: u.id,
                                      firstName: firstNameCtrl.text,
                                      lastName: lastNameCtrl.text,
                                      displayName: displayNameCtrl.text,
                                      phone: phoneCtrl.text,
                                      dateOfBirth: dobCtrl.text.isNotEmpty ? dobCtrl.text : null,
                                      notificationsEnabled: notificationsEnabled,
                                      voiceEnabled: voiceEnabled,
                                    );
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('User profile updated'),
                                          backgroundColor: Color(0xFF047857),
                                        ),
                                      );
                                      _loadUsers();
                                    }
                                  } catch (e) {
                                    setDialogState(() => saving = false);
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to save: $e'),
                                          backgroundColor: const Color(0xFFB91C1C),
                                        ),
                                      );
                                    }
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(saving ? 'Saving...' : 'Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    displayNameCtrl.dispose();
    phoneCtrl.dispose();
    dobCtrl.dispose();
  }

  void _showResetPasswordConfirm(BuildContext dialogCtx, AdminUser user) {
    showDialog(
      context: dialogCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
          'Send a password reset email to ${user.email ?? 'this user'}?\n\n'
          'The user will receive an email with instructions to set a new password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(
                  content: Text('Password reset email sent'),
                  backgroundColor: Color(0xFF047857),
                ),
              );
            },
            child: const Text('Send Reset Email'),
          ),
        ],
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
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildStaffPanel()),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _buildRolePermissionsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolePermissionsPanel() {
    const roles = <Map<String, dynamic>>[
      {
        'role': 'Super Admin',
        'color': Color(0xFFD97706),
        'icon': Icons.shield_outlined,
        'actions': [
          'Full platform access',
          'Manage all staff & roles',
          'Manage households & users',
          'Manage features & plans',
          'Configure payment gateways',
          'View & export analytics',
          'View audit logs',
          'Manage security settings',
          'Approve staff changes (dual-approval)',
        ],
      },
      {
        'role': 'Admin',
        'color': Color(0xFFEA580C),
        'icon': Icons.admin_panel_settings_outlined,
        'actions': [
          'Manage households & users',
          'Manage features & plans',
          'Moderate content',
          'Handle support tickets',
          'View & export analytics',
          'View audit logs',
        ],
      },
      {
        'role': 'Support Staff',
        'color': Color(0xFF3B82F6),
        'icon': Icons.support_agent_outlined,
        'actions': [
          'View households & users',
          'Moderate content',
          'Handle support tickets',
          'View analytics & audit logs',
        ],
      },
      {
        'role': 'Customer Service',
        'color': Color(0xFF7C3AED),
        'icon': Icons.headset_mic_outlined,
        'actions': [
          'View & manage users',
          'View households',
          'Handle support tickets',
          'View audit logs',
        ],
      },
      {
        'role': 'Reader',
        'color': Color(0xFF6B7280),
        'icon': Icons.visibility_outlined,
        'actions': [
          'View dashboard (read-only)',
          'View users & households',
          'View analytics & audit logs',
        ],
      },
      {
        'role': 'Billing Service',
        'color': Color(0xFF0891B2),
        'icon': Icons.receipt_long_outlined,
        'actions': [
          'View dashboard',
          'View users',
          'View analytics (billing focus)',
        ],
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Role Permissions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'What each role can do in the app',
              style: TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: roles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final r = roles[index];
                final color = r['color'] as Color;
                final actions = r['actions'] as List<String>;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(r['icon'] as IconData, size: 18, color: color),
                          const SizedBox(width: 8),
                          Text(
                            r['role'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...actions.map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 14, color: color.withValues(alpha: 0.7)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    a,
                                    style: const TextStyle(fontSize: 12, color: AppColors.grey600),
                                  ),
                                ),
                              ],
                            ),
                          )),
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
                      : s.isAdmin
                          ? const Color(0xFFEA580C)
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
      'super_admin': 'Super Admin',
      'admin': 'Admin',
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
    final payload = req.requestPayload;
    final targetEmail = payload['email'] as String?;
    final targetRole = payload['staff_role'] as String?;
    final targetScope = payload['initial_scope'] as String?;
    final newScope = payload['new_scope'] as String?;

    String _roleLabel(String role) {
      switch (role) {
        case 'super_admin': return 'Super Admin';
        case 'admin': return 'Admin';
        case 'support_staff': return 'Support Staff';
        case 'customer_service': return 'Customer Service';
        case 'reader': return 'Reader';
        case 'billing_service': return 'Billing Service';
        default: return role;
      }
    }

    // Build a human-readable summary of what this request does
    String summary;
    switch (req.actionType) {
      case 'assign_staff_role':
        final role = targetRole != null ? _roleLabel(targetRole) : 'staff';
        summary = 'Promote ${targetEmail ?? 'unknown user'} to $role';
        if (targetScope != null && targetScope != 'global') {
          summary += ' (scope: $targetScope)';
        }
        break;
      case 'revoke_staff_role':
        summary = 'Revoke staff access from ${targetEmail ?? 'unknown user'}';
        break;
      case 'change_staff_scope':
        summary = 'Change scope for ${targetEmail ?? 'unknown user'}';
        if (newScope != null) summary += ' to $newScope';
        break;
      default:
        summary = _formatActionType(req.actionType);
    }

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
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    summary,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 4),
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
    final payload = req.requestPayload;
    final targetEmail = payload['email'] as String?;
    final targetRole = payload['staff_role'] as String?;

    String detailText;
    if (req.actionType == 'assign_staff_role' && targetEmail != null) {
      final roleLabel = targetRole != null
          ? targetRole.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ')
          : 'staff';
      detailText = '$action promoting $targetEmail to $roleLabel?\n\nSubmitted by ${req.requestedByEmail}.';
    } else if (req.actionType == 'revoke_staff_role' && targetEmail != null) {
      detailText = '$action revoking staff access from $targetEmail?\n\nSubmitted by ${req.requestedByEmail}.';
    } else {
      detailText = '$action "${_formatActionType(req.actionType)}" submitted by ${req.requestedByEmail}?';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Request'),
        content: Text(detailText),
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

  Widget _buildEmailIntegrationTab() {
    final summary = _emailIntegrationSummary ?? const {};
    final providerCounts = summary['provider_counts'] as Map<String, dynamic>? ?? const {};
    final emailTx = summary['email_transactions'] as Map<String, dynamic>? ?? const {};

    String _countValue(String key) => '${summary[key] ?? 0}';
    String _providerValue(String key) => '${providerCounts[key] ?? 0}';
    String _emailTxValue(String key) => '${emailTx[key] ?? 0}';

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Email Administration',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connection status and ingestion analytics for household email integrations.',
                  style: TextStyle(color: AppColors.grey600),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Connected Accounts',
                        value: _countValue('total_connected_accounts'),
                        icon: Icons.alternate_email,
                        color: const Color(0xFF0EA5E9),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Active Connections',
                        value: _countValue('active_connections'),
                        icon: Icons.link,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Gmail Accounts',
                        value: _providerValue('gmail'),
                        icon: Icons.mail_outline,
                        color: const Color(0xFFDB4437),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Outlook Accounts',
                        value: _providerValue('outlook'),
                        icon: Icons.outbox_outlined,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Email Transactions Identified',
                        value: _countValue('emails_identified'),
                        icon: Icons.analytics_outlined,
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'AI Classification Requests (Month)',
                        value: _countValue('ai_classification_requests_current_month'),
                        icon: Icons.auto_awesome,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Email Tx Pending',
                        value: _emailTxValue('pending'),
                        icon: Icons.hourglass_top,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _StatCard(
                        label: 'Email Tx Approved',
                        value: _emailTxValue('approved'),
                        icon: Icons.check_circle_outline,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Token-level usage for email classification is not yet persisted; request counts are shown instead.',
                  style: TextStyle(fontSize: 12, color: AppColors.grey600),
                ),
              ],
            ),
          ),

          // ── OAuth Provider Configuration ─────────────────────────────────
          _buildOAuthProviderConfigSection(),

          // ── Email Inbox Insights ─────────────────────────────────────────
          _buildEmailInboxInsights(),

          AdminEmailIntegrationPanel(
            adminService: _adminService,
            accounts: _emailIntegrationAccounts,
            isLoading: _emailIntegrationLoading,
            error: _emailIntegrationError,
            onRefresh: () async {
              setState(() {
                _emailIntegrationLoaded = false;
              });
              await _loadEmailIntegrationAccounts();
            },
          ),
        ],
      ),
    );
  }

  // ── OAuth Provider Configuration Section ──────────────────────────────────

  Widget _buildOAuthProviderConfigSection() {
    final googleConfig = _oauthProviders
        .where((p) => p['provider'] == 'google')
        .toList();
    final microsoftConfig = _oauthProviders
        .where((p) => p['provider'] == 'microsoft')
        .toList();

    final hasGoogle = googleConfig.isNotEmpty;
    final hasMicrosoft = microsoftConfig.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key, size: 22),
              const SizedBox(width: 8),
              const Text(
                'OAuth Provider Configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  try {
                    final providers = await _adminService.fetchOAuthProviders();
                    if (mounted) {
                      setState(() => _oauthProviders = providers);
                    }
                  } catch (_) {}
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Configure Google and Microsoft OAuth credentials to enable email inbox connections for users.',
            style: TextStyle(color: AppColors.grey600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildOAuthProviderCard(
                provider: 'google',
                title: 'Google (Gmail)',
                icon: Icons.mail_outline,
                color: const Color(0xFFDB4437),
                isConfigured: hasGoogle,
                config: hasGoogle ? googleConfig.first : null,
              ),
              _buildOAuthProviderCard(
                provider: 'microsoft',
                title: 'Microsoft (Outlook)',
                icon: Icons.outbox_outlined,
                color: const Color(0xFF2563EB),
                isConfigured: hasMicrosoft,
                config: hasMicrosoft ? microsoftConfig.first : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthProviderCard({
    required String provider,
    required String title,
    required IconData icon,
    required Color color,
    required bool isConfigured,
    Map<String, dynamic>? config,
  }) {
    return SizedBox(
      width: 420,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isConfigured ? color.withOpacity(0.3) : Colors.grey.shade300,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isConfigured ? Colors.green : Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConfigured ? 'Connected' : 'Not Configured',
                              style: TextStyle(
                                fontSize: 12,
                                color: isConfigured ? Colors.green.shade700 : Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isConfigured)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      tooltip: 'Remove credentials',
                      onPressed: () => _confirmDeleteProvider(provider, title),
                    ),
                ],
              ),
              if (isConfigured && config != null) ...[
                const Divider(height: 24),
                _buildConfigDetail('Client ID', config['client_id_masked'] ?? '****'),
                const SizedBox(height: 4),
                _buildConfigDetail('Secret', '••••••••'),
                const SizedBox(height: 4),
                _buildConfigDetail('Updated', _formatConfigDate(config['updated_at'])),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showTestProviderResult(provider),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Test'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showOAuthConfigDialog(provider, title, config),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Update'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _showOAuthConfigDialog(provider, title, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Configure'),
                    style: FilledButton.styleFrom(backgroundColor: color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigDetail(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  String _formatConfigDate(dynamic dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr.toString());
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr.toString();
    }
  }

  void _showOAuthConfigDialog(String provider, String title, Map<String, dynamic>? existing) {
    final clientIdController = TextEditingController();
    final clientSecretController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Update $title Credentials' : 'Configure $title'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider == 'google'
                      ? 'Enter your Google Cloud OAuth 2.0 credentials.\nGet them from Google Cloud Console → APIs & Services → Credentials.'
                      : 'Enter your Azure App Registration credentials.\nGet them from Azure Portal → App Registrations.',
                  style: const TextStyle(fontSize: 13, color: AppColors.grey600),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Redirect URI: https://qimqakfjryptyhxmrjsj.supabase.co/functions/v1/email-oauthCallback',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.grey600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: clientIdController,
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    hintText: provider == 'google'
                        ? 'xxxx.apps.googleusercontent.com'
                        : 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientSecretController,
                  decoration: const InputDecoration(
                    labelText: 'Client Secret',
                    hintText: 'Paste secret value here',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final clientId = clientIdController.text.trim();
                      final clientSecret = clientSecretController.text.trim();
                      if (clientId.isEmpty || clientSecret.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Both Client ID and Client Secret are required')),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await _adminService.upsertOAuthProvider(
                          provider: provider,
                          clientId: clientId,
                          clientSecret: clientSecret,
                        );
                        if (mounted) {
                          setState(() {
                            _oauthProviders = _adminService.oauthProviders;
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$title credentials saved successfully')),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(existing != null ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProvider(String provider, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $title Credentials?'),
        content: Text(
          'This will disconnect $title OAuth integration. '
          'Existing connected email accounts will stop syncing until credentials are reconfigured.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _adminService.deleteOAuthProvider(provider);
                if (mounted) {
                  setState(() => _oauthProviders = _adminService.oauthProviders);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title credentials removed')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTestProviderResult(String provider) async {
    try {
      final result = await _adminService.testOAuthProvider(provider);
      final status = result['status'] ?? 'unknown';
      final message = result['message'] ?? 'No details';
      final checks = result['checks'] as Map<String, dynamic>?;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                status == 'valid' ? Icons.check_circle : Icons.warning,
                color: status == 'valid' ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text('Test Result: ${status == 'valid' ? 'Passed' : 'Issues Found'}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (checks != null) ...[
                const SizedBox(height: 12),
                ...checks.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        e.value == true ? Icons.check : Icons.close,
                        size: 16,
                        color: e.value == true ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(e.key.replaceAll('_', ' ')),
                    ],
                  ),
                )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

  // ── Email Inbox Insights Section ──────────────────────────────────────────

  Widget _buildEmailInboxInsights() {
    final data = _inboxInsightsData;
    if (data == null) return const SizedBox.shrink();

    final insights = data['insights'] as Map<String, dynamic>? ?? {};
    final accounts = (data['accounts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    Color healthColor(String? health) {
      switch (health) {
        case 'healthy': return const Color(0xFF16A34A);
        case 'stale': return const Color(0xFFF59E0B);
        case 'critical': return Colors.red;
        default: return Colors.grey;
      }
    }

    Color tokenColor(String? status) {
      switch (status) {
        case 'valid': return const Color(0xFF16A34A);
        case 'expiring_soon': return const Color(0xFFF59E0B);
        case 'expired': return Colors.red;
        default: return Colors.grey;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Email Inbox Insights',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Insights',
                  onPressed: () async {
                    try {
                      final result = await _adminService.fetchEmailInboxInsights();
                      if (mounted) setState(() => _inboxInsightsData = result);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to refresh insights: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Summary cards row
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InsightChip(
                  label: 'Needs Attention',
                  value: '${insights['needs_attention'] ?? 0}',
                  color: (insights['needs_attention'] ?? 0) > 0 ? Colors.red : Colors.grey,
                ),
                _InsightChip(
                  label: 'Healthy',
                  value: '${insights['healthy_accounts'] ?? 0}',
                  color: const Color(0xFF16A34A),
                ),
                _InsightChip(
                  label: 'Stale',
                  value: '${insights['stale_accounts'] ?? 0}',
                  color: const Color(0xFFF59E0B),
                ),
                _InsightChip(
                  label: 'Never Synced',
                  value: '${insights['never_synced'] ?? 0}',
                  color: Colors.grey,
                ),
                _InsightChip(
                  label: 'Expired Tokens',
                  value: '${insights['expired_tokens'] ?? 0}',
                  color: (insights['expired_tokens'] ?? 0) > 0 ? Colors.red : Colors.grey,
                ),
                _InsightChip(
                  label: 'Expiring Soon',
                  value: '${insights['expiring_soon_tokens'] ?? 0}',
                  color: (insights['expiring_soon_tokens'] ?? 0) > 0 ? const Color(0xFFF59E0B) : Colors.grey,
                ),
              ],
            ),

            if (accounts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Per-Account Health',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 44,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Provider', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Sync Health', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Token Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Last Sync', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Filters', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataColumn(label: Text('Scope', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  ],
                  rows: accounts.map((acct) {
                    final syncHealth = acct['sync_health'] as String? ?? 'unknown';
                    final tokenStatus = acct['token_status'] as String? ?? 'unknown';
                    final syncAgeHours = acct['sync_age_hours'] as num?;
                    final lastSyncLabel = syncAgeHours == null
                        ? 'Never'
                        : syncAgeHours < 1
                            ? '< 1h ago'
                            : '${syncAgeHours.toStringAsFixed(0)}h ago';

                    return DataRow(cells: [
                      DataCell(Text(acct['email_address'] ?? '—', style: const TextStyle(fontSize: 12))),
                      DataCell(Text((acct['provider'] ?? '—').toString().toUpperCase(), style: const TextStyle(fontSize: 12))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: healthColor(syncHealth).withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(syncHealth, style: TextStyle(fontSize: 11, color: healthColor(syncHealth), fontWeight: FontWeight.w600)),
                      )),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokenColor(tokenStatus).withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(tokenStatus, style: TextStyle(fontSize: 11, color: tokenColor(tokenStatus), fontWeight: FontWeight.w600)),
                      )),
                      DataCell(Text(lastSyncLabel, style: const TextStyle(fontSize: 12))),
                      DataCell(Text('${acct['filter_count'] ?? 0}', style: const TextStyle(fontSize: 12))),
                      DataCell(Text(acct['screening_scope'] ?? '—', style: const TextStyle(fontSize: 12))),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── AI Administration Tab ──────────────────────────────────────────────────

  bool _aiDataLoaded = false;
  Map<String, List<String>> _availableModels = {};

  Future<void> _loadAIData() async {
    if (_aiDataLoaded) return;
    try {
      await Future.wait([
        _adminService.fetchAIProviders(),
        _adminService.fetchAIKeys(),
        _adminService.fetchAITasks(),
      ]);
      _availableModels = await _adminService.fetchAvailableModels();
      _aiDataLoaded = true;
    } catch (_) {}
  }

  Widget _buildAITab() {
    return FutureBuilder(
      future: _loadAIData(),
      builder: (context, snapshot) {
        final adminService = context.watch<AdminService>();
        final providers = adminService.aiProviders;
        final keys = adminService.aiProviderKeys;
        final tasks = adminService.aiTaskAssignments;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Administration',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage AI provider connections, API keys, and task model assignments.',
                style: TextStyle(fontSize: 14, color: AppColors.grey600),
              ),
              const SizedBox(height: 24),

              // ── Section 1: Providers & Keys ──
              _buildAISectionHeader('Providers & API Keys', Icons.vpn_key_outlined),
              const SizedBox(height: 12),
              ...providers.map((p) => _buildProviderCard(p, keys)),
              const SizedBox(height: 32),

              // ── Section 2: Task Assignments ──
              _buildAISectionHeader('Task Assignments', Icons.assignment_outlined),
              const SizedBox(height: 8),
              Text(
                'Assign an AI provider and model to each application task.',
                style: TextStyle(fontSize: 13, color: AppColors.grey600),
              ),
              const SizedBox(height: 12),
              ...tasks.map((t) => _buildTaskCard(t, providers)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAISectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildProviderCard(AIProvider provider, List<AIProviderKey> allKeys) {
    final providerKeys = allKeys.where((k) => k.providerId == provider.id).toList();
    final hasKey = providerKeys.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _providerIcon(provider.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.displayName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(provider.baseUrl,
                          style: TextStyle(fontSize: 12, color: AppColors.grey600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasKey ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    hasKey ? '${providerKeys.length} key(s)' : 'No key',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hasKey ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            if (providerKeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...providerKeys.map((k) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.key, size: 16, color: AppColors.grey400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(k.label,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        TextButton.icon(
                          onPressed: () => _testAIKey(k.id),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('Test', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _removeAIKey(k.id, k.label),
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                          label: Text('Remove', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAddKeyDialog(provider),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add API Key'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerIcon(String providerName) {
    IconData icon;
    Color color;
    switch (providerName) {
      case 'openai':
        icon = Icons.auto_awesome;
        color = const Color(0xFF10A37F);
        break;
      case 'anthropic':
        icon = Icons.psychology;
        color = const Color(0xFFD4A574);
        break;
      case 'gemini':
        icon = Icons.diamond_outlined;
        color = const Color(0xFF4285F4);
        break;
      default:
        icon = Icons.smart_toy;
        color = AppColors.grey600;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildTaskCard(AITaskAssignment task, List<AIProvider> providers) {
    final isConfigured = task.providerId != null && task.modelName != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(
          _taskIcon(task.taskSlug),
          color: task.isActive ? AppColors.primary : AppColors.grey400,
        ),
        title: Text(task.displayName),
        subtitle: Text(
          isConfigured
              ? '${task.providerDisplayName ?? task.providerName ?? "?"} / ${task.modelName}'
              : task.description ?? 'Not configured',
          style: TextStyle(fontSize: 12, color: AppColors.grey600),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: task.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                task.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  color: task.isActive ? Colors.green.shade700 : AppColors.grey600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Configure',
              onPressed: () => _showAssignModelDialog(task, providers),
            ),
          ],
        ),
      ),
    );
  }

  IconData _taskIcon(String slug) {
    switch (slug) {
      case 'financial_chat':
        return Icons.chat_bubble_outline;
      case 'weekly_summary':
        return Icons.summarize_outlined;
      case 'expense_categorization':
        return Icons.category_outlined;
      case 'budget_analysis':
        return Icons.analytics_outlined;
      case 'voice_processing':
        return Icons.mic_outlined;
      case 'email_parsing':
        return Icons.email_outlined;
      case 'anomaly_detection':
        return Icons.warning_amber_outlined;
      case 'financial_simulator':
        return Icons.science_outlined;
      default:
        return Icons.smart_toy_outlined;
    }
  }

  // ── AI Dialogs ──

  void _showAddKeyDialog(AIProvider provider) {
    final keyController = TextEditingController();
    final labelController = TextEditingController(text: 'default');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add API Key — ${provider.displayName}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. production, dev',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyController.text.trim();
              final label = labelController.text.trim();
              if (key.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _adminService.addAIKey(
                  providerId: provider.id,
                  apiKey: key,
                  label: label.isEmpty ? 'default' : label,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API key added')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Add Key'),
          ),
        ],
      ),
    );
  }

  Future<void> _testAIKey(String keyId) async {
    try {
      final result = await _adminService.testAIKey(keyId);
      final valid = result['valid'] as bool? ?? false;
      final message = result['message'] as String? ?? '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(valid ? 'Key is valid' : 'Invalid: $message'),
            backgroundColor: valid ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

  Future<void> _removeAIKey(String keyId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API Key'),
        content: Text('Remove key "$label"? Tasks using this provider may stop working.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _adminService.removeAIKey(keyId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showAssignModelDialog(AITaskAssignment task, List<AIProvider> providers) {
    String? selectedProviderId = task.providerId;
    String? selectedModel = task.modelName;
    bool isActive = task.isActive;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedProvider = providers
              .where((p) => p.id == selectedProviderId)
              .firstOrNull;
          final modelsForProvider = selectedProvider != null
              ? (_availableModels[selectedProvider.name] ?? [])
              : <String>[];

          return AlertDialog(
            title: Text('Configure: ${task.displayName}'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (task.description != null) ...[
                    Text(task.description!,
                        style: TextStyle(fontSize: 13, color: AppColors.grey600)),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    value: selectedProviderId,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...providers.map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.displayName),
                          )),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        selectedProviderId = v;
                        selectedModel = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: modelsForProvider.contains(selectedModel) ? selectedModel : null,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...modelsForProvider.map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m),
                          )),
                    ],
                    onChanged: selectedProviderId == null
                        ? null
                        : (v) => setDialogState(() => selectedModel = v),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text('Enable this task for users'),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await _adminService.assignAIModel(
                      taskId: task.id,
                      providerId: selectedProviderId,
                      modelName: selectedModel,
                      isActive: isActive,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Task updated')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

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

  // ── Payment Gateways Tab ────────────────────────────────────────────────

  Future<void> _loadPaymentGateways() async {
    setState(() {
      _paymentGatewaysLoading = true;
      _paymentGatewaysError = null;
    });
    try {
      final gateways = await _adminService.fetchPaymentGateways();
      if (mounted) {
        setState(() {
          _paymentGatewaysList = gateways;
          _paymentGatewaysLoaded = true;
          _paymentGatewaysLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentGatewaysError = e.toString();
          _paymentGatewaysLoading = false;
        });
      }
    }
  }

  Widget _buildPaymentGatewaysTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Gateways',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Configure payment gateway credentials for subscription billing.',
                      style: TextStyle(fontSize: 14, color: AppColors.grey600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _paymentGatewaysLoading ? null : _loadPaymentGateways,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_paymentGatewaysLoading && _paymentGatewaysList.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ))
          else if (_paymentGatewaysError != null && _paymentGatewaysList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 12),
                    Text(_paymentGatewaysError!, style: const TextStyle(color: AppColors.grey600)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadPaymentGateways, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: _buildGatewayCards(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGatewayCards() {
    const gateways = [
      {'key': 'stripe', 'name': 'Stripe', 'icon': Icons.credit_card_rounded, 'color': Color(0xFF635BFF)},
      {'key': 'razorpay', 'name': 'Razorpay', 'icon': Icons.account_balance_rounded, 'color': Color(0xFF0066FF)},
      {'key': 'phonepe', 'name': 'PhonePe', 'icon': Icons.phone_android_rounded, 'color': Color(0xFF5F259F)},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: gateways.map((gw) {
        final key = gw['key'] as String;
        final name = gw['name'] as String;
        final icon = gw['icon'] as IconData;
        final color = gw['color'] as Color;

        final config = _paymentGatewaysList.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['gateway'] == key,
          orElse: () => null,
        );

        final isConfigured = config != null;
        final isActive = config?['is_active'] == true;
        final isTestMode = config?['is_test_mode'] == true;

        return SizedBox(
          width: 360,
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isActive ? color.withOpacity(0.3) : Colors.grey[300]!,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isConfigured
                                        ? (isActive ? Colors.green[50] : Colors.orange[50])
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isConfigured
                                        ? (isActive ? 'Active' : 'Inactive')
                                        : 'Not Configured',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isConfigured
                                          ? (isActive ? Colors.green[700] : Colors.orange[700])
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                if (isConfigured && isTestMode) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Test Mode',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isConfigured)
                        Switch(
                          value: isActive,
                          onChanged: (val) async {
                            try {
                              await _adminService.togglePaymentGateway(key, val);
                              await _loadPaymentGateways();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          activeColor: color,
                        ),
                    ],
                  ),
                  if (isConfigured) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _gwDetailRow('API Key', config['api_key_masked'] ?? '••••••••'),
                    _gwDetailRow('Secret', '••••••••'),
                    if (config['updated_at'] != null)
                      _gwDetailRow('Updated', _formatDate(config['updated_at'])),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showGatewayConfigDialog(key, name, color, config),
                          icon: Icon(isConfigured ? Icons.edit : Icons.add, size: 16),
                          label: Text(isConfigured ? 'Edit' : 'Configure'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: color,
                            side: BorderSide(color: color.withOpacity(0.5)),
                          ),
                        ),
                      ),
                      if (isConfigured) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await _adminService.testPaymentGateway(key);
                              if (mounted) {
                                final status = result['status'] ?? 'unknown';
                                final msg = result['message'] ?? '';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$name: $status — $msg'),
                                    backgroundColor: status == 'valid' ? Colors.green : Colors.orange,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Test failed: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Test'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 20),
                          tooltip: 'Remove',
                          onPressed: () => _confirmDeleteGateway(key, name),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _gwDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }

  void _showGatewayConfigDialog(
    String gateway,
    String displayName,
    Color color,
    Map<String, dynamic>? existing,
  ) {
    final apiKeyCtrl = TextEditingController();
    final apiSecretCtrl = TextEditingController();
    final webhookSecretCtrl = TextEditingController();
    bool isTestMode = existing?['is_test_mode'] ?? true;
    bool isActive = existing?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payment, color: color),
              const SizedBox(width: 8),
              Text('Configure $displayName'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Current key: ${existing['api_key_masked'] ?? '••••'}\nLeave fields empty to keep existing values.',
                                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextField(
                    controller: apiKeyCtrl,
                    decoration: InputDecoration(
                      labelText: gateway == 'phonepe' ? 'Merchant ID' : 'API Key',
                      hintText: existing != null ? 'Leave empty to keep current' : 'Enter API key',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: apiSecretCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: gateway == 'phonepe' ? 'Salt Key' : 'API Secret',
                      hintText: existing != null ? 'Leave empty to keep current' : 'Enter API secret',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: webhookSecretCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Webhook Secret (optional)',
                      hintText: 'For verifying webhook signatures',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.webhook, size: 18),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Test Mode'),
                    subtitle: const Text('Use sandbox/test credentials'),
                    value: isTestMode,
                    onChanged: (v) => setDialogState(() => isTestMode = v),
                    activeColor: Colors.amber,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Active'),
                    subtitle: const Text('Enable this gateway for payments'),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                    activeColor: Colors.green,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final key = apiKeyCtrl.text.trim();
                final secret = apiSecretCtrl.text.trim();

                if (existing == null && (key.isEmpty || secret.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('API Key and Secret are required for new configuration'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (key.isEmpty && secret.isEmpty && existing != null) {
                  // Only updating toggles
                  try {
                    await _adminService.togglePaymentGateway(gateway, isActive);
                    await _loadPaymentGateways();
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                  return;
                }

                // Need both key and secret for upsert
                if (key.isEmpty || secret.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Both API Key and Secret are required when changing credentials'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await _adminService.upsertPaymentGateway(
                    gateway: gateway,
                    apiKey: key,
                    apiSecret: secret,
                    webhookSecret: webhookSecretCtrl.text.trim().isNotEmpty
                        ? webhookSecretCtrl.text.trim()
                        : null,
                    isActive: isActive,
                    isTestMode: isTestMode,
                  );
                  await _loadPaymentGateways();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$displayName configuration saved'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteGateway(String gateway, String displayName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Gateway'),
        content: Text('Are you sure you want to remove $displayName configuration? '
            'This will delete the API credentials permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _adminService.deletePaymentGateway(gateway);
                await _loadPaymentGateways();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$displayName configuration removed'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
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

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(60)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.grey600),
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
