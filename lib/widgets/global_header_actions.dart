import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
