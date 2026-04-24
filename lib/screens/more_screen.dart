import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/app_header.dart';

/// More screen with quick access to additional features
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'More',
              avatarIcon: Icons.more_horiz,
              showViewModeSelector: false,
              showSettingsButton: false,
              showNotifications: false,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  spacing: 12,
                  children: [
                    _FeatureCard(
                      icon: AppIcons.smartToy,
                      title: 'AI Insights',
                      description: 'Get AI-powered financial insights and ideas',
                      onTap: () {
                        Navigator.of(context).pushNamed('/featureboard');
                      },
                      isDark: isDark,
                    ),
                    _FeatureCard(
                      icon: AppIcons.mic,
                      title: 'Voice Expense',
                      description: 'Record expenses by speaking',
                      onTap: () {
                        Navigator.of(context).pushNamed('/voice-expense');
                      },
                      isDark: isDark,
                    ),
                    _FeatureCard(
                      icon: AppIcons.upload,
                      title: 'Import CSV',
                      description: 'Bulk import expenses or budgets from CSV',
                      onTap: () {
                        Navigator.of(context).pushNamed('/csv-import');
                      },
                      isDark: isDark,
                    ),
                    _FeatureCard(
                      icon: AppIcons.settings,
                      title: 'Settings',
                      description: 'Manage your preferences and account',
                      onTap: () {
                        Navigator.of(context).pushNamed('/user-settings');
                      },
                      isDark: isDark,
                    ),
                    _FeatureCard(
                      icon: AppIcons.notifications,
                      title: 'Notifications',
                      description: 'View and manage your notifications',
                      onTap: () {
                        Navigator.of(context).pushNamed('/notifications');
                      },
                      isDark: isDark,
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
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool isDark;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: isDark ? 2 : 1,
      color: isDark
          ? colorScheme.surface
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppColors.grey700 : AppColors.grey200,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.grey400 : AppColors.grey600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDark ? AppColors.grey600 : AppColors.grey400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

