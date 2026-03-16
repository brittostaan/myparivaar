class SavingsGoal {
  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final String? notes;
  final DateTime createdAt;

  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.targetDate,
    this.notes,
    required this.createdAt,
  });

  double get progressPercent =>
      targetAmount <= 0 ? 0 : (currentAmount / targetAmount * 100).clamp(0, 100);

  double get remaining => (targetAmount - currentAmount).clamp(0, double.infinity);

  bool get isCompleted => currentAmount >= targetAmount;

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      targetAmount: (json['target_amount'] as num?)?.toDouble() ?? 0,
      currentAmount: (json['current_amount'] as num?)?.toDouble() ?? 0,
      targetDate: json['target_date'] != null
          ? DateTime.tryParse(json['target_date'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      'target_date': targetDate?.toIso8601String().substring(0, 10),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  SavingsGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    double? currentAmount,
    DateTime? targetDate,
    bool clearTargetDate = false,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      notes: clearNotes ? null : (notes ?? this.notes),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
