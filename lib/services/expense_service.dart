import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/expense.dart';

String _supabaseAnonKey() =>
    const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpbXFha2ZqcnlwdHloeG1yanNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NDQ3NzQsImV4cCI6MjA4ODQyMDc3NH0.SIySX0aILaLTp08K-TurhhS4dMWl0VqKzgKp3PPFlM0');

class ExpenseException implements Exception {
  final String message;
  final int? statusCode;
  final String? rawBody;
  final String? url;

  ExpenseException(this.message, {this.statusCode, this.rawBody, this.url});

  String get diagnostics {
    final parts = <String>[];
    if (url != null) parts.add('URL: $url');
    if (statusCode != null) parts.add('HTTP Status: $statusCode');
    parts.add('Error: $message');
    if (rawBody != null && rawBody!.isNotEmpty) parts.add('Response: $rawBody');
    return parts.join('\n');
  }

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
          'apikey': _supabaseAnonKey(),
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
        String errorMsg = 'Failed to load expenses';
        String debugInfo = '';
        try {
          final error = jsonDecode(response.body);
          errorMsg = error['error'] ?? errorMsg;
          if (error['debug'] != null) {
            debugInfo = '\nDEBUG: ${jsonEncode(error['debug'])}';
          }
        } catch (_) {}
        debugPrint('=== expense-list FAILED ===');
        debugPrint('URL: $uri');
        debugPrint('Status: ${response.statusCode}');
        debugPrint('Body: ${response.body}');
        debugPrint('==========================');
        throw ExpenseException(
          errorMsg,
          statusCode: response.statusCode,
          rawBody: '${response.body}$debugInfo',
          url: uri.toString(),
        );
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      debugPrint('=== expense-list EXCEPTION ===\n$e\n==============================');
      throw ExpenseException(
        'Network/parse error: $e',
        url: '$supabaseUrl/functions/v1/expense-list',
      );
    }
  }

  /// Create a new expense
  Future<Expense> createExpense({
    required double amount,
    required String category,
    required String description,
    required DateTime date,
    String? notes,
    List<String>? tags,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-create'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': _supabaseAnonKey(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': amount,
          'category': category,
          'description': description,
          'date': date.toIso8601String().split('T')[0], // Date only
          'notes': notes,
          'tags': tags,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Expense.fromJson(data['expense']);
      } else {
        try {
          final error = jsonDecode(response.body);
          final msg = error['error'] ?? error['message'] ?? error['msg'] ?? response.body;
          throw ExpenseException(
            '$msg (HTTP ${response.statusCode})',
            statusCode: response.statusCode,
            rawBody: response.body,
            url: '$supabaseUrl/functions/v1/expense-create',
          );
        } catch (e) {
          if (e is ExpenseException) rethrow;
          throw ExpenseException(
            'HTTP ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
            rawBody: response.body,
            url: '$supabaseUrl/functions/v1/expense-create',
          );
        }
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException(
        'Network error: Unable to create expense: $e',
        url: '$supabaseUrl/functions/v1/expense-create',
      );
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
    List<String>? tags,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/expense-update'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': _supabaseAnonKey(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'expense_id': expenseId,
          'amount': amount,
          'category': category,
          'description': description,
          'date': date.toIso8601String().split('T')[0], // Date only
          'notes': notes,
          'tags': tags,
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
          'apikey': _supabaseAnonKey(),
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
          'apikey': _supabaseAnonKey(),
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
          'apikey': _supabaseAnonKey(),
        },
        body: jsonEncode({
          'expense_id': expenseId,
          'action': 'approve',
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

  /// Reject email-sourced transactions
  Future<void> rejectTransaction({
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
          'apikey': _supabaseAnonKey(),
        },
        body: jsonEncode({
          'expense_id': expenseId,
          'action': 'reject',
        }),
      );

      if (response.statusCode == 200) {
        return;
      } else {
        final error = jsonDecode(response.body);
        throw ExpenseException(error['error'] ?? 'Failed to reject transaction');
      }
    } catch (e) {
      if (e is ExpenseException) rethrow;
      throw ExpenseException('Network error: Unable to reject transaction');
    }
  }
}