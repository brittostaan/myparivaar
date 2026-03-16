import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/navigation_shell.dart';
import '../theme/app_icons.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NavigationShell(
      currentRoute: '/more',
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(
                title: 'More',
                avatarIcon: AppIcons.expandMore,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _MoreTile(
                      icon: AppIcons.mic,
                      label: 'Voice Expense',
                      subtitle: 'Add an expense by speaking',
                      onTap: () => Navigator.of(context).pushNamed('/voice-expense'),
                    ),
                    _MoreTile(
                      icon: AppIcons.notifications,
                      label: 'Notifications',
                      subtitle: 'View your alerts and reminders',
                      onTap: () => Navigator.of(context).pushReplacementNamed('/notifications'),
                    ),
                    _MoreTile(
                      icon: AppIcons.upload,
                      label: 'Import CSV',
                      subtitle: 'Import expenses from a spreadsheet',
                      onTap: () => Navigator.of(context).pushReplacementNamed('/csv-import'),
                    ),
                    _MoreTile(
                      icon: Icons.savings_outlined,
                      label: 'Savings Goals',
                      subtitle: 'Track your savings and targets',
                      onTap: () => Navigator.of(context).pushReplacementNamed('/savings'),
                    ),
                    _MoreTile(
                      icon: Icons.query_stats,
                      label: 'Investments',
                      subtitle: 'Track portfolio and due dates',
                      onTap: () => Navigator.of(context).pushReplacementNamed('/investments'),
                    ),
                    _MoreTile(
                      icon: AppIcons.smartToy,
                      label: 'AI Features',
                      subtitle: 'Smart insights and suggestions',
                      onTap: () => Navigator.of(context).pushReplacementNamed('/ai'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
