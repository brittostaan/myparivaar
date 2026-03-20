import 'admin_permissions.dart';

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
    this.staffRole,
    this.staffScope,
    this.displayName,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.dateOfBirth,
    this.photoUrl,
    this.adminPermissions,
  });

  final String id;
  final String? supabaseUserId;  // Supabase Auth UID (stored as firebase_uid in DB for compatibility)
  final String email;

  /// 'admin' | 'member' | 'super_admin'
  final String role;

  final String? householdId;
  final String? staffRole;
  final String? staffScope;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final DateTime? dateOfBirth;
  final String? photoUrl;
  final Map<String, dynamic>? adminPermissions;
  final bool notificationsEnabled;
  final bool voiceEnabled;
  final DateTime createdAt;

  bool get isAdmin      => role == 'admin';
  bool get isMember     => role == 'member';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isSupportStaff => staffRole == 'support_staff' || role == 'support_staff';
  bool get isPlatformAdmin => isSuperAdmin || isSupportStaff;

  bool hasAdminPermission(String permissionKey) {
    if (isSuperAdmin) {
      return true;
    }

    if (!isPlatformAdmin || !AdminPermissions.all.contains(permissionKey)) {
      return false;
    }

    final raw = adminPermissions?[permissionKey];
    if (raw is bool) {
      return raw;
    }

    // Fall back to role defaults when explicit permissions are not stored.
    return isSupportStaff && AdminPermissions.supportAdminDefaults.contains(permissionKey);
  }

  Set<String> get effectiveAdminPermissions {
    if (isSuperAdmin) {
      return AdminPermissions.superAdminDefaults;
    }

    final explicit = <String>{};
    if (adminPermissions != null) {
      for (final entry in adminPermissions!.entries) {
        if (entry.value == true && AdminPermissions.all.contains(entry.key)) {
          explicit.add(entry.key);
        }
      }
    }

    if (explicit.isNotEmpty) {
      return explicit;
    }

    return isSupportStaff ? AdminPermissions.supportAdminDefaults : <String>{};
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at']?.toString();
    final dobRaw = json['date_of_birth']?.toString();
    return AppUser(
      id:                   json['id']?.toString() ?? '',
      supabaseUserId:       json['firebase_uid']?.toString(),  // DB column still named firebase_uid
      email:                json['email']?.toString() ?? '',
      role:                 json['role']?.toString() ?? 'member',
      householdId:          json['household_id']          as String?,
      staffRole:            json['staff_role']            as String?,
      staffScope:           json['staff_scope']           as String?,
      displayName:          json['display_name']          as String?,
      firstName:            json['first_name']            as String?,
      lastName:             json['last_name']             as String?,
      phoneNumber:          (json['phone_number'] ?? json['phone']) as String?,
      dateOfBirth:          dobRaw != null ? DateTime.parse(dobRaw) : null,
      photoUrl:             json['photo_url']             as String?,
      adminPermissions:     json['admin_permissions']     as Map<String, dynamic>?,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      voiceEnabled:         json['voice_enabled']         as bool? ?? true,
      createdAt:            createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now(),
    );
  }

  AppUser copyWith({
    String? role,
    String? householdId,
    String? staffRole,
    String? staffScope,
    String? displayName,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? photoUrl,
    Map<String, dynamic>? adminPermissions,
    bool?   notificationsEnabled,
    bool?   voiceEnabled,
  }) {
    return AppUser(
      id:                   id,
      supabaseUserId:       supabaseUserId,
      email:                email,
      role:                 role                 ?? this.role,
      householdId:          householdId          ?? this.householdId,
      staffRole:            staffRole            ?? this.staffRole,
      staffScope:           staffScope           ?? this.staffScope,
      displayName:          displayName          ?? this.displayName,
      firstName:            firstName            ?? this.firstName,
      lastName:             lastName             ?? this.lastName,
      phoneNumber:          phoneNumber          ?? this.phoneNumber,
      dateOfBirth:          dateOfBirth          ?? this.dateOfBirth,
      photoUrl:             photoUrl             ?? this.photoUrl,
      adminPermissions:     adminPermissions     ?? this.adminPermissions,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      voiceEnabled:         voiceEnabled         ?? this.voiceEnabled,
      createdAt:            createdAt,
    );
  }
}
