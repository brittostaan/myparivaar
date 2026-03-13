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
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.more_horiz,
                        size: 64,
                        color: Theme.of(context).primaryColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'More Options',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Content coming soon...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
