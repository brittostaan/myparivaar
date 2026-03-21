import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/admin_models.dart';
import 'auth_service.dart';

/// Thrown by [AdminService] for admin-related errors
class AdminException implements Exception {
  const AdminException(this.message);
  final String message;

  @override
  String toString() => 'AdminException: $message';
}

/// Manages platform-level admin operations via Supabase Edge Functions.
///
/// Provides access to:
/// - Audit logs
/// - Staff management
/// - Feature flags
/// - Admin statistics
///
/// Only accessible to users with role 'super_admin' or 'support_staff'.
class AdminService extends ChangeNotifier {
  AdminService({
    required String supabaseUrl,
    required String supabaseAnonKey,
    required AuthService authService,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl.replaceAll(RegExp(r'/$'), ''),
        _supabaseAnonKey = supabaseAnonKey,
        _authService = authService,
        _http = httpClient ?? http.Client();

  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final AuthService _authService;
  final http.Client _http;

  // ── In-memory state ────────────────────────────────────────────────────────
  List<AuditLog> _auditLogs = [];
  List<AdminApprovalRequest> _approvalRequests = [];
  List<AdminStaff> _staff = [];
  List<AdminUser> _users = [];
  List<AdminSubscription> _subscriptions = [];
  List<AdminPlan> _plans = [];
  AdminStats? _stats;
  bool _isLoading = false;
  String? _error;

  // ── Public read-only state ─────────────────────────────────────────────────
  List<AuditLog> get auditLogs => _auditLogs;
  List<AdminApprovalRequest> get approvalRequests => _approvalRequests;
  List<AdminStaff> get staff => _staff;
  List<AdminUser> get users => _users;
  List<AdminSubscription> get subscriptions => _subscriptions;
  List<AdminPlan> get plans => _plans;
  AdminStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Public methods ─────────────────────────────────────────────────────────

  /// Fetch recent audit logs for a specific resource or all resources
  /// [resourceType] — optional filter: 'household', 'user', 'subscription', etc.
  /// [resourceId] — optional filter: specific resource UUID
  /// [limit] — max results (default 50)
  Future<List<AuditLog>> fetchAuditLogs({
    String? resourceType,
    String? resourceId,
    int limit = 50,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-audit-log', {
        if (resourceType != null) 'resource_type': resourceType,
        if (resourceId != null) 'resource_id': resourceId,
        'limit': limit,
      });

      final list = data['audit_logs'] as List? ?? [];
      _auditLogs = list
          .map((e) => AuditLog.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _auditLogs;
    } catch (e) {
      _setError('Failed to fetch audit logs: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch admin statistics (household count, users, subscriptions, AI usage)
  Future<AdminStats?> fetchStats() async {
    _setLoading(true);
    _setError(null);

    try {
      debugPrint('🔄 Fetching admin stats...');
      final data = await _post('admin-stats', {});
      _stats = AdminStats.fromJson(data);
      debugPrint('✅ Admin stats loaded: $_stats');
      notifyListeners();
      return _stats;
    } catch (e) {
      debugPrint('❌ fetchStats error: $e');
      _setError('Failed to fetch admin stats: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch all current staff members (super_admin + support_staff).
  Future<List<AdminStaff>> fetchStaff() async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-staff-manage', {'action': 'list'});
      final rows = data['staff'] as List? ?? [];
      _staff = rows
          .map((e) => AdminStaff.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return _staff;
    } catch (e) {
      _setError('Failed to fetch staff: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch platform users for admin Users Management tab.
  Future<List<AdminUser>> fetchUsers({
    String? query,
    String? role,
    int limit = 100,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-users', {
        'action': 'list',
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
        'limit': limit,
      });

      final rows = data['users'] as List? ?? [];
      _users = rows
          .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return _users;
    } catch (e) {
      _setError('Failed to fetch users: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Toggle a user's active status (enable/disable).
  Future<void> toggleUserActive({
    required String userId,
    required bool isActive,
  }) async {
    await _post('admin-users', {
      'action': 'toggle_active',
      'user_id': userId,
      'is_active': isActive,
    });
  }

  /// Fetch detailed user profile for admin management.
  Future<AdminUser> fetchUserDetail(String userId) async {
    final data = await _post('admin-users', {
      'action': 'get_user',
      'user_id': userId,
    });
    return AdminUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Update a user's profile fields from admin panel.
  Future<AdminUser> updateUser({
    required String userId,
    String? firstName,
    String? lastName,
    String? displayName,
    String? phone,
    String? dateOfBirth,
    String? photoUrl,
    bool? notificationsEnabled,
    bool? voiceEnabled,
  }) async {
    final data = await _post('admin-users', {
      'action': 'update_user',
      'user_id': userId,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (displayName != null) 'display_name': displayName,
      if (phone != null) 'phone': phone,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (notificationsEnabled != null) 'notifications_enabled': notificationsEnabled,
      if (voiceEnabled != null) 'voice_enabled': voiceEnabled,
    });
    return AdminUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Fetch all platform subscriptions.
  Future<List<AdminSubscription>> fetchSubscriptions({
    String? status,
    int limit = 100,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-subscriptions', {
        'action': 'list_subscriptions',
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        'limit': limit,
      });
      final rows = data['subscriptions'] as List? ?? [];
      _subscriptions = rows
          .map((e) => AdminSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return _subscriptions;
    } catch (e) {
      _setError('Failed to fetch subscriptions: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Change the plan for a household.
  Future<AdminSubscription> changePlan({
    required String householdId,
    required String planName,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-subscriptions', {
        'action': 'change_plan',
        'household_id': householdId,
        'plan_name': planName,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      final sub = AdminSubscription.fromJson(
        data['subscription'] as Map<String, dynamic>,
      );
      _subscriptions = _subscriptions
          .map((s) => s.householdId == householdId ? sub : s)
          .toList();
      notifyListeners();
      return sub;
    } catch (e) {
      _setError('Failed to change plan: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Cancel an existing subscription.
  Future<void> cancelSubscription({
    required String subscriptionId,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      await _post('admin-subscriptions', {
        'action': 'cancel_subscription',
        'subscription_id': subscriptionId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      _subscriptions = _subscriptions.map((s) {
        if (s.id == subscriptionId) {
          return AdminSubscription.fromJson({
            'id': s.id,
            'household_id': s.householdId,
            'household_name': s.householdName,
            'plan_id': s.planId,
            'plan_name': s.planName,
            'plan_display_name': s.planDisplayName,
            'status': 'cancelled',
            'billing_cycle': s.billingCycle,
            'amount_paid': s.amountPaid,
            'currency': s.currency,
            'started_at': s.startedAt.toIso8601String(),
            'created_at': s.createdAt.toIso8601String(),
          });
        }
        return s;
      }).toList();
      notifyListeners();
    } catch (e) {
      _setError('Failed to cancel subscription: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch all plan definitions.
  Future<List<AdminPlan>> fetchPlans() async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-subscriptions', {'action': 'list_plans'});
      final rows = data['plans'] as List? ?? [];
      _plans = rows
          .map((e) => AdminPlan.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return _plans;
    } catch (e) {
      _setError('Failed to fetch plans: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Update limits on an existing plan (super admin only).
  Future<AdminPlan> updatePlan({
    required String planId,
    String? displayName,
    String? description,
    double? priceMonthly,
    double? priceYearly,
    int? maxFamilyMembers,
    int? aiWeeklySummaries,
    int? aiChatQueries,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-subscriptions', {
        'action': 'update_plan',
        'plan_id': planId,
        if (displayName != null) 'display_name': displayName.trim(),
        if (description != null) 'description': description.trim(),
        if (priceMonthly != null) 'price_monthly': priceMonthly,
        if (priceYearly != null) 'price_yearly': priceYearly,
        if (maxFamilyMembers != null) 'max_family_members': maxFamilyMembers,
        if (aiWeeklySummaries != null) 'ai_weekly_summaries': aiWeeklySummaries,
        if (aiChatQueries != null) 'ai_chat_queries': aiChatQueries,
      });
      final updated = AdminPlan.fromJson(data['plan'] as Map<String, dynamic>);
      _plans = _plans.map((p) => p.id == planId ? updated : p).toList();
      notifyListeners();
      return updated;
    } catch (e) {
      _setError('Failed to update plan: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Add a new admin staff member [email] with optional [initialScope]
  /// [initialScope] — 'global' (platform-wide) or household UUID (scoped)
  Future<AdminStaff> addStaff({
    required String email,
    required String initialScope,
    String staffRole = 'support_staff',
    String? approvalRequestId,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-staff-manage', {
        'action': 'add',
        'email': email.trim(),
        'initial_scope': initialScope,
        'staff_role': staffRole,
        if (approvalRequestId != null && approvalRequestId.trim().isNotEmpty)
          'approval_request_id': approvalRequestId.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

      final staff = AdminStaff.fromJson(data['staff'] as Map<String, dynamic>);
      return staff;
    } catch (e) {
      _setError('Failed to add staff: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Remove an admin staff member [staffUserId]
  Future<void> removeStaff(
    String staffUserId, {
    String? approvalRequestId,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      await _post('admin-staff-manage', {
        'action': 'remove',
        'staff_user_id': staffUserId,
        if (approvalRequestId != null && approvalRequestId.trim().isNotEmpty)
          'approval_request_id': approvalRequestId.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
    } catch (e) {
      _setError('Failed to remove staff: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Update staff member [staffUserId] with new [staffScope]
  /// [staffScope] — 'global' or household UUID
  Future<AdminStaff> updateStaffScope({
    required String staffUserId,
    required String staffScope,
    String? approvalRequestId,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-staff-manage', {
        'action': 'update_scope',
        'staff_user_id': staffUserId,
        'new_scope': staffScope,
        if (approvalRequestId != null && approvalRequestId.trim().isNotEmpty)
          'approval_request_id': approvalRequestId.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

      final staff = AdminStaff.fromJson(data['staff'] as Map<String, dynamic>);
      return staff;
    } catch (e) {
      _setError('Failed to update staff scope: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Check if current user is an admin (super_admin or support_staff)
  bool get isCurrentUserAdmin {
    final user = _authService.currentUser;
    return user?.isPlatformAdmin == true;
  }

  /// Fetch households for admin management list.
  Future<List<AdminHouseholdSummary>> fetchHouseholds({
    String? query,
    bool? suspendedOnly,
    int limit = 100,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-households', {
        'action': 'list',
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (suspendedOnly != null) 'suspended_only': suspendedOnly,
        'limit': limit,
      });

      final rows = data['households'] as List? ?? [];
      return rows
          .map((row) => AdminHouseholdSummary.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _setError('Failed to fetch households: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<AdminHouseholdDetail> fetchHouseholdDetail(String householdId) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-households', {
        'action': 'detail',
        'household_id': householdId,
      });

      return AdminHouseholdDetail.fromJson(data['household'] as Map<String, dynamic>);
    } catch (e) {
      _setError('Failed to fetch household details: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<AdminHouseholdDetail> suspendHousehold({
    required String householdId,
    required String reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-households', {
        'action': 'suspend',
        'household_id': householdId,
        'reason': reason.trim(),
      });

      return AdminHouseholdDetail.fromJson(data['household'] as Map<String, dynamic>);
    } catch (e) {
      _setError('Failed to suspend household: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<AdminHouseholdDetail> reactivateHousehold({
    required String householdId,
    required String reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-households', {
        'action': 'reactivate',
        'household_id': householdId,
        'reason': reason.trim(),
      });

      return AdminHouseholdDetail.fromJson(data['household'] as Map<String, dynamic>);
    } catch (e) {
      _setError('Failed to reactivate household: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<AdminHouseholdDetail> updateHouseholdNotes({
    required String householdId,
    required String notes,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-households', {
        'action': 'update_notes',
        'household_id': householdId,
        'admin_notes': notes.trim(),
      });

      return AdminHouseholdDetail.fromJson(data['household'] as Map<String, dynamic>);
    } catch (e) {
      _setError('Failed to update household notes: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ── Household-scoped queries for detail panel ──────────────────────────────

  /// Fetch users belonging to a specific household.
  Future<List<AdminUser>> fetchHouseholdUsers(String householdId) async {
    try {
      final data = await _post('admin-users', {
        'action': 'list',
        'household_id': householdId,
        'limit': 50,
      });
      final rows = data['users'] as List? ?? [];
      return rows
          .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch subscriptions for a specific household.
  Future<List<AdminSubscription>> fetchHouseholdSubscriptions(
      String householdId) async {
    try {
      final data = await _post('admin-subscriptions', {
        'action': 'list_subscriptions',
        'household_id': householdId,
      });
      final rows = data['subscriptions'] as List? ?? [];
      return rows
          .map((e) => AdminSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch feature flags with overrides for a specific household.
  Future<List<AdminFeatureFlag>> fetchHouseholdFeatureFlags(
      String householdId) async {
    try {
      final data = await _post('admin-feature-flags', {
        'action': 'list_flags',
        'householdId': householdId,
      });
      final flagList = data['flags'] as List? ?? [];
      return flagList
          .map((e) => AdminFeatureFlag.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch audit logs scoped to a specific household.
  Future<List<AuditLog>> fetchHouseholdAuditLogs(String householdId,
      {int limit = 50}) async {
    try {
      final data = await _post('admin-audit-log', {
        'household_id': householdId,
        'limit': limit,
      });
      final list = data['audit_logs'] as List? ?? [];
      return list
          .map((e) => AuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch approval requests for dual-approval decision workflows.
  Future<List<AdminApprovalRequest>> fetchApprovalRequests({
    String? status,
    String? actionType,
    int limit = 100,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-approval-manage', {
        'action': 'list',
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (actionType != null && actionType.trim().isNotEmpty) 'action_type': actionType.trim(),
        'limit': limit,
      });

      final rows = data['approval_requests'] as List? ?? [];
      _approvalRequests = rows
          .map((row) => AdminApprovalRequest.fromJson(row as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _approvalRequests;
    } catch (e) {
      _setError('Failed to fetch approval requests: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Approve an existing dual-approval request.
  Future<AdminApprovalRequest> approveApprovalRequest({
    required String approvalRequestId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-approval-manage', {
        'action': 'approve',
        'approval_request_id': approvalRequestId.trim(),
      });

      final approval = AdminApprovalRequest.fromJson(
        data['approval_request'] as Map<String, dynamic>,
      );

      _approvalRequests = _approvalRequests
          .map((existing) => existing.id == approval.id ? approval : existing)
          .toList();
      notifyListeners();
      return approval;
    } catch (e) {
      _setError('Failed to approve request: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Reject an existing dual-approval request.
  Future<AdminApprovalRequest> rejectApprovalRequest({
    required String approvalRequestId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-approval-manage', {
        'action': 'reject',
        'approval_request_id': approvalRequestId.trim(),
      });

      final approval = AdminApprovalRequest.fromJson(
        data['approval_request'] as Map<String, dynamic>,
      );

      _approvalRequests = _approvalRequests
          .map((existing) => existing.id == approval.id ? approval : existing)
          .toList();
      notifyListeners();
      return approval;
    } catch (e) {
      _setError('Failed to reject request: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Get admin scope of current user ('global' or household_id)
  String get currentAdminScope {
    final user = _authService.currentUser;
    if (user?.staffScope != null) {
      return user!.staffScope!;
    }
    if (user?.isSuperAdmin == true) {
      return 'global';
    }
    return 'none';
  }

  // ── Phase 4: Feature Flags ─────────────────────────────────────────────────

  List<AdminFeatureFlag> _featureFlags = [];

  List<AdminFeatureFlag> get featureFlags => _featureFlags;

  /// Fetch all feature flags, optionally with household overrides for context.
  Future<List<AdminFeatureFlag>> fetchFeatureFlags({
    String? householdId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-feature-flags', {
        'action': 'list_flags',
        if (householdId != null) 'householdId': householdId,
      });

      final flagList = data['flags'] as List? ?? [];
      _featureFlags = flagList
          .map((e) => AdminFeatureFlag.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _featureFlags;
    } catch (e) {
      _setError('Failed to fetch feature flags: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Toggle global flag state (super-admin only).
  Future<AdminFeatureFlag> toggleFlag({
    required String flagId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-feature-flags', {
        'action': 'toggle_flag',
        'flagId': flagId,
      });

      final flag = AdminFeatureFlag.fromJson(
        data['flag'] as Map<String, dynamic>,
      );

      final index = _featureFlags.indexWhere((f) => f.id == flagId);
      if (index >= 0) {
        _featureFlags[index] = flag;
      }

      notifyListeners();
      return flag;
    } catch (e) {
      _setError('Failed to toggle flag: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Set a per-household feature flag override (super-admin only).
  Future<AdminFeatureFlagOverride> setHouseholdOverride({
    required String householdId,
    required String flagId,
    required bool isEnabled,
    String? reason,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-feature-flags', {
        'action': 'set_household_override',
        'householdId': householdId,
        'flagId': flagId,
        'isEnabled': isEnabled,
        if (reason != null) 'reason': reason,
      });

      final override = AdminFeatureFlagOverride.fromJson(
        data['override'] as Map<String, dynamic>,
      );

      // Update the flag's household_override in local state
      final flagIndex = _featureFlags.indexWhere((f) => f.id == flagId);
      if (flagIndex >= 0) {
        // Reconstruct the flag with updated override
        final existingFlag = _featureFlags[flagIndex];
        _featureFlags[flagIndex] = AdminFeatureFlag(
          id: existingFlag.id,
          name: existingFlag.name,
          displayName: existingFlag.displayName,
          description: existingFlag.description,
          isEnabled: existingFlag.isEnabled,
          category: existingFlag.category,
          isBeta: existingFlag.isBeta,
          createdAt: existingFlag.createdAt,
          updatedAt: existingFlag.updatedAt,
          householdOverride: override,
        );
      }

      notifyListeners();
      return override;
    } catch (e) {
      _setError('Failed to set household override: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Remove a per-household feature flag override (super-admin only).
  Future<void> removeHouseholdOverride({
    required String overrideId,
    required String flagId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      await _post('admin-feature-flags', {
        'action': 'remove_household_override',
        'overrideId': overrideId,
      });

      // Clear the override from local state
      final flagIndex = _featureFlags.indexWhere((f) => f.id == flagId);
      if (flagIndex >= 0) {
        final existingFlag = _featureFlags[flagIndex];
        _featureFlags[flagIndex] = AdminFeatureFlag(
          id: existingFlag.id,
          name: existingFlag.name,
          displayName: existingFlag.displayName,
          description: existingFlag.description,
          isEnabled: existingFlag.isEnabled,
          category: existingFlag.category,
          isBeta: existingFlag.isBeta,
          createdAt: existingFlag.createdAt,
          updatedAt: existingFlag.updatedAt,
          householdOverride: null,
        );
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to remove household override: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ── Phase 5: Analytics & Reports ───────────────────────────────────────────

  AdminAnalyticsOverview? _analyticsOverview;
  List<SubscriptionTrend> _subscriptionTrends = [];
  List<HouseholdTrend> _householdTrends = [];
  List<AdminActivitySummary> _adminActivity = [];
  List<AIUsageTrend> _aiUsageTrends = [];

  AdminAnalyticsOverview? get analyticsOverview => _analyticsOverview;
  List<SubscriptionTrend> get subscriptionTrends => _subscriptionTrends;
  List<HouseholdTrend> get householdTrends => _householdTrends;
  List<AdminActivitySummary> get adminActivity => _adminActivity;
  List<AIUsageTrend> get aiUsageTrends => _aiUsageTrends;

  /// Fetch analytics overview for specified month (default: current month).
  Future<AdminAnalyticsOverview?> fetchAnalyticsOverview({
    String? month,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-analytics', {
        'action': 'get_overview',
        if (month != null) 'month': month,
      });

      _analyticsOverview = AdminAnalyticsOverview.fromJson(
        data['overview'] as Map<String, dynamic>,
      );

      notifyListeners();
      return _analyticsOverview;
    } catch (e) {
      _setError('Failed to fetch analytics overview: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch subscription trends over last N months.
  Future<List<SubscriptionTrend>> fetchSubscriptionTrends({
    int monthsBack = 12,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-analytics', {
        'action': 'get_subscription_trends',
        'monthsBack': monthsBack,
      });

      final trendsList = data['trends'] as List? ?? [];
      _subscriptionTrends = trendsList
          .map((e) => SubscriptionTrend.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _subscriptionTrends;
    } catch (e) {
      _setError('Failed to fetch subscription trends: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch household trends over last N months.
  Future<List<HouseholdTrend>> fetchHouseholdTrends({
    int monthsBack = 12,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-analytics', {
        'action': 'get_household_trends',
        'monthsBack': monthsBack,
      });

      final trendsList = data['trends'] as List? ?? [];
      _householdTrends = trendsList
          .map((e) => HouseholdTrend.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _householdTrends;
    } catch (e) {
      _setError('Failed to fetch household trends: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch admin activity summary for last N days.
  Future<List<AdminActivitySummary>> fetchAdminActivity({
    int daysBack = 30,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-analytics', {
        'action': 'get_admin_activity',
        'daysBack': daysBack,
      });

      final activityList = data['activity'] as List? ?? [];
      _adminActivity = activityList
          .map((e) => AdminActivitySummary.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _adminActivity;
    } catch (e) {
      _setError('Failed to fetch admin activity: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetch AI usage trends over last N months.
  Future<List<AIUsageTrend>> fetchAIUsageTrends({
    int monthsBack = 12,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-analytics', {
        'action': 'get_ai_usage_trends',
        'monthsBack': monthsBack,
      });

      final trendsList = data['trends'] as List? ?? [];
      _aiUsageTrends = trendsList
          .map((e) => AIUsageTrend.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
      return _aiUsageTrends;
    } catch (e) {
      _setError('Failed to fetch AI usage trends: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ── Phase 6: AI Administration ─────────────────────────────────────────────

  List<AIProvider> _aiProviders = [];
  List<AIProviderKey> _aiProviderKeys = [];
  List<AITaskAssignment> _aiTaskAssignments = [];

  List<AIProvider> get aiProviders => _aiProviders;
  List<AIProviderKey> get aiProviderKeys => _aiProviderKeys;
  List<AITaskAssignment> get aiTaskAssignments => _aiTaskAssignments;

  Future<List<AIProvider>> fetchAIProviders() async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-ai-config', {'action': 'list_providers'});
      final list = data['providers'] as List? ?? [];
      _aiProviders = list.map((e) => AIProvider.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
      return _aiProviders;
    } catch (e) {
      _setError('Failed to fetch AI providers: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<AIProviderKey>> fetchAIKeys() async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-ai-config', {'action': 'list_keys'});
      final list = data['keys'] as List? ?? [];
      _aiProviderKeys = list.map((e) => AIProviderKey.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
      return _aiProviderKeys;
    } catch (e) {
      _setError('Failed to fetch AI keys: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addAIKey({
    required String providerId,
    required String apiKey,
    String label = 'default',
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      await _post('admin-ai-config', {
        'action': 'add_key',
        'provider_id': providerId,
        'api_key': apiKey,
        'label': label,
      });
      await fetchAIKeys();
    } catch (e) {
      _setError('Failed to add AI key: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removeAIKey(String keyId) async {
    _setLoading(true);
    _setError(null);
    try {
      await _post('admin-ai-config', {'action': 'remove_key', 'key_id': keyId});
      await fetchAIKeys();
    } catch (e) {
      _setError('Failed to remove AI key: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> testAIKey(String keyId) async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-ai-config', {'action': 'test_key', 'key_id': keyId});
      return data;
    } catch (e) {
      _setError('Failed to test AI key: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<AITaskAssignment>> fetchAITasks() async {
    _setLoading(true);
    _setError(null);
    try {
      final data = await _post('admin-ai-config', {'action': 'list_tasks'});
      final list = data['tasks'] as List? ?? [];
      _aiTaskAssignments = list.map((e) => AITaskAssignment.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
      return _aiTaskAssignments;
    } catch (e) {
      _setError('Failed to fetch AI tasks: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> assignAIModel({
    required String taskId,
    String? providerId,
    String? modelName,
    bool? isActive,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      await _post('admin-ai-config', {
        'action': 'assign_model',
        'task_id': taskId,
        if (providerId != null) 'provider_id': providerId,
        if (modelName != null) 'model_name': modelName,
        if (isActive != null) 'is_active': isActive,
      });
      await fetchAITasks();
    } catch (e) {
      _setError('Failed to assign AI model: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, List<String>>> fetchAvailableModels() async {
    try {
      final data = await _post('admin-ai-config', {'action': 'list_models'});
      final models = data['models'] as Map<String, dynamic>? ?? {};
      return models.map((key, value) =>
          MapEntry(key, (value as List).cast<String>()));
    } catch (e) {
      _setError('Failed to fetch available models: $e');
      rethrow;
    }
  }

  // ── Internal methods ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String function,
    Map<String, dynamic> body,
  ) async {
    if (!_authService.isLoggedIn) {
      throw const AdminException('Not authenticated.');
    }

    if (!isCurrentUserAdmin) {
      throw const AdminException('Admin access required.');
    }

    final idToken = await _authService.getIdToken(true);

    final url = '$_supabaseUrl/functions/v1/$function';
    debugPrint('📤 AdminService POST to: $url');
    debugPrint('📤 Request body: $body');

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse(url),
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint('❌ Network error: $e');
      throw const AdminException('Network error: unable to reach the server.');
    }

    debugPrint('📥 Response status: ${response.statusCode}');
    debugPrint('📥 Response body: ${response.body}');

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ JSON decode error: $e');
      throw const AdminException('Unexpected response from server.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('✅ Success: $data');
      return data;
    }

    if (response.statusCode == 403) {
      debugPrint('❌ Forbidden: Admin access denied');
      throw const AdminException('Admin access denied. Insufficient permissions.');
    }

    final errorMsg = data['error'] as String? ?? 'Request failed (${response.statusCode}).';
    debugPrint('❌ Error: $errorMsg');
    throw AdminException(errorMsg);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }
}
