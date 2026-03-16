/// Represents the authenticated user record stored in Supabase.
class AppUser {
  const AppUser({
    required this.id,
    required this.supabaseUserId,
    required this.email,
    required this.role,
    required this.notificationsEnabled,
    required this.voiceEnabled,
    required this.createdAt,
    this.householdId,
    this.displayName,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.dateOfBirth,
    this.photoUrl,
  });

  final String id;
  final String? supabaseUserId;  // Supabase Auth UID (stored as firebase_uid in DB for compatibility)
  final String email;

  /// 'admin' | 'member' | 'super_admin'
  final String role;

  final String? householdId;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final DateTime? dateOfBirth;
  final String? photoUrl;
  final bool notificationsEnabled;
  final bool voiceEnabled;
  final DateTime createdAt;

  bool get isAdmin      => role == 'admin';
  bool get isMember     => role == 'member';
  bool get isSuperAdmin => role == 'super_admin';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at']?.toString();
    final dobRaw = json['date_of_birth']?.toString();
    return AppUser(
      id:                   json['id']?.toString() ?? '',
      supabaseUserId:       json['firebase_uid']?.toString(),  // DB column still named firebase_uid
      email:                json['email']?.toString() ?? '',
      role:                 json['role']?.toString() ?? 'member',
      householdId:          json['household_id']          as String?,
      displayName:          json['display_name']          as String?,
      firstName:            json['first_name']            as String?,
      lastName:             json['last_name']             as String?,
      phoneNumber:          (json['phone_number'] ?? json['phone']) as String?,
      dateOfBirth:          dobRaw != null ? DateTime.parse(dobRaw) : null,
      photoUrl:             json['photo_url']             as String?,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      voiceEnabled:         json['voice_enabled']         as bool? ?? true,
      createdAt:            createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now(),
    );
  }

  AppUser copyWith({
    String? role,
    String? householdId,
    String? displayName,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? photoUrl,
    bool?   notificationsEnabled,
    bool?   voiceEnabled,
  }) {
    return AppUser(
      id:                   id,
      supabaseUserId:       supabaseUserId,
      email:                email,
      role:                 role                 ?? this.role,
      householdId:          householdId          ?? this.householdId,
      displayName:          displayName          ?? this.displayName,
      firstName:            firstName            ?? this.firstName,
      lastName:             lastName             ?? this.lastName,
      phoneNumber:          phoneNumber          ?? this.phoneNumber,
      dateOfBirth:          dateOfBirth          ?? this.dateOfBirth,
      photoUrl:             photoUrl             ?? this.photoUrl,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      voiceEnabled:         voiceEnabled         ?? this.voiceEnabled,
      createdAt:            createdAt,
    );
  }
}
