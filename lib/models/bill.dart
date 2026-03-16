import 'package:flutter/material.dart';

enum BillCategory {
  creditCard,
  electricity,
  internet,
  insurance,
  loanEmi,
  subscription,
  rent,
  mobile,
  waterGas,
  other,
}

enum BillStatus { pending, overdue, paid, upcoming }

enum BillFrequency { oneTime, weekly, monthly, quarterly, halfYearly, yearly }

class Bill {
  final String id;
  final String name;
  final BillCategory category;
  final String provider;
  final double amount;
  final DateTime dueDate;
  bool isPaid;
  final bool isRecurring;
  final BillFrequency frequency;
  final String? notes;
  DateTime? paidOn;

  Bill({
    required this.id,
    required this.name,
    required this.category,
    required this.provider,
    required this.amount,
    required this.dueDate,
    this.isPaid = false,
    this.isRecurring = true,
    this.frequency = BillFrequency.monthly,
    this.notes,
    this.paidOn,
  });

  BillStatus get status {
    if (isPaid) return BillStatus.paid;
    final today = _midnight(DateTime.now());
    final due = _midnight(dueDate);
    if (due.isBefore(today)) return BillStatus.overdue;
    if (due.difference(today).inDays <= 7) return BillStatus.upcoming;
    return BillStatus.pending;
  }

  int get daysUntilDue {
    final today = _midnight(DateTime.now());
    final due = _midnight(dueDate);
    return due.difference(today).inDays;
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  static Color categoryIconColor(BillCategory cat) {
    switch (cat) {
      case BillCategory.creditCard:
        return const Color(0xFFDC2626);
      case BillCategory.electricity:
        return const Color(0xFF2563EB);
      case BillCategory.internet:
        return const Color(0xFF16A34A);
      case BillCategory.insurance:
        return const Color(0xFF7C3AED);
      case BillCategory.loanEmi:
        return const Color(0xFFD97706);
      case BillCategory.subscription:
        return const Color(0xFFDB2777);
      case BillCategory.rent:
        return const Color(0xFF475569);
      case BillCategory.mobile:
        return const Color(0xFF0891B2);
      case BillCategory.waterGas:
        return const Color(0xFF0D9488);
      case BillCategory.other:
        return const Color(0xFF64748B);
    }
  }

  static Color categoryBgColor(BillCategory cat) {
    switch (cat) {
      case BillCategory.creditCard:
        return const Color(0xFFFEE2E2);
      case BillCategory.electricity:
        return const Color(0xFFDBEAFE);
      case BillCategory.internet:
        return const Color(0xFFDCFCE7);
      case BillCategory.insurance:
        return const Color(0xFFF3E8FF);
      case BillCategory.loanEmi:
        return const Color(0xFFFEF3C7);
      case BillCategory.subscription:
        return const Color(0xFFFCE7F3);
      case BillCategory.rent:
        return const Color(0xFFF1F5F9);
      case BillCategory.mobile:
        return const Color(0xFFECFEFF);
      case BillCategory.waterGas:
        return const Color(0xFFF0FDFA);
      case BillCategory.other:
        return const Color(0xFFF8FAFC);
    }
  }

  static IconData categoryIcon(BillCategory cat) {
    switch (cat) {
      case BillCategory.creditCard:
        return Icons.credit_card;
      case BillCategory.electricity:
        return Icons.bolt;
      case BillCategory.internet:
        return Icons.wifi;
      case BillCategory.insurance:
        return Icons.verified_user_outlined;
      case BillCategory.loanEmi:
        return Icons.account_balance_outlined;
      case BillCategory.subscription:
        return Icons.subscriptions_outlined;
      case BillCategory.rent:
        return Icons.home_outlined;
      case BillCategory.mobile:
        return Icons.phone_android_outlined;
      case BillCategory.waterGas:
        return Icons.water_drop_outlined;
      case BillCategory.other:
        return Icons.receipt_outlined;
    }
  }

  static String categoryLabel(BillCategory cat) {
    switch (cat) {
      case BillCategory.creditCard:
        return 'Credit Card';
      case BillCategory.electricity:
        return 'Electricity';
      case BillCategory.internet:
        return 'Internet';
      case BillCategory.insurance:
        return 'Insurance';
      case BillCategory.loanEmi:
        return 'Loan / EMI';
      case BillCategory.subscription:
        return 'Subscription';
      case BillCategory.rent:
        return 'Rent';
      case BillCategory.mobile:
        return 'Mobile';
      case BillCategory.waterGas:
        return 'Water / Gas';
      case BillCategory.other:
        return 'Other';
    }
  }

  static String frequencyLabel(BillFrequency f) {
    switch (f) {
      case BillFrequency.oneTime:
        return 'One-time';
      case BillFrequency.weekly:
        return 'Weekly';
      case BillFrequency.monthly:
        return 'Monthly';
      case BillFrequency.quarterly:
        return 'Quarterly';
      case BillFrequency.halfYearly:
        return 'Half-yearly';
      case BillFrequency.yearly:
        return 'Yearly';
    }
  }

  Bill copyWith({bool? isPaid, DateTime? paidOn}) => Bill(
        id: id,
        name: name,
        category: category,
        provider: provider,
        amount: amount,
        dueDate: dueDate,
        isPaid: isPaid ?? this.isPaid,
        isRecurring: isRecurring,
        frequency: frequency,
        notes: notes,
        paidOn: paidOn ?? this.paidOn,
      );
}
