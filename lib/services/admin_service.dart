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
