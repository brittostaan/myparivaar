import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../models/household.dart';

/// Thrown by [AuthService] for authentication and bootstrap errors.
class AppAuthException implements Exception {
  const AppAuthException(this.message);
  final String message;

  @override
  String toString() => 'AppAuthException: $message';
}

/// Describes the state of the user after a successful sign-in.
enum AuthStatus {
  /// Signed in and attached to a household — proceed to home.
  ready,

  /// Signed in but no household yet — show onboarding (create / join).
  needsHousehold,
}

/// Manages Supabase Email/Password Authentication and user bootstrapping.
///
/// Usage:
///   1. [signInWithEmail]  — sign in with email and password
///   2. [signUpWithEmail]  — create new account with email and password
///   3. [refreshSession]   — restore state on app cold start
///   4. [signOut]          — clear session
///
/// State is held in memory only. The service is a [ChangeNotifier] so
/// widgets or state managers can listen for [currentUser] / [currentHousehold]
/// changes without depending on this class directly.
class AuthService extends ChangeNotifier {
  AuthService({
    required String supabaseUrl,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl.replaceAll(RegExp(r'/$'), ''),
        _supabase = supabaseClient ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  final String _supabaseUrl;
  final SupabaseClient _supabase;
  final http.Client _http;

  // ── In-memory state ────────────────────────────────────────────────────────
  AppUser? _currentUser;
  Household? _currentHousehold;
  bool _isLoading = false;

  // ── Public read-only state ─────────────────────────────────────────────────
  AppUser? get currentUser => _currentUser;
  Household? get currentHousehold => _currentHousehold;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  bool get hasHousehold => _currentHousehold != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  String get supabaseUrl => _supabaseUrl;

  // ── Public methods ─────────────────────────────────────────────────────────

  /// Get the current Supabase JWT token, auto-refreshing if expired or stale.
  Future<String> getIdToken([bool forceRefresh = false]) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw const AppAuthException('User not authenticated');
    }

    // Auto-refresh if:
    //  - expiresAt is unknown (can't trust the token)
    //  - token is within 60 seconds of expiry (or already expired)
    final expiresAt = session.expiresAt;
    final isExpired = expiresAt == null ||
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt - 60;

    if (forceRefresh || isExpired) {
      final response = await _supabase.auth.refreshSession();
      if (response.session == null) {
        throw const AppAuthException('Unable to refresh token');
      }
      return response.session!.accessToken;
    }

    return session.accessToken;
  }

  // ── Sign In with Email/Password ────────────────────────────────────────────

  /// Signs in with email and password, then bootstraps the user against Supabase.
  ///
  /// Returns [AuthStatus.ready] if the user has a household,
  /// or [AuthStatus.needsHousehold] if the user needs to create or join one.
  ///
  /// Throws [AppAuthException] on invalid credentials or server error.
  Future<AuthStatus> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final response = await _withRetry(
        () => _supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
        actionLabel: 'sign in',
      );

      if (response.user == null) {
        throw const AppAuthException('Sign-in succeeded but returned no user.');
      }

