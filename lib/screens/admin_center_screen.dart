import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
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

  @override
  void initState() {
    super.initState();
    _adminService = context.read<AdminService>();
    _loadStats();
  }

  void _loadStats() {
    _adminService.fetchStats();
  }

  Future<void> _selectTab(int index) async {
    setState(() {
      _selectedTabIndex = index;
    });

    if (index == 7 && _adminService.auditLogs.isEmpty && !_adminService.isLoading) {
      await _adminService.fetchAuditLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final adminService = context.watch<AdminService>();

    // Permission check
    final isAdmin = user?.isPlatformAdmin == true;

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
                            _NavItem(
                              label: 'Households',
                              icon: Icons.home_work_outlined,
                              isSelected: _selectedTabIndex == 1,
                              onTap: () => _selectTab(1),
                            ),
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
                            _NavItem(
                              label: 'Features',
                              icon: Icons.toggle_on_outlined,
                              isSelected: _selectedTabIndex == 5,
                              onTap: () => _selectTab(5),
                            ),
                            _NavItem(
                              label: 'Analytics',
                              icon: Icons.analytics_outlined,
                              isSelected: _selectedTabIndex == 6,
                              onTap: () => _selectTab(6),
                            ),
                            _NavItem(
                              label: 'Audit Logs',
                              icon: Icons.history_outlined,
                              isSelected: _selectedTabIndex == 7,
                              onTap: () => _selectTab(7),
                            ),
                            if (user?.isSuperAdmin == true) ...[
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              _NavItem(
                                label: 'Staff',
                                icon: Icons.admin_panel_settings_outlined,
                                isSelected: _selectedTabIndex == 8,
                                onTap: () => _selectTab(8),
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
                      child: _buildContent(adminService),
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

  Widget _buildContent(AdminService adminService) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildDashboard(adminService);
      case 1:
        return _buildPlaceholder('Households Management', 'Coming in Phase 2');
      case 2:
        return _buildPlaceholder('Users Management', 'Coming in Phase 2');
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
        return _buildPlaceholder('Staff Management', 'Coming in Phase 2 (Super Admin Only)');
      default:
        return _buildPlaceholder('Unknown', 'Unknown section');
    }
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
                separatorBuilder: (_, __) => const Divider(height: 1, margin: EdgeInsets.zero),
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
                  AppIcons.construction,
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? const Color(0xFF3B82F6) : AppColors.grey700,
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
