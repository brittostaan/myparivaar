import 'package:flutter/material.dart';
import '../constants/app_dimensions.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_icons.dart';

/// A gradient card widget displaying the total family balance with action buttons
class BalanceCard extends StatelessWidget {
  final double balance;
  final double percentageChange;
  final VoidCallback? onDeposit;
  final VoidCallback? onViewDetails;

  const BalanceCard({
    super.key,
    required this.balance,
    this.percentageChange = 0.0,
    this.onDeposit,
    this.onViewDetails,
  });

  String _formatCurrency(double amount) {
    return '₹${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = percentageChange >= 0;
    
    return Container(
      margin: AppDimensions.paddingHorizontalMedium.add(
        const EdgeInsets.symmetric(vertical: 8),
      ),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppDimensions.borderRadiusXl,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background decorative circles
          Positioned(
            right: -16,
            bottom: -16,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: AppColors.textPrimaryDark.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -16,
            top: -16,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.textPrimaryDark.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Content
          Padding(
            padding: AppDimensions.paddingAllLarge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Balance',
                      style: AppTextStyles.cardSubtitle(AppColors.textPrimaryDark.withOpacity(0.9)),
                    ),
                    Icon(
                      AppIcons.wallet,
                      color: AppColors.textPrimaryDark.withOpacity(0.8),
                      size: 24,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spacingSmall),
                Text(
                  _formatCurrency(balance),
                  style: AppTextStyles.balanceAmount(AppColors.textPrimaryDark),
                ),
                const SizedBox(height: AppDimensions.spacingXs),
                Row(
                  children: [
                    Icon(
                      isPositive ? AppIcons.trendingUp : AppIcons.trendingDown,
                      color: AppColors.textPrimaryDark.withOpacity(0.8),
                      size: 16,
                    ),
                    const SizedBox(width: AppDimensions.spacingXs),
                    Text(
                      '${isPositive ? '+' : ''}${percentageChange.toStringAsFixed(1)}% from last month',
                      style: TextStyle(
                        color: AppColors.textPrimaryDark.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }
}
