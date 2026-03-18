import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show ViewMode, ViewModeProvider;
import '../services/auth_service.dart';

/// Shared top-right actions used across screens.
///
/// Includes:
/// - View mode selector
/// - Logout action (optional)
class GlobalHeaderActions extends StatelessWidget {
  final bool showLogout;
  final Color? iconColor;

  const GlobalHeaderActions({
    super.key,
    this.showLogout = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final modeProvider = context.watch<ViewModeProvider>();
    final currentMode = modeProvider.mode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<ViewMode>(
          tooltip: 'View Mode',
          icon: Icon(currentMode.icon, color: iconColor),
          onSelected: modeProvider.setMode,
          itemBuilder: (context) => ViewMode.values.map((mode) {
            final selected = mode == currentMode;
            return PopupMenuItem<ViewMode>(
              value: mode,
              child: Row(
                children: [
                  Icon(
                    mode.icon,
                    color: selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (showLogout)
          TextButton.icon(
            onPressed: () async {
              await context.read<AuthService>().signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            },
            icon: Icon(Icons.logout_rounded, size: 18, color: iconColor),
            label: Text(
              'Logout',
              style: TextStyle(color: iconColor),
            ),
            style: TextButton.styleFrom(
              foregroundColor: iconColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
      ],
    );
  }
}
