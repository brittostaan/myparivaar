import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/investment_record.dart';
import 'auth_service.dart';
import 'expense_service.dart';
import 'investment_service.dart';

class SearchResultItem {
  final String id;
  final String title;
  final String subtitle;
  final String amountText;
  final String routeName;
  final String sourceLabel;
  final DateTime? sortDate;
  final IconData icon;
  final List<String> keywords;

  const SearchResultItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amountText,
    required this.routeName,
    required this.sourceLabel,
    required this.sortDate,
    required this.icon,
    required this.keywords,
  });
}

abstract class GlobalSearchSource {
  String get key;

  Future<List<SearchResultItem>> load(AuthService authService);
}

class ExpenseSearchSource implements GlobalSearchSource {
  @override
  String get key => 'expenses';

  @override
  Future<List<SearchResultItem>> load(AuthService authService) async {
    final idToken = await authService.getIdToken();
    final expenses = await ExpenseService().getExpenses(
      supabaseUrl: authService.supabaseUrl,
      idToken: idToken,
      limit: 500,
    );

    return expenses.map(_mapExpense).toList();
  }

  SearchResultItem _mapExpense(Expense expense) {
    final amountText = '₹${expense.amount.toStringAsFixed(2)}';
    final subtitle =
        '${_capitalise(expense.category)} · ${_formatDate(expense.date)}';

    return SearchResultItem(
      id: 'expense:${expense.id}',
      title: expense.description,
      subtitle: subtitle,
      amountText: amountText,
      routeName: '/expenses',
      sourceLabel: 'Expense',
      sortDate: expense.date,
      icon: _iconForCategory(expense.category),
      keywords: [
        expense.description,
        expense.category,
        amountText,
        expense.notes ?? '',
        'expense',
        'transaction',
      ],
    );
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & dining':
        return Icons.restaurant_outlined;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'transport':
        return Icons.directions_car_outlined;
      case 'entertainment':
        return Icons.movie_outlined;
      case 'healthcare':
        return Icons.local_hospital_outlined;
      case 'utilities':
        return Icons.bolt_outlined;
      case 'rent':
      case 'housing':
        return Icons.home_outlined;
      case 'education':
        return Icons.school_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }
}

class InvestmentSearchSource implements GlobalSearchSource {
  @override
  String get key => 'investments';

  @override
  Future<List<SearchResultItem>> load(AuthService authService) async {
    final investments = InvestmentService().getInvestments();
    return investments.map(_mapInvestment).toList();
  }

  SearchResultItem _mapInvestment(InvestmentRecord investment) {
    final amountText = '₹${investment.currentValue.toStringAsFixed(2)}';
    final subtitle =
        '${investment.type} · ${investment.provider.isEmpty ? 'Provider not set' : investment.provider}';

    return SearchResultItem(
      id: 'investment:${investment.id}',
      title: investment.name,
      subtitle: subtitle,
      amountText: amountText,
      routeName: '/investments',
      sourceLabel: 'Investment',
      sortDate: investment.dueDate ?? investment.maturityDate,
      icon: _iconForType(investment.type),
      keywords: [
        investment.name,
        investment.type,
        investment.provider,
        investment.frequency,
        investment.riskLevel,
        investment.notes,
        amountText,
        'investment',
        'portfolio',
      ],
    );
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'insurance':
        return Icons.verified_user_outlined;
      case 'mutual fund':
        return Icons.stacked_line_chart;
      case 'equity':
        return Icons.candlestick_chart;
      case 'fixed deposit':
        return Icons.account_balance_outlined;
      case 'gold':
        return Icons.workspace_premium_outlined;
      case 'retirement':
        return Icons.elderly_outlined;
      default:
        return Icons.pie_chart_outline;
    }
  }
}

class GlobalSearchService {
  GlobalSearchService._();

  static final GlobalSearchService _instance = GlobalSearchService._();

  factory GlobalSearchService() => _instance;

  final List<GlobalSearchSource> _sources = [
    ExpenseSearchSource(),
    InvestmentSearchSource(),
  ];

  void registerSource(GlobalSearchSource source) {
    final exists = _sources.any((s) => s.key == source.key);
    if (!exists) {
      _sources.add(source);
    }
  }

  Future<List<SearchResultItem>> buildIndex(AuthService authService) async {
    final sourceResults = await Future.wait(
      _sources.map((source) async {
        try {
          return await source.load(authService);
        } catch (_) {
          return <SearchResultItem>[];
        }
      }),
    );

    final all = sourceResults.expand((items) => items).toList();
    all.sort((a, b) {
      final aDate = a.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return all;
  }

  List<SearchResultItem> search(
    List<SearchResultItem> index,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final terms = normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final scored = <(SearchResultItem item, int score)>[];

    for (final item in index) {
      final haystack = [item.title, item.subtitle, ...item.keywords]
          .join(' ')
          .toLowerCase();

      var score = 0;
      for (final term in terms) {
        if (item.title.toLowerCase().contains(term)) {
          score += 5;
        }
        if (item.subtitle.toLowerCase().contains(term)) {
          score += 3;
        }
        if (haystack.contains(term)) {
          score += 2;
        }
      }

      if (score > 0) {
        scored.add((item, score));
      }
    }

    scored.sort((a, b) {
      if (b.$2 != a.$2) return b.$2.compareTo(a.$2);
      final aDate = a.$1.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.$1.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return scored.map((pair) => pair.$1).toList(growable: false);
  }
}

String _capitalise(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
