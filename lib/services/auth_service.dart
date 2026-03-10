import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/household.dart';

/// Thrown by [AuthService] for authentication and bootstrap errors.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Describes the state of the user after a successful sign-in.
enum AuthStatus {
  /// Signed in and attached to a household — proceed to home.
  ready,

  /// Signed in but no household yet — show onboarding (create / join).
  needsHousehold,
}

/// Manages Firebase Phone Authentication and Supabase user bootstrapping.
///
/// Usage:
///   1. [verifyPhoneNumber]   — request SMS OTP
///   2. [verifyOtp]           — confirm OTP, bootstrap user, return [AuthStatus]
///   3. [refreshSession]      — restore state on app cold start
///   4. [signOut]             — clear session
///
/// State is held in memory only. The service is a [ChangeNotifier] so
/// widgets or state managers can listen for [currentUser] / [currentHousehold]
/// changes without depending on this class directly.
class AuthService extends ChangeNotifier {
  AuthService({
    required String supabaseUrl,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl.replaceAll(RegExp(r'/$'), ''),
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client();

  final String _supabaseUrl;
  final FirebaseAuth _auth;
  final http.Client _http;

  // ── In-memory state ────────────────────────────────────────────────────────
  AppUser?   _currentUser;
  Household? _currentHousehold;
  bool       _isLoading = false;

  // ── Public read-only state ─────────────────────────────────────────────────
  AppUser?   get currentUser      => _currentUser;
  Household? get currentHousehold => _currentHousehold;
  bool       get isLoading        => _isLoading;
  bool       get isLoggedIn       => _currentUser != null;
  bool       get hasHousehold     => _currentHousehold != null;
  bool       get isAdmin          => _currentUser?.isAdmin ?? false;
  String     get supabaseUrl      => _supabaseUrl;

  // ── Public methods ─────────────────────────────────────────────────────────

  /// Get the current Firebase ID token, refreshing if needed
  Future<String> getIdToken([bool forceRefresh = false]) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthException('User not authenticated');
    }
    final token = await user.getIdToken(forceRefresh);
    if (token == null) {
      throw AuthException('Unable to get ID token');
    }
    return token;
  }

  // ── Phase 1: Request OTP ───────────────────────────────────────────────────

  /// Initiates Firebase Phone Auth and sends an SMS OTP.
  ///
  /// [onCodeSent]     — called with verificationId once the SMS is dispatched.
  /// [onError]        — called with a human-readable message on failure.
  /// [onAutoVerified] — called on Android if the OTP is retrieved automatically.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String error) onError,
    void Function()? onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      // Auto-retrieval on Android — skip manual OTP entry
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final result = await _auth.signInWithCredential(credential);
          if (result.user != null) {
            await _bootstrap(result.user!);
            onAutoVerified?.call();
          }
        } on AuthException catch (e) {
          onError(e.message);
        } catch (_) {
          onError('Auto-verification failed. Please enter the OTP manually.');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(_friendlyError(e));
      },
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {
        // No action required — user continues with manual OTP entry.
      },
    );
  }

  // ── Phase 2: Confirm OTP ───────────────────────────────────────────────────

  /// Verifies the SMS OTP and bootstraps the user against Supabase.
  ///
  /// [familyName] — optional. If provided on a first-ever login, the
  /// Edge Function will create a household and assign the user as admin.
  ///
  /// Returns [AuthStatus.ready] if the user has a household,
  /// or [AuthStatus.needsHousehold] if the user needs to create or join one.
  ///
  /// Throws [AuthException] on invalid OTP or server error.
  Future<AuthStatus> verifyOtp({
    required String verificationId,
    required String smsCode,
    String? familyName,
  }) async {
    _setLoading(true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      final result = await _auth.signInWithCredential(credential);
      if (result.user == null) {
        throw const AuthException('Sign-in succeeded but returned no user.');
      }
      await _bootstrap(result.user!, familyName: familyName);
      return hasHousehold ? AuthStatus.ready : AuthStatus.needsHousehold;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyError(e));
    } finally {
      _setLoading(false);
    }
  }

  // ── Session restore ────────────────────────────────────────────────────────

  /// Restores session on cold start by re-bootstrapping the existing
  /// Firebase session (if any). Call once from app initialisation.
  ///
  /// Returns [AuthStatus.ready], [AuthStatus.needsHousehold], or null if the
  /// user has no active Firebase session.
  Future<AuthStatus?> refreshSession() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    _setLoading(true);
    try {
      // Force-refresh token in case it expired while the app was closed.
      await _bootstrap(firebaseUser);
      return hasHousehold ? AuthStatus.ready : AuthStatus.needsHousehold;
    } on AuthException {
      // Token is genuinely invalid — clear state and force re-login.
      await signOut();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
    _currentUser      = null;
    _currentHousehold = null;
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Retrieves a fresh Firebase ID token, calls auth-bootstrap, and updates
  /// in-memory state. Throws [AuthException] on any failure.
  Future<void> _bootstrap(User firebaseUser, {String? familyName}) async {
    // Always force-refresh the token to avoid serving a stale one.
    final idToken = await firebaseUser.getIdToken(true);

    final body = <String, dynamic>{};
    final trimmedName = familyName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      body['family_name'] = trimmedName;
    }

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_supabaseUrl/functions/v1/auth-bootstrap'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw AuthException('Network error: unable to reach the server.');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);

      _currentHousehold = data['household'] != null
          ? Household.fromJson(data['household'] as Map<String, dynamic>)
          : null;

      notifyListeners();
    } else {
      throw AuthException(_parseServerError(response.body));
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
      final message = data['error'] as String?;
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    return 'An unexpected server error occurred.';
  }

  /// Maps FirebaseAuthException error codes to user-readable messages.
  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check the code and try again.';
      case 'session-expired':
        return 'OTP has expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait before trying again.';
      case 'invalid-phone-number':
        return 'The phone number format is invalid.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
