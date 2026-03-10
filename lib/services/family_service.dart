import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/member.dart';

/// Thrown by [FamilyService] for all API-level failures.
class FamilyException implements Exception {
  const FamilyException(this.message);
  final String message;

  @override
  String toString() => 'FamilyException: $message';
}

/// Manages household membership via Supabase Edge Functions.
///
/// Depends on:
///   household-members  (POST)  — list all members in the caller's household
///   household-invite   (POST)  — admin: generate invite code for a phone number
///   household-join     (POST)  — attach the caller to a household via invite code
///   household-remove   (POST)  — admin: soft-deactivate a member
class FamilyService {
  FamilyService({
    required String supabaseUrl,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl.replaceAll(RegExp(r'/$'), ''),
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client();

  final String       _supabaseUrl;
  final FirebaseAuth _auth;
  final http.Client  _http;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns all active members of the caller's household, sorted admin-first.
  Future<List<Member>> fetchMembers() async {
    final data = await _post('household-members', {});
    final list = data['members'] as List;
    final members = list
        .map((e) => Member.fromJson(e as Map<String, dynamic>))
        .toList();
    // Admin always appears first; ties broken by joinedAt from the server.
    members.sort((a, b) {
      if (a.isAdmin && !b.isAdmin) return -1;
      if (!a.isAdmin && b.isAdmin) return 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });
    return members;
  }

  /// Admin-only. Generates an invite code for [phoneNumber].
  /// The code must be shared out-of-band — no SMS is sent.
  /// Throws [FamilyException] if the caller is not admin, household is full,
  /// or a pending invite already exists for that number.
  Future<InviteResult> inviteMember(String phoneNumber) async {
    final data = await _post('household-invite', {'phone_number': phoneNumber});
    return InviteResult.fromJson(data);
  }

  /// Attaches the authenticated user to a household using [inviteCode].
  ///
  /// The invite must be pending, non-expired, and issued for the caller's
  /// phone number. Returns both the updated [AppUser] and the [Household].
  ///
  /// Typical flow (used from [_NeedsHouseholdScreen]):
  ///   1. Call [joinHousehold] with the code the admin shared.
  ///   2. On success, call [AuthService.refreshSession] to sync app state.
  Future<JoinResult> joinHousehold(String inviteCode) async {
    final data = await _post(
      'household-join',
      {'invite_code': inviteCode.trim().toUpperCase()},
      expectedStatus: 201,
    );
    return JoinResult.fromJson(data);
  }

  /// Admin-only. Soft-deactivates [userId] in the household.
  /// The removed user's is_active flag is cleared; their data is retained.
  Future<void> removeMember(String userId) async {
    // Edge Function expects the key 'member_user_id', not 'user_id'.
    await _post('household-remove', {'member_user_id': userId});
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String function,
    Map<String, dynamic> body, {
    int expectedStatus = 200,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const FamilyException('Not authenticated.');

    final idToken = await user.getIdToken(true);

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_supabaseUrl/functions/v1/$function'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (_) {
      throw const FamilyException('Network error: unable to reach the server.');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const FamilyException('Unexpected response from server.');
    }

    if (response.statusCode == expectedStatus ||
        (response.statusCode >= 200 && response.statusCode < 300)) {
      return data;
    }

    throw FamilyException(
      data['error'] as String? ?? 'Request failed (${response.statusCode}).',
    );
  }
}
