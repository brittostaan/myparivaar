class Budget {
  final String id;
  final String category;
  final double amount;
  final String month;
  final double spent;

  const Budget({
    required this.id,
    required this.category,
    required this.amount,
    required this.month,
    this.spent = 0,
  });

  double get remaining => amount - spent;
  bool get isOverBudget => spent > amount;
  double get usagePercent => amount <= 0 ? 0 : (spent / amount) * 100;

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      month: json['month'] as String? ?? '',
      spent: (json['spent'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'month': month,
      'spent': spent,
    };
  }

  Budget copyWith({
    String? id,
    String? category,
    double? amount,
    String? month,
    double? spent,
  }) {
    return Budget(
      id: id ?? this.id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      month: month ?? this.month,
      spent: spent ?? this.spent,
    );
  }
}

class BudgetSummary {
  final String month;
  final List<Budget> budgets;

  const BudgetSummary({
    required this.month,
    required this.budgets,
  });

  double get totalBudget =>
      budgets.fold<double>(0, (sum, budget) => sum + budget.amount);

  double get totalSpent =>
      budgets.fold<double>(0, (sum, budget) => sum + budget.spent);

  double get totalRemaining => totalBudget - totalSpent;
}
