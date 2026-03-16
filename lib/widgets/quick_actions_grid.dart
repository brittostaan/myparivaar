import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Quick action button data model
class QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const QuickAction({
    required this.label,
    required this.icon,
    this.onTap,
  });
}

/// A grid of quick action buttons for common tasks
class QuickActionsGrid extends StatelessWidget {
  final List<QuickAction> actions;

  const QuickActionsGrid({
    super.key,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: actions.length.clamp(1, 4),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return _QuickActionButton(
                label: action.label,
                icon: action.icon,
                onTap: action.onTap,
                isDark: isDark,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    required this.isDark,
  });

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    
    return InkWell(
      onTap: widget.onTap,
      onHover: (hovering) {
        setState(() {
          _isHovered = hovering;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _isHovered
                  ? primaryColor.withOpacity(0.1)
                  : (widget.isDark ? AppColors.grey800 : AppColors.surfaceLight),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHovered
                    ? primaryColor
                    : (widget.isDark ? AppColors.grey700 : AppColors.grey200),
                width: _isHovered ? 2 : 1,
              ),
              boxShadow: [
                if (!widget.isDark)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Icon(
              widget.icon,
              color: primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.isDark ? AppColors.grey400 : AppColors.grey600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