      await _bootstrap();
      return hasHousehold ? AuthStatus.ready : AuthStatus.needsHousehold;
    } on AppAuthException {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AppAuthException(
        'Unable to reach Supabase authentication service. Check your internet connection and try again.',
      );
    } on AuthApiException catch (e) {
      throw AppAuthException(_friendlySupabaseError(e));
    } catch (e) {
      throw AppAuthException('Sign-in failed: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // ── Sign Up with Email/Password ────────────────────────────────────────────

  /// Creates a new account with email and password.
  ///
  /// [familyName] — optional. If provided, the Edge Function will create a
  /// household and assign the user as admin.
  ///
  /// Returns [AuthStatus.ready] if the user has a household,
  /// or [AuthStatus.needsHousehold] if the user needs to create or join one.
  ///
  /// Throws [AppAuthException] on validation errors or server error.
  Future<AuthStatus> signUpWithEmail({
    required String email,
    required String password,
    String? familyName,
  }) async {
    _setLoading(true);
    try {
      final response = await _withRetry(
        () => _supabase.auth.signUp(
          email: email.trim(),
          password: password,
        ),
        actionLabel: 'sign up',
      );

      if (response.user == null) {
        throw const AppAuthException('Sign-up succeeded but returned no user.');
      }

      // Bootstrap with optional family name
      await _bootstrap(familyName: familyName);
      return hasHousehold ? AuthStatus.ready : AuthStatus.needsHousehold;
    } on AppAuthException {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AppAuthException(
        'Unable to reach Supabase authentication service. Check your internet connection and try again.',
      );
    } on AuthApiException catch (e) {
      throw AppAuthException(_friendlySupabaseError(e));
    } catch (e) {
      throw AppAuthException('Sign-up failed: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // ── Session restore ────────────────────────────────────────────────────────

  /// Restores session on cold start by re-bootstrapping the existing
  /// Supabase session (if any). Call once from app initialisation.
  ///
  /// Returns [AuthStatus.ready], [AuthStatus.needsHousehold], or null if the
  /// user has no active Supabase session.
  Future<AuthStatus?> refreshSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null;

    _setLoading(true);
    try {
      // Refresh token in case it expired while the app was closed.
      await _withRetry(
        _supabase.auth.refreshSession,
        actionLabel: 'refresh session',
      );
      await _bootstrap();
      return hasHousehold ? AuthStatus.ready : AuthStatus.needsHousehold;
    } on AppAuthException catch (e) {
      debugPrint('refreshSession app auth error: ${e.message}');
      if (_isTerminalAuthError(e.message)) {
        await signOut();
        return null;
      }
      rethrow;
    } catch (e) {
      // Preserve transient issues; only force re-login on terminal auth failures.
      debugPrint('refreshSession error: $e');
      if (_looksLikeTerminalAuthError(e.toString())) {
        await signOut();
        return null;
      }
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _currentUser = null;
    _currentHousehold = null;
    notifyListeners();
  }

  // ── Profile update ─────────────────────────────────────────────────────────

  /// Updates the current user's profile fields via the user-update Edge Function.
  /// Returns the updated [AppUser]. Throws [AppAuthException] on failure.
  Future<AppUser> updateProfile({
    String? displayName,
    String? firstName,
    String? lastName,
    String? phone,
    String? dateOfBirth,
    String? photoUrl,
  }) async {
    final idToken = await getIdToken();

    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;
    if (phone != null) body['phone'] = phone;
    if (dateOfBirth != null) body['date_of_birth'] = dateOfBirth;
    if (photoUrl != null) body['photo_url'] = photoUrl;

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_supabaseUrl/functions/v1/user-update'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw AppAuthException(
          'Network error during profile update: ${e.toString()}');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      notifyListeners();
      return _currentUser!;
    } else {
      throw AppAuthException(_parseServerError(response.body));
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Retrieves a fresh Supabase JWT token, calls auth-bootstrap, and updates
  /// in-memory state. Throws [AppAuthException] on any failure.
  Future<void> _bootstrap({String? familyName}) async {
    // Get the current session access token
    final idToken = await getIdToken(true);

    final body = <String, dynamic>{};
    final trimmedName = familyName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      body['family_name'] = trimmedName;
    }

    final http.Response response;
    try {
      response = await _withRetry(
        () => _http.post(
          Uri.parse('$_supabaseUrl/functions/v1/auth-bootstrap'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        ),
        actionLabel: 'bootstrap user',
      );
    } catch (e) {
      throw AppAuthException('Network error during bootstrap: ${e.toString()}');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);

      _currentHousehold = data['household'] != null
          ? Household.fromJson(data['household'] as Map<String, dynamic>)
          : null;

      notifyListeners();
    } else {
      debugPrint(
          'auth-bootstrap error: status=${response.statusCode} body=${response.body}');
      throw AppAuthException(_parseServerError(response.body));
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Extracts the 'error' field from a JSON error body, falling back to a
  /// generic message rather than exposing raw server text.
  String _parseServerError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = (data['error'] as String?) ??
          (data['message'] as String?) ??
          (data['error_description'] as String?);
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    return 'An unexpected server error occurred.';
  }

  bool _isTerminalAuthError(String message) {
    final m = message.toLowerCase();
    return m.contains('invalid or expired token') ||
        m.contains('missing authorization') ||
        m.contains('not authenticated') ||
        m.contains('token verification failed') ||
        m.contains('invalid jwt') ||
        m.contains('jwt expired');
  }

  bool _looksLikeTerminalAuthError(String message) {
    final m = message.toLowerCase();
    // Match only specific, well-known terminal auth error strings to avoid
    // signing out users on unrelated errors that happen to contain 'auth',
    // 'jwt', or 'token' (e.g. network proxy errors, 503 response bodies).
    return m.contains('invalid or expired token') ||
        m.contains('missing authorization') ||
        m.contains('not authenticated') ||
        m.contains('token verification failed') ||
        m.contains('invalid jwt') ||
        m.contains('jwt expired') ||
        m.contains('user not found');
  }

  Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    required String actionLabel,
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } on AuthRetryableFetchException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }

      if (attempt < maxAttempts) {
        final delayMs = 300 * attempt;
        debugPrint(
            'Retrying $actionLabel (attempt $attempt/$maxAttempts) after ${delayMs}ms...');
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw AppAuthException(
      'Unable to $actionLabel right now. Please check your connection and try again. (${lastError ?? 'unknown error'})',
    );
  }

  /// Maps Supabase AuthApiException error messages to user-readable messages.
  String _friendlySupabaseError(AuthApiException e) {
    final message = e.message.toLowerCase();

    if (message.contains('invalid login credentials') ||
        message.contains('invalid email or password')) {
      return 'Invalid email or password. Please try again.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email address to sign in.';
    }
    if (message.contains('user already registered')) {
      return 'This email is already registered. Please sign in instead.';
    }
    if (message.contains('password')) {
      return 'Password must be at least 6 characters long.';
    }
    if (message.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (message.contains('network')) {
      return 'No internet connection. Please check your network.';
    }

    return e.message;
  }
}
