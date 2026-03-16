class InvestmentRecord {
  final String id;
  final String name;
  final String type;
  final String provider;
  final double amountInvested;
  final double currentValue;
  final DateTime? dueDate;
  final DateTime? maturityDate;
  final String frequency;
  final String riskLevel;
  final String notes;

  const InvestmentRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.provider,
    required this.amountInvested,
    required this.currentValue,
    required this.dueDate,
    required this.maturityDate,
    required this.frequency,
    required this.riskLevel,
    required this.notes,
  });
}
