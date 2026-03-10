/// Represents the authenticated user record stored in Supabase.
class AppUser {
  const AppUser({
    required this.id,
    required this.firebaseUid,
    required this.phone,
    required this.role,
    required this.notificationsEnabled,
    required this.voiceEnabled,
    required this.createdAt,
    this.householdId,
    this.displayName,
  });

  final String id;
  final String firebaseUid;
  final String phone;

  /// 'admin' | 'member' | 'super_admin'
  final String role;

  final String? householdId;
  final String? displayName;
  final bool notificationsEnabled;
  final bool voiceEnabled;
  final DateTime createdAt;

  bool get isAdmin      => role == 'admin';
  bool get isMember     => role == 'member';
  bool get isSuperAdmin => role == 'super_admin';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id:                   json['id']                    as String,
      firebaseUid:          json['firebase_uid']          as String,
      phone:                json['phone']                 as String,
      role:                 json['role']                  as String,
      householdId:          json['household_id']          as String?,
      displayName:          json['display_name']          as String?,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      voiceEnabled:         json['voice_enabled']         as bool? ?? true,
      createdAt:            DateTime.parse(json['created_at'] as String),
    );
  }

  AppUser copyWith({
    String? role,
    String? householdId,
    String? displayName,
    bool?   notificationsEnabled,
    bool?   voiceEnabled,
  }) {
    return AppUser(
      id:                   id,
      firebaseUid:          firebaseUid,
      phone:                phone,
      role:                 role                 ?? this.role,
      householdId:          householdId          ?? this.householdId,
      displayName:          displayName          ?? this.displayName,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      voiceEnabled:         voiceEnabled         ?? this.voiceEnabled,
      createdAt:            createdAt,
    );
  }
}
