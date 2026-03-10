import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/expense.dart';

class ExpenseException implements Exception {
  final String message;
  ExpenseException(this.message);
  
  @override
  String toString() => message;
}

class ExpenseService {
  /// Get all expenses for the authenticated user's household
  Future<List<Expense>> getExpenses({
    required String supabaseUrl,
    required String idToken,
    int? limit,
    String? category,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (category != null) queryParams['category'] = category;
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;

      final uri = Uri.parse('$supabaseUrl/functions/v1/expense-list')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final expenses = (data['expenses'] as List)
            .map((expense) => Expense.fromJson(expense))
            .toList();
        return expenses;
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to load expenses');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to load expenses');
    }
  }

  /// Create a new expense
  Future<Expense> createExpense({
    required double amount,
    required String category,
    required String description,
    required DateTime date,
    String? notes,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-create'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': amount,
          'category': category,
          'description': description,
          'date': date.toIso8601String().split('T')[0], // Date only
          'notes': notes,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Expense.fromJson(data['expense']);
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to create expense');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to create expense');
    }
  }

  /// Update an existing expense
  Future<Expense> updateExpense({
    required String expenseId,
    required double amount,
    required String category,
    required String description,
    required DateTime date,
    String? notes,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-update'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'expense_id': expenseId,
          'amount': amount,
          'category': category,
          'description': description,
          'date': date.toIso8601String().split('T')[0], // Date only
          'notes': notes,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Expense.fromJson(data['expense']);
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to update expense');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to update expense');
    }
  }

  /// Delete an expense (soft delete)
  Future<void> deleteExpense({
    required String expenseId,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-delete'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'expense_id': expenseId,
        }),
      );

      if (response.statusCode == 200) {
        // Success
        return;
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to delete expense');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to delete expense');
    }
  }

  /// Get expense statistics for dashboard/insights
  Future<Map<String, dynamic>> getExpenseStats({
    required String supabaseUrl,
    required String idToken,
    String? month,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-stats'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (month != null) 'month': month,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to load expense stats');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to load expense stats');
    }
  }

  /// Approve email-sourced transactions
  Future<void> approveTransaction({
    required String expenseId,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-approve'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'expense_id': expenseId,
        }),
      );

      if (response.statusCode == 200) {
        return;
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to approve transaction');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to approve transaction');
    }
  }
}