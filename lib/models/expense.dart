class Expense {
  final String id;
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  final String? notes;
  final List<String> tags;
  final String source; // 'manual', 'csv', 'email'
  final bool isApproved; // For email-sourced transactions
  final DateTime createdAt;
  final DateTime updatedAt;

  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    this.notes,
    this.tags = const [],
    required this.source,
    required this.isApproved,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Parses a date string that may be date-only ("2026-03-01") or a full
  /// ISO-8601 timestamp. Date-only strings are treated as local midnight to
  /// avoid off-by-one-day issues for users east of UTC.
  static DateTime _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    // If the string has no time component, append local midnight explicitly.
    final normalized = raw.contains('T') ? raw : '${raw}T00:00:00';
    return DateTime.tryParse(normalized)?.toLocal() ?? DateTime.now();
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id:          json['id']?.toString() ?? '',
      amount:      (json['amount'] as num?)?.toDouble() ?? 0.0,
      category:    json['category']?.toString() ?? 'other',
      description: json['description']?.toString() ?? '',
      date:        _parseDate(json['date']?.toString()),
      notes:       json['notes']?.toString(),
      tags:        (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      source:      json['source']?.toString() ?? 'manual',
      isApproved:  (json['status']?.toString() == 'approved') ||
                   (json['status'] != null && json['status']?.toString() != 'pending'),
      createdAt:   DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt:   DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'category': category,
      'description': description,
      'date': date.toIso8601String().split('T')[0], // Date only
      'notes': notes,
      'tags': tags,
      'source': source,
      'status': isApproved ? 'approved' : 'pending',
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Expense copyWith({
    String? id,
    double? amount,
    String? category,
    String? description,
    DateTime? date,
    String? notes,
    List<String>? tags,
    String? source,
    bool? isApproved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Expense{id: $id, amount: $amount, category: $category, description: $description, date: $date}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Expense && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}