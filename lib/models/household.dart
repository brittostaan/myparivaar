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
    return Household(
      id:               json['id']                 as String,
      name:             json['name']               as String,
      adminFirebaseUid: json['admin_firebase_uid'] as String,
      plan:             json['plan']               as String? ?? 'free',
      suspended:        json['suspended']          as bool?   ?? false,
      createdAt:        DateTime.parse(json['created_at'] as String),
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
