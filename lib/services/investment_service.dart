import '../models/investment_record.dart';

class InvestmentService {
  InvestmentService._();

  static final InvestmentService _instance = InvestmentService._();

  factory InvestmentService() => _instance;

  final List<InvestmentRecord> _investments = [
    InvestmentRecord(
      id: 'inv-01',
      name: 'HDFC Life Shield',
      type: 'Insurance',
      provider: 'HDFC Life',
      amountInvested: 120000,
      currentValue: 126500,
      dueDate: DateTime.now().add(const Duration(days: 8)),
      maturityDate: DateTime.now().add(const Duration(days: 365 * 14)),
      frequency: 'Yearly',
      riskLevel: 'Low',
      notes: 'Annual premium plan for life cover',
    ),
    InvestmentRecord(
      id: 'inv-02',
      name: 'SBI Bluechip SIP',
      type: 'Mutual Fund',
      provider: 'SBI Mutual Fund',
      amountInvested: 285000,
      currentValue: 332000,
      dueDate: DateTime.now().add(const Duration(days: 4)),
      maturityDate: null,
      frequency: 'Monthly',
      riskLevel: 'Medium',
      notes: 'SIP on 5th of every month',
    ),
    InvestmentRecord(
      id: 'inv-03',
      name: 'PPF Account',
      type: 'Retirement',
      provider: 'State Bank of India',
      amountInvested: 450000,
      currentValue: 498000,
      dueDate: DateTime.now().add(const Duration(days: 26)),
      maturityDate: DateTime.now().add(const Duration(days: 365 * 8)),
      frequency: 'Yearly',
      riskLevel: 'Low',
      notes: 'Tax saving investment',
    ),
    InvestmentRecord(
      id: 'inv-04',
      name: 'NIFTY 50 ETF Basket',
      type: 'Equity',
      provider: 'Zerodha',
      amountInvested: 170000,
      currentValue: 162800,
      dueDate: null,
      maturityDate: null,
      frequency: 'One-time',
      riskLevel: 'High',
      notes: 'Long-term growth portfolio',
    ),
  ];

  List<InvestmentRecord> getInvestments() => List<InvestmentRecord>.unmodifiable(_investments);

  void addInvestment(InvestmentRecord record) {
    _investments.insert(0, record);
  }
}
