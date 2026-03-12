import 'app_user.dart';
import 'household.dart';

/// A household member as returned by the household-members Edge Function.
///
/// Field mapping (Edge Function → Dart):
///   phone_number → phone
///   name         → displayName
class Member {
  const Member({
    required this.id,
    required this.phone,
    required this.role,
    required this.joinedAt,
    this.displayName,
  });

  final String   id;
  final String   phone;

  /// 'admin' | 'member'
  final String   role;

  final String?  displayName;
  final DateTime joinedAt;

  bool   get isAdmin       => role == 'admin';
  String get displayLabel  => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : phone;

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id:          json['id']           as String,
        // household-members returns phone_number (not phone)
        phone:       json['phone_number'] as String,
        role:        json['role']         as String,
        // household-members returns name (not display_name)
        displayName: json['name']         as String?,
        joinedAt:    DateTime.parse(json['created_at'] as String),
      );
}

/// Returned by [FamilyService.inviteMember].
class InviteResult {
  const InviteResult({
    required this.inviteCode,
    required this.phoneNumber,
    required this.expiresAt,
  });

  final String   inviteCode;
  final String   phoneNumber;
  final DateTime expiresAt;

  factory InviteResult.fromJson(Map<String, dynamic> json) => InviteResult(
        inviteCode:  json['invite_code']  as String,
        phoneNumber: json['phone_number'] as String,
        expiresAt:   DateTime.parse(json['expires_at'] as String),
      );
}

/// Returned by [FamilyService.joinHousehold].
///
/// Contains the updated [AppUser] (now with household_id and role='member')
/// and the [Household] they just joined.
class JoinResult {
  const JoinResult({required this.user, required this.household});

  final AppUser   user;
  final Household household;

  factory JoinResult.fromJson(Map<String, dynamic> json) => JoinResult(
        user:      AppUser.fromJson(json['user']      as Map<String, dynamic>),
        household: Household.fromJson(json['household'] as Map<String, dynamic>),
      );
}
