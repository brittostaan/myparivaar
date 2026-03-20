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
    int toInt(dynamic value) => value == null ? 0 : (value as num).toInt();

    return AdminStats(
      totalHouseholds: toInt(json['total_households']),
      activeSubscriptions: toInt(json['active_subscriptions']),
      totalUsers: toInt(json['total_users']),
      aiUsageThisMonth: toInt(json['ai_usage_this_month']),
      lastAuditAction: json['last_audit_action'] != null
          ? DateTime.tryParse(json['last_audit_action'].toString())
          : null,
    );
  }
}

/// Lightweight household entry for list/search views in Admin Center
class AdminHouseholdSummary {
  const AdminHouseholdSummary({
    required this.id,
    required this.name,
    required this.plan,
    required this.suspended,
    required this.memberCount,
    required this.activeMemberCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String plan;
  final bool suspended;
  final int memberCount;
  final int activeMemberCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdminHouseholdSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) => value == null ? 0 : (value as num).toInt();

    return AdminHouseholdSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed household',
      plan: json['plan'] as String? ?? 'free',
      suspended: json['suspended'] as bool? ?? false,
      memberCount: toInt(json['member_count']),
      activeMemberCount: toInt(json['active_member_count']),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class AdminHouseholdMember {
  const AdminHouseholdMember({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String? displayName;
  final String? email;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  factory AdminHouseholdMember.fromJson(Map<String, dynamic> json) {
    return AdminHouseholdMember(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String? ?? 'member',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Household detail payload for admin actions and right-side detail panel
class AdminHouseholdDetail {
  const AdminHouseholdDetail({
    required this.id,
    required this.name,
    required this.plan,
    required this.suspended,
    this.suspensionReason,
    this.adminNotes,
    required this.memberCount,
    required this.activeMemberCount,
    required this.createdAt,
    required this.updatedAt,
    required this.members,
  });

  final String id;
  final String name;
  final String plan;
  final bool suspended;
  final String? suspensionReason;
  final String? adminNotes;
  final int memberCount;
  final int activeMemberCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AdminHouseholdMember> members;

  factory AdminHouseholdDetail.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) => value == null ? 0 : (value as num).toInt();

    final memberRows = json['members'] as List? ?? [];
    return AdminHouseholdDetail(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed household',
      plan: json['plan'] as String? ?? 'free',
      suspended: json['suspended'] as bool? ?? false,
      suspensionReason: json['suspension_reason'] as String?,
      adminNotes: json['admin_notes'] as String?,
      memberCount: toInt(json['member_count']),
      activeMemberCount: toInt(json['active_member_count']),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      members: memberRows
          .map((member) => AdminHouseholdMember.fromJson(member as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Admin approval request for two-person control workflows.
class AdminApprovalRequest {
  const AdminApprovalRequest({
    required this.id,
    required this.actionType,
    required this.resourceType,
    this.resourceId,
    required this.requestPayload,
    this.reason,
    required this.status,
    required this.requestedByUserId,
    required this.requestedByEmail,
    this.approvedByUserId,
    this.approvedByEmail,
    required this.requestedAt,
    this.decidedAt,
    this.expiresAt,
  });

  final String id;
  final String actionType;
  final String resourceType;
  final String? resourceId;
  final Map<String, dynamic> requestPayload;
  final String? reason;
  final String status; // pending | approved | rejected | expired
  final String requestedByUserId;
  final String requestedByEmail;
  final String? approvedByUserId;
  final String? approvedByEmail;
  final DateTime requestedAt;
  final DateTime? decidedAt;
  final DateTime? expiresAt;

  factory AdminApprovalRequest.fromJson(Map<String, dynamic> json) {
    return AdminApprovalRequest(
      id: json['id'] as String? ?? '',
      actionType: json['action_type'] as String? ?? 'unknown',
      resourceType: json['resource_type'] as String? ?? 'unknown',
      resourceId: json['resource_id'] as String?,
      requestPayload: json['request_payload'] as Map<String, dynamic>? ?? {},
      reason: json['reason'] as String?,
      status: json['status'] as String? ?? 'pending',
      requestedByUserId: json['requested_by_user_id'] as String? ?? '',
      requestedByEmail: json['requested_by_email'] as String? ?? 'Unknown',
      approvedByUserId: json['approved_by_user_id'] as String?,
      approvedByEmail: json['approved_by_email'] as String?,
      requestedAt: DateTime.tryParse(json['requested_at'] as String? ?? '') ?? DateTime.now(),
      decidedAt: json['decided_at'] != null
          ? DateTime.tryParse(json['decided_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired' || (expiresAt?.isBefore(DateTime.now()) ?? false);
}

/// Platform user entry for the admin Users Management tab.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.staffRole,
    this.staffScope,
    required this.isActive,
    this.householdId,
    this.householdName,
    required this.createdAt,
  });

  final String id;
  final String? email;
  final String? displayName;
  final String role;
  final String? staffRole;
  final String? staffScope;
  final bool isActive;
  final String? householdId;
  final String? householdName;
  final DateTime createdAt;

  bool get isPlatformAdmin => role == 'super_admin' || staffRole != null;

  String get displayRoleName {
    if (role == 'super_admin') return 'Super Admin';
    if (staffRole == 'support_staff') return 'Support Staff';
    if (role == 'admin') return 'Admin';
    return 'Member';
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      role: json['role'] as String? ?? 'member',
      staffRole: json['staff_role'] as String?,
      staffScope: json['staff_scope'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      householdId: json['household_id'] as String?,
      householdName: json['household_name'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
