import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bill.dart';

enum BillErrorType {
  authExpired,
  authInvalid,
  notFound,
  serverError,
  networkError,
  unknown,
}

class BillException implements Exception {
  final String message;
  final BillErrorType type;
  final int? statusCode;

  const BillException(
    this.message, {
    this.type = BillErrorType.unknown,
    this.statusCode,
  });

  @override
  String toString() => message;
}

BillErrorType _classifyHttpError(int statusCode) {
  if (statusCode == 401) return BillErrorType.authExpired;
  if (statusCode == 404) return BillErrorType.notFound;
  if (statusCode >= 500) return BillErrorType.serverError;
  return BillErrorType.unknown;
}

class BillService {
  Future<List<Bill>> getBills({
    required String supabaseUrl,
    required String idToken,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'bills-list',
      body: {},
    );

    final rows = (response['bills'] as List<dynamic>? ?? []);
    return rows
        .map((row) => Bill.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Bill> upsertBill({
    required String supabaseUrl,
    required String idToken,
    String? id,
    required String name,
    String? provider,
    required BillCategory category,
    required BillFrequency frequency,
    required double amount,
    required DateTime dueDate,
    required bool isRecurring,
    String? notes,
    List<String>? tags,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'category': Bill.categoryKey(category),
      'frequency': Bill.frequencyKey(frequency),
      'amount': amount,
      'due_date':
          '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
      'is_recurring': isRecurring,
    };

    if (id != null) body['id'] = id;
    if (provider != null && provider.trim().isNotEmpty) {
      body['provider'] = provider.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) {
      body['notes'] = notes.trim();
    }
    if (tags != null) {
      body['tags'] = tags;
    }

    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'bills-upsert',
      body: body,
    );

    final bill = response['bill'] as Map<String, dynamic>?;
    if (bill == null) {
      throw const BillException('Invalid bill response from server');
    }
    return Bill.fromJson(bill);
  }

  Future<void> deleteBill({
    required String supabaseUrl,
    required String idToken,
    required String billId,
  }) async {
    await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'bills-delete',
      body: {'bill_id': billId},
    );
  }

  Future<Bill> setPaidStatus({
    required String supabaseUrl,
    required String idToken,
    required String billId,
    required bool isPaid,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'bills-mark-paid',
      body: {
        'bill_id': billId,
        'is_paid': isPaid,
      },
    );

    final bill = response['bill'] as Map<String, dynamic>?;
    if (bill == null) {
      throw const BillException('Invalid bill response from server');
    }
    return Bill.fromJson(bill);
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

      throw BillException(
        data['error'] as String? ??
            data['message'] as String? ??
            'Request failed [HTTP ${response.statusCode}]',
        type: _classifyHttpError(response.statusCode),
        statusCode: response.statusCode,
      );
    } catch (e) {
      if (e is BillException) rethrow;
      throw const BillException(
        'Network error: could not reach the server.',
        type: BillErrorType.networkError,
      );
    }
  }
}
