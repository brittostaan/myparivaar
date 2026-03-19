import 'package:flutter/material.dart';

/// Admin staff member with role and scope
class AdminStaff {
  const AdminStaff({
    required this.id,
    required this.email,
    required this.displayName,
    required this.staffRole, // 'super_admin' or 'support_staff'
    required this.staffScope, // 'global' or specific household_id
    required this.adminPermissions,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String? displayName;
  final String staffRole; // 'super_admin' | 'support_staff'
  final String staffScope; // 'global' | household UUID
  final Map<String, dynamic> adminPermissions;
  final DateTime createdAt;

  bool get isSuperAdmin => staffRole == 'super_admin';
  bool get isSupportStaff => staffRole == 'support_staff';
  bool get isGlobalScope => staffScope == 'global';

  factory AdminStaff.fromJson(Map<String, dynamic> json) {
    return AdminStaff(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String?,
      staffRole: json['staff_role'] as String? ?? 'support_staff',
      staffScope: json['staff_scope'] as String? ?? 'global',
      adminPermissions: json['admin_permissions'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Audit log entry for admin actions
class AuditLog {
  const AuditLog({
    required this.id,
    required this.adminUserId,
    required this.adminEmail,
    required this.action,
    required this.resourceType,
    this.resourceId,
    this.oldValues,
    this.newValues,
    this.description,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });

  final String id;
  final String adminUserId;
  final String adminEmail;
  final String action; // 'create', 'update', 'delete', 'suspend', 'unsuspend'
  final String resourceType; // 'household', 'user', 'subscription', 'plan'
  final String? resourceId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? description;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] as String? ?? '',
      adminUserId: json['admin_user_id'] as String? ?? '',
      adminEmail: json['admin_email'] as String? ?? 'Unknown',
      action: json['action'] as String? ?? 'unknown',
      resourceType: json['resource_type'] as String? ?? 'unknown',
      resourceId: json['resource_id'] as String?,
      oldValues: json['old_values'] as Map<String, dynamic>?,
      newValues: json['new_values'] as Map<String, dynamic>?,
      description: json['description'] as String?,
      ipAddress: json['ip_address'] as String?,
      userAgent: json['user_agent'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get actionLabel {
    switch (action) {
      case 'create':
        return 'Created';
      case 'update':
        return 'Updated';
      case 'delete':
        return 'Deleted';
      case 'suspend':
        return 'Suspended';
      case 'unsuspend':
        return 'Reactivated';
      case 'upgrade_plan':
        return 'Upgraded plan';
      case 'downgrade_plan':
        return 'Downgraded plan';
      default:
        return action;
    }
  }

  String get resourceLabel {
    switch (resourceType) {
      case 'household':
        return 'Household';
      case 'user':
        return 'User';
      case 'subscription':
        return 'Subscription';
      case 'plan':
        return 'Plan';
      case 'feature_flag':
        return 'Feature Flag';
      default:
        return resourceType;
    }
  }
}

/// Feature flag for controlling features globally or per-household
class FeatureFlag {
  const FeatureFlag({
    required this.id,
    required this.name,
    required this.displayName,
    this.description,
    required this.isEnabled,
    this.category,
    this.isBeta,
    required this.createdAt,
  });

  final String id;
  final String name; // e.g., 'email_ingestion', 'voice_features'
  final String displayName; // e.g., 'Email Ingestion'
  final String? description;
  final bool isEnabled;
  final String? category; // 'ai', 'finance', 'integration', 'general'
  final bool? isBeta;
  final DateTime createdAt;

  factory FeatureFlag.fromJson(Map<String, dynamic> json) {
    return FeatureFlag(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      description: json['description'] as String?,
      isEnabled: json['is_enabled'] as bool? ?? false,
      category: json['category'] as String?,
      isBeta: json['is_beta'] as bool?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Color get statusColor {
    return isEnabled ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  }

  String get statusLabel {
    return isEnabled ? 'Enabled' : 'Disabled';
  }
}

/// Admin statistics for dashboard
class AdminStats {
  const AdminStats({
    required this.totalHouseholds,
    required this.activeSubscriptions,
    required this.totalUsers,
    required this.aiUsageThisMonth,
    required this.lastAuditAction,
  });

  final int totalHouseholds;
  final int activeSubscriptions;
  final int totalUsers;
  final int aiUsageThisMonth;
  final DateTime? lastAuditAction;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalHouseholds: json['total_households'] as int? ?? 0,
      activeSubscriptions: json['active_subscriptions'] as int? ?? 0,
      totalUsers: json['total_users'] as int? ?? 0,
      aiUsageThisMonth: json['ai_usage_this_month'] as int? ?? 0,
      lastAuditAction: json['last_audit_action'] != null 
        ? DateTime.tryParse(json['last_audit_action'] as String)
        : null,
    );
  }
}
