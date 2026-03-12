/// Represents the household record stored in Supabase.
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.adminFirebaseUid,
    required this.plan,
    required this.suspended,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String adminFirebaseUid;

  /// 'free' | 'paid'
  final String plan;

  final bool suspended;
  final DateTime createdAt;

  bool get isFree => plan == 'free';
  bool get isPaid => plan == 'paid';

  factory Household.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at']?.toString();
    return Household(
      id:               json['id']?.toString() ?? '',
      name:             json['name']?.toString() ?? 'Household',
      // Supports both legacy (admin_firebase_uid) and current (owner_user_id) schemas.
      adminFirebaseUid: (json['admin_firebase_uid'] ?? json['owner_user_id'])?.toString() ?? '',
      plan:             json['plan']?.toString() ?? 'free',
      suspended:        json['suspended'] as bool? ?? false,
      createdAt:        createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now(),
    );
  }

  Household copyWith({String? name, String? plan, bool? suspended}) {
    return Household(
      id:               id,
      name:             name      ?? this.name,
      adminFirebaseUid: adminFirebaseUid,
      plan:             plan      ?? this.plan,
      suspended:        suspended ?? this.suspended,
      createdAt:        createdAt,
    );
  }
}
