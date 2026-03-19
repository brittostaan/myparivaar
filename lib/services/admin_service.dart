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
  AdminStats? _stats;
  bool _isLoading = false;
  String? _error;

  // ── Public read-only state ─────────────────────────────────────────────────
  List<AuditLog> get auditLogs => _auditLogs;
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

  /// Add a new admin staff member [email] with optional [initialScope]
  /// [initialScope] — 'global' (platform-wide) or household UUID (scoped)
  Future<AdminStaff> addStaff({
    required String email,
    required String initialScope,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-staff-manage', {
        'action': 'add',
        'email': email.trim(),
        'initial_scope': initialScope,
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
  Future<void> removeStaff(String staffUserId) async {
    _setLoading(true);
    _setError(null);

    try {
      await _post('admin-staff-manage', {
        'action': 'remove',
        'staff_user_id': staffUserId,
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
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final data = await _post('admin-staff-manage', {
        'action': 'update_scope',
        'staff_user_id': staffUserId,
        'new_scope': staffScope,
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
