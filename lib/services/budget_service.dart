import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/budget.dart';

class BudgetException implements Exception {
  final String message;
  final int? statusCode;
  final String? rawBody;

  const BudgetException(
    this.message, {
    this.statusCode,
    this.rawBody,
  });

  @override
  String toString() => message;
}

class BudgetService {
  Future<List<Budget>> getBudgets({
    required String supabaseUrl,
    required String idToken,
    required String month,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'budget-list',
      body: {'month': month},
    );

    final rows = (response['budgets'] as List<dynamic>? ?? []);
    return rows
        .map((row) => Budget.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Budget> upsertBudget({
    required String supabaseUrl,
    required String idToken,
    required String category,
    required double amount,
    required String month,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'budget-upsert',
      body: {
        'category': category,
        'amount': amount,
        'month': month,
      },
    );

    final budget = response['budget'] as Map<String, dynamic>?;
    if (budget == null) {
      throw const BudgetException('Invalid budget response from server');
    }
    return Budget.fromJson(budget);
  }

  Future<void> deleteBudget({
    required String supabaseUrl,
    required String idToken,
    required String budgetId,
  }) async {
    await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'budget-delete',
      body: {'budget_id': budgetId},
    );
  }

  Future<Map<String, dynamic>> _post({
    required String supabaseUrl,
    required String idToken,
    required String functionName,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$supabaseUrl/functions/v1/$functionName');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      Map<String, dynamic> data = {};
      if (response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      }

      throw BudgetException(
        data['error'] as String? ?? 'Budget request failed',
        statusCode: response.statusCode,
        rawBody: response.body,
      );
    } catch (e) {
      if (e is BudgetException) rethrow;
      throw BudgetException('Network error: $e');
    }
  }
}
