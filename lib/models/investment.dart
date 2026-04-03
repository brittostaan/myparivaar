import 'package:flutter/material.dart';

enum InvestmentRiskLevel { low, medium, high }

class Investment {
  final String id;
  final String name;
  final String type;
  final String? provider;
  final double amountInvested;
  final double currentValue;
  final DateTime? dueDate;
  final DateTime? maturityDate;
  final String frequency;
  final InvestmentRiskLevel riskLevel;
  final String? notes;
  final String? childName;
  final DateTime createdAt;

  const Investment({
    required this.id,
    required this.name,
    required this.type,
    this.provider,
    required this.amountInvested,
    required this.currentValue,
    required this.dueDate,
    required this.maturityDate,
    required this.frequency,
    required this.riskLevel,
    this.notes,
    this.childName,
    required this.createdAt,
  });

  double get netReturns => currentValue - amountInvested;

  factory Investment.fromJson(Map<String, dynamic> json) {
    return Investment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'Other',
      provider: json['provider'] as String?,
      amountInvested: (json['amount_invested'] as num?)?.toDouble() ?? 0,
      currentValue: (json['current_value'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
      maturityDate: json['maturity_date'] != null
          ? DateTime.tryParse(json['maturity_date'] as String)
          : null,
      frequency: json['frequency'] as String? ?? 'One-time',
      riskLevel: _parseRiskLevel(json['risk_level'] as String?),
      notes: json['notes'] as String?,
      childName: json['child_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static InvestmentRiskLevel _parseRiskLevel(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'low':
        return InvestmentRiskLevel.low;
      case 'high':
        return InvestmentRiskLevel.high;
      default:
        return InvestmentRiskLevel.medium;
    }
  }

  static String riskLevelKey(InvestmentRiskLevel riskLevel) {
    switch (riskLevel) {
      case InvestmentRiskLevel.low:
        return 'low';
      case InvestmentRiskLevel.medium:
        return 'medium';
      case InvestmentRiskLevel.high:
        return 'high';
    }
  }

  static String riskLevelLabel(InvestmentRiskLevel riskLevel) {
    switch (riskLevel) {
      case InvestmentRiskLevel.low:
        return 'Low';
      case InvestmentRiskLevel.medium:
        return 'Medium';
      case InvestmentRiskLevel.high:
        return 'High';
    }
  }

  static Color riskColor(InvestmentRiskLevel riskLevel) {
    switch (riskLevel) {
      case InvestmentRiskLevel.low:
        return const Color(0xFF16A34A);
      case InvestmentRiskLevel.medium:
        return const Color(0xFFD97706);
      case InvestmentRiskLevel.high:
        return const Color(0xFFDC2626);
    }
  }
}
