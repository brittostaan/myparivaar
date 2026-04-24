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
    try {
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
    } catch (e) {
      // Budget functions not yet deployed; return empty list
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        return [];
      }
      rethrow;
    }
  }

  Future<Budget> upsertBudget({
    required String supabaseUrl,
    required String idToken,
    required String category,
    required double amount,
    required String month,
    List<String>? tags,
  }) async {
    try {
      final response = await _post(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
        functionName: 'budget-upsert',
        body: {
          'category': category,
          'amount': amount,
          'month': month,
          'tags': tags,
        },
      );

      final budget = response['budget'] as Map<String, dynamic>?;
      if (budget == null) {
        throw const BudgetException('Invalid budget response from server');
      }
      return Budget.fromJson(budget);
    } catch (e) {
      // Budget functions not yet deployed; throw helpful error
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        throw const BudgetException('Budget management coming soon - feature not yet available');
      }
      rethrow;
    }
  }

  Future<void> deleteBudget({
    required String supabaseUrl,
    required String idToken,
    required String budgetId,
  }) async {
    try {
      await _post(
        supabaseUrl: supabaseUrl,
        idToken: idToken,
        functionName: 'budget-delete',
        body: {'budget_id': budgetId},
      );
    } catch (e) {
      // Budget functions not yet deployed; throw helpful error
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        throw const BudgetException('Budget management coming soon - feature not yet available');
      }
      rethrow;
    }
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
        data['error'] as String? ??
            data['message'] as String? ??
            'Budget request failed [HTTP ${response.statusCode}]: ${response.body}',
        statusCode: response.statusCode,
        rawBody: response.body,
      );
    } catch (e) {
      if (e is BudgetException) rethrow;
      throw BudgetException('Network error: $e');
    }
  }
}
