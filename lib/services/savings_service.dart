import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/savings_goal.dart';

enum SavingsErrorType {
  /// 401 — Supabase gateway rejected the JWT (expired or invalid)
  authExpired,
  /// 401 — token present but can't be refreshed (refresh token dead)
  authInvalid,
  /// 404 — endpoint or resource not found
  notFound,
  /// 5xx — server-side failure
  serverError,
  /// Network / socket error — no HTTP response received
  networkError,
  /// Any other HTTP error
  unknown,
}

class SavingsException implements Exception {
  final String message;
  final SavingsErrorType type;
  final int? statusCode;
  final String? rawBody;

  const SavingsException(
    this.message, {
    this.type = SavingsErrorType.unknown,
    this.statusCode,
    this.rawBody,
  });

  @override
  String toString() => message;
}

/// Derive the error type from an HTTP status code + raw body.
SavingsErrorType _classifyHttpError(int statusCode, String rawBody) {
  if (statusCode == 401) {
    // Both "expired" and "Invalid JWT" come back as 401 from the Supabase
    // gateway. Treat all 401s as authExpired so the retry loop can try a
    // token refresh. If refresh also fails the caller escalates to authInvalid.
    return SavingsErrorType.authExpired;
  }
  if (statusCode == 404) return SavingsErrorType.notFound;
  if (statusCode >= 500) return SavingsErrorType.serverError;
  return SavingsErrorType.unknown;
}

class SavingsService {
  Future<List<SavingsGoal>> getGoals({
    required String supabaseUrl,
    required String idToken,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'savings-list',
      body: {},
    );

    final rows = (response['goals'] as List<dynamic>? ?? []);
    return rows
        .map((row) => SavingsGoal.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<SavingsGoal> upsertGoal({
    required String supabaseUrl,
    required String idToken,
    String? id,
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'target_amount': targetAmount,
    };
    if (id != null) body['id'] = id;
    if (targetDate != null) {
      body['target_date'] =
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
    }
    if (notes != null && notes.trim().isNotEmpty) body['notes'] = notes.trim();

    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'savings-upsert',
      body: body,
    );

    final goal = response['goal'] as Map<String, dynamic>?;
    if (goal == null) {
      throw const SavingsException('Invalid savings goal response from server');
    }
    return SavingsGoal.fromJson(goal);
  }

  Future<void> deleteGoal({
    required String supabaseUrl,
    required String idToken,
    required String goalId,
  }) async {
    await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'savings-delete',
      body: {'goal_id': goalId},
    );
  }

  /// Adds [amount] to the goal's current_amount (use negative to withdraw).
  Future<SavingsGoal> contribute({
    required String supabaseUrl,
    required String idToken,
    required String goalId,
    required double amount,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'savings-contribute',
      body: {'goal_id': goalId, 'amount': amount},
    );

    final goal = response['goal'] as Map<String, dynamic>?;
    if (goal == null) {
      throw const SavingsException('Invalid savings goal response from server');
    }
    return SavingsGoal.fromJson(goal);
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

      final errorType = _classifyHttpError(response.statusCode, response.body);
      throw SavingsException(
        data['error'] as String? ??
            data['message'] as String? ??
            'Request failed [HTTP ${response.statusCode}]',
        type: errorType,
        statusCode: response.statusCode,
        rawBody: response.body,
      );
    } catch (e) {
      if (e is SavingsException) rethrow;
      throw SavingsException(
        'Network error: could not reach the server.',
        type: SavingsErrorType.networkError,
      );
    }
  }
}
