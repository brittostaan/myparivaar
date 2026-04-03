import 'package:flutter/material.dart';

enum BillCategory {
  rent,
  utilities,
  internet,
  insurance,
  creditCard,
  subscription,
  loan,
  school,
  other,
}

enum BillFrequency {
  monthly,
  quarterly,
  yearly,
  oneTime,
}

class Bill {
  final String id;
  final String name;
  final String? provider;
  final BillCategory category;
  final BillFrequency frequency;
  final double amount;
  final DateTime dueDate;
  final bool isRecurring;
  final bool isPaid;
  final DateTime? paidOn;
  final String? notes;
  final List<String> tags;
  final DateTime createdAt;

  const Bill({
    required this.id,
    required this.name,
    this.provider,
    required this.category,
    required this.frequency,
    required this.amount,
    required this.dueDate,
    required this.isRecurring,
    required this.isPaid,
    this.paidOn,
    this.notes,
    this.tags = const [],
    required this.createdAt,
  });

  int get daysUntilDue {
    final now = DateTime.now();
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final today = DateTime(now.year, now.month, now.day);
    return due.difference(today).inDays;
  }

  bool get isOverdue => !isPaid && daysUntilDue < 0;
  bool get isUpcoming => !isPaid && daysUntilDue >= 0;

  Bill copyWith({
    bool? isPaid,
    DateTime? paidOn,
    List<String>? tags,
  }) {
    return Bill(
      id: id,
      name: name,
      provider: provider,
      category: category,
      frequency: frequency,
      amount: amount,
      dueDate: dueDate,
      isRecurring: isRecurring,
      isPaid: isPaid ?? this.isPaid,
      paidOn: paidOn ?? this.paidOn,
      notes: notes,
      tags: tags ?? this.tags,
      createdAt: createdAt,
    );
  }

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String?,
      category: _parseCategory(json['category'] as String?),
      frequency: _parseFrequency(json['frequency'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      isRecurring: json['is_recurring'] as bool? ?? true,
      isPaid: json['is_paid'] as bool? ?? false,
      paidOn: json['paid_on'] != null
          ? DateTime.tryParse(json['paid_on'] as String)
          : null,
      notes: json['notes'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static BillCategory _parseCategory(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'rent':
        return BillCategory.rent;
      case 'utilities':
        return BillCategory.utilities;
      case 'internet':
        return BillCategory.internet;
      case 'insurance':
        return BillCategory.insurance;
      case 'credit_card':
        return BillCategory.creditCard;
      case 'subscription':
        return BillCategory.subscription;
      case 'loan':
        return BillCategory.loan;
      case 'school':
        return BillCategory.school;
      default:
        return BillCategory.other;
    }
  }

  static BillFrequency _parseFrequency(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'monthly':
        return BillFrequency.monthly;
      case 'quarterly':
        return BillFrequency.quarterly;
      case 'yearly':
        return BillFrequency.yearly;
      default:
        return BillFrequency.oneTime;
    }
  }

  static String categoryKey(BillCategory category) {
    switch (category) {
      case BillCategory.rent:
        return 'rent';
      case BillCategory.utilities:
        return 'utilities';
      case BillCategory.internet:
        return 'internet';
      case BillCategory.insurance:
        return 'insurance';
      case BillCategory.creditCard:
        return 'credit_card';
      case BillCategory.subscription:
        return 'subscription';
      case BillCategory.loan:
        return 'loan';
      case BillCategory.school:
        return 'school';
      case BillCategory.other:
        return 'other';
    }
  }

  static String frequencyKey(BillFrequency frequency) {
    switch (frequency) {
      case BillFrequency.monthly:
        return 'monthly';
      case BillFrequency.quarterly:
        return 'quarterly';
      case BillFrequency.yearly:
        return 'yearly';
      case BillFrequency.oneTime:
        return 'one_time';
    }
  }

  static String categoryLabel(BillCategory category) {
    switch (category) {
      case BillCategory.rent:
        return 'Rent';
      case BillCategory.utilities:
        return 'Utilities';
      case BillCategory.internet:
        return 'Internet';
      case BillCategory.insurance:
        return 'Insurance';
      case BillCategory.creditCard:
        return 'Credit Card';
      case BillCategory.subscription:
        return 'Subscription';
      case BillCategory.loan:
        return 'Loan';
      case BillCategory.school:
        return 'School';
      case BillCategory.other:
        return 'Other';
    }
  }

  static String frequencyLabel(BillFrequency frequency) {
    switch (frequency) {
      case BillFrequency.monthly:
        return 'Monthly';
      case BillFrequency.quarterly:
        return 'Quarterly';
      case BillFrequency.yearly:
        return 'Yearly';
      case BillFrequency.oneTime:
        return 'One-time';
    }
  }

  static IconData iconForCategory(BillCategory category) {
    switch (category) {
      case BillCategory.rent:
        return Icons.home_work_outlined;
      case BillCategory.utilities:
        return Icons.bolt_outlined;
      case BillCategory.internet:
        return Icons.wifi_outlined;
      case BillCategory.insurance:
        return Icons.health_and_safety_outlined;
      case BillCategory.creditCard:
        return Icons.credit_card_outlined;
      case BillCategory.subscription:
        return Icons.subscriptions_outlined;
      case BillCategory.loan:
        return Icons.account_balance_outlined;
      case BillCategory.school:
        return Icons.school_outlined;
      case BillCategory.other:
        return Icons.receipt_long_outlined;
    }
  }
}
