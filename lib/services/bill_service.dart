import '../models/bill.dart';

class BillService {
  BillService._();
  static final BillService _instance = BillService._();
  factory BillService() => _instance;

  final List<Bill> _bills = _seed();

  List<Bill> getBills() => List.unmodifiable(_bills);

  List<Bill> getUpcoming({int withinDays = 30}) {
    final horizon = DateTime.now().add(Duration(days: withinDays));
    return _bills
        .where((b) =>
            !b.isPaid &&
            !b.dueDate.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
            b.dueDate.isBefore(horizon))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<Bill> getOverdue() => _bills
      .where((b) => b.status == BillStatus.overdue)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  double get monthlyTotal => _bills
      .where((b) => b.frequency == BillFrequency.monthly && !b.isPaid)
      .fold(0.0, (sum, b) => sum + b.amount);

  double get overdueTotal => getOverdue().fold(0.0, (s, b) => s + b.amount);

  double get paidThisMonth {
    final now = DateTime.now();
    return _bills
        .where((b) =>
            b.isPaid &&
            b.paidOn != null &&
            b.paidOn!.year == now.year &&
            b.paidOn!.month == now.month)
        .fold(0.0, (s, b) => s + b.amount);
  }

  void markPaid(String id) {
    final i = _bills.indexWhere((b) => b.id == id);
    if (i != -1) {
      _bills[i] = _bills[i].copyWith(isPaid: true, paidOn: DateTime.now());
    }
  }

  void markUnpaid(String id) {
    final i = _bills.indexWhere((b) => b.id == id);
    if (i != -1) {
      _bills[i] = _bills[i].copyWith(isPaid: false);
    }
  }

  void addBill(Bill bill) => _bills.insert(0, bill);

  void deleteBill(String id) => _bills.removeWhere((b) => b.id == id);

  static List<Bill> _seed() {
    final now = DateTime.now();
    final m = now.month;
    final y = now.year;

    return [
      Bill(
        id: 'bill-001',
        name: 'HDFC Credit Card',
        category: BillCategory.creditCard,
        provider: 'HDFC Bank',
        amount: 12450,
        dueDate: DateTime(y, m, now.day + 3),
        isRecurring: true,
        frequency: BillFrequency.monthly,
        notes: 'Statement cycle: 1st to last day',
      ),
      Bill(
        id: 'bill-002',
        name: 'Electricity Bill',
        category: BillCategory.electricity,
        provider: 'BESCOM / TNEB',
        amount: 3200,
        dueDate: DateTime(y, m, now.day + 6),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
      Bill(
        id: 'bill-003',
        name: 'Home Broadband',
        category: BillCategory.internet,
        provider: 'Airtel Xstream',
        amount: 999,
        dueDate: DateTime(y, m, now.day + 1),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
      Bill(
        id: 'bill-004',
        name: 'LIC Term Insurance',
        category: BillCategory.insurance,
        provider: 'LIC of India',
        amount: 24000,
        dueDate: DateTime(y, m + 1, 5),
        isRecurring: true,
        frequency: BillFrequency.yearly,
        notes: 'Annual premium',
      ),
      Bill(
        id: 'bill-005',
        name: 'Home Loan EMI',
        category: BillCategory.loanEmi,
        provider: 'SBI Home Loans',
        amount: 32000,
        dueDate: DateTime(y, m, 5),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
      Bill(
        id: 'bill-006',
        name: 'Netflix',
        category: BillCategory.subscription,
        provider: 'Netflix India',
        amount: 649,
        dueDate: DateTime(y, m, now.day + 12),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
      Bill(
        id: 'bill-007',
        name: 'Amazon Prime',
        category: BillCategory.subscription,
        provider: 'Amazon India',
        amount: 1499,
        dueDate: DateTime(y, m + 1, 15),
        isRecurring: true,
        frequency: BillFrequency.yearly,
      ),
      Bill(
        id: 'bill-008',
        name: 'Rent',
        category: BillCategory.rent,
        provider: 'Landlord',
        amount: 25000,
        dueDate: DateTime(y, m, now.day - 2),
        isRecurring: true,
        frequency: BillFrequency.monthly,
        notes: 'Pay on 1st of every month',
      ),
      Bill(
        id: 'bill-009',
        name: 'Mobile Postpaid',
        category: BillCategory.mobile,
        provider: 'Jio / Airtel',
        amount: 799,
        dueDate: DateTime(y, m, now.day + 9),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
      Bill(
        id: 'bill-010',
        name: 'Piped Gas',
        category: BillCategory.waterGas,
        provider: 'IGL / MGL',
        amount: 850,
        dueDate: DateTime(y, m, now.day + 14),
        isRecurring: true,
        frequency: BillFrequency.monthly,
      ),
    ];
  }
}
