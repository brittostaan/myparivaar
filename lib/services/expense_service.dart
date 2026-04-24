import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/expense.dart';

String _supabaseAnonKey() {
  const key = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'MISSING_SUPABASE_ANON_KEY');
  if (key == 'MISSING_SUPABASE_ANON_KEY') {
    throw Exception(
      'SUPABASE_ANON_KEY environment variable is not set. '
      'Please provide it at compile time: '
      'flutter build ... --dart-define=SUPABASE_ANON_KEY=<your-anon-key>'
    );
  }
  return key;
}

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
      // Send filters in the JSON body (the Edge Function reads from body,
      // not from URL query params). Default limit 500 to show all imported rows.
      final bodyParams = <String, dynamic>{
        'limit': limit ?? 1000,
      };
      if (category != null) bodyParams['category'] = category;
      if (startDate != null) bodyParams['start_date'] = startDate;
      if (endDate != null) bodyParams['end_date'] = endDate;

      final uri = Uri.parse('$supabaseUrl/functions/v1/expense-list');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': _supabaseAnonKey(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyParams),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Validate expenses is a list before casting
        if (data['expenses'] is! List) {
          throw ExpenseException(
            'Invalid response: expenses field is not a list',
            statusCode: 200,
            rawBody: response.body,
            url: uri.toString(),
          );
        }
        
        // Filter to only valid map items and safely deserialize
        final expenses = (data['expenses'] as List)
            .whereType<Map<String, dynamic>>()
            .map((expense) {
              try {
                return Expense.fromJson(expense);
              } catch (e) {
                debugPrint('[ExpenseService] Malformed expense item: $expense, Error: $e');
                return null;
              }
            })
            .whereType<Expense>()
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