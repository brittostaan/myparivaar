import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment.dart';

enum InvestmentErrorType {
  authExpired,
  authInvalid,
  notFound,
  serverError,
  networkError,
  unknown,
}

class InvestmentException implements Exception {
  final String message;
  final InvestmentErrorType type;
  final int? statusCode;

  const InvestmentException(
    this.message, {
    this.type = InvestmentErrorType.unknown,
    this.statusCode,
  });

  @override
  String toString() => message;
}

InvestmentErrorType _classifyHttpError(int statusCode) {
  if (statusCode == 401) return InvestmentErrorType.authExpired;
  if (statusCode == 404) return InvestmentErrorType.notFound;
  if (statusCode >= 500) return InvestmentErrorType.serverError;
  return InvestmentErrorType.unknown;
}

class InvestmentService {
  Future<List<Investment>> getInvestments({
    required String supabaseUrl,
    required String idToken,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'investment-list',
      body: {},
    );

    final rows = response['investments'] as List<dynamic>? ?? [];
    return rows
        .map((row) => Investment.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Investment> upsertInvestment({
    required String supabaseUrl,
    required String idToken,
    String? id,
    required String name,
    required String type,
    String? provider,
    required double amountInvested,
    required double currentValue,
    DateTime? dueDate,
    DateTime? maturityDate,
    required String frequency,
    required InvestmentRiskLevel riskLevel,
    String? notes,
    String? childName,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      'amount_invested': amountInvested,
      'current_value': currentValue,
      'frequency': frequency,
      'risk_level': Investment.riskLevelKey(riskLevel),
    };

    if (id != null) body['id'] = id;
    if (provider != null && provider.trim().isNotEmpty) {
      body['provider'] = provider.trim();
    }
    if (dueDate != null) body['due_date'] = _fmtDate(dueDate);
    if (maturityDate != null) body['maturity_date'] = _fmtDate(maturityDate);
    if (notes != null && notes.trim().isNotEmpty) body['notes'] = notes.trim();
    if (childName != null && childName.trim().isNotEmpty) {
      body['child_name'] = childName.trim();
    }

    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'investment-upsert',
      body: body,
    );

    final investment = response['investment'] as Map<String, dynamic>?;
    if (investment == null) {
      throw const InvestmentException('Invalid investment response from server');
    }

    return Investment.fromJson(investment);
  }

  Future<void> deleteInvestment({
    required String supabaseUrl,
    required String idToken,
    required String investmentId,
  }) async {
    await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'investment-delete',
      body: {'investment_id': investmentId},
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

      throw InvestmentException(
        data['error'] as String? ??
            data['message'] as String? ??
            'Request failed [HTTP ${response.statusCode}]',
        type: _classifyHttpError(response.statusCode),
        statusCode: response.statusCode,
      );
    } catch (e) {
      if (e is InvestmentException) rethrow;
      throw const InvestmentException(
        'Network error: could not reach the server.',
        type: InvestmentErrorType.networkError,
      );
    }
  }

  String _fmtDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
