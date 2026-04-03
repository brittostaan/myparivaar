import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/planner_item.dart';

enum FamilyPlannerErrorType {
  authExpired,
  authInvalid,
  notFound,
  serverError,
  networkError,
  unknown,
}

class FamilyPlannerException implements Exception {
  final String message;
  final FamilyPlannerErrorType type;
  final int? statusCode;

  const FamilyPlannerException(
    this.message, {
    this.type = FamilyPlannerErrorType.unknown,
    this.statusCode,
  });

  @override
  String toString() => message;
}

FamilyPlannerErrorType _classifyHttpError(int statusCode) {
  if (statusCode == 401) return FamilyPlannerErrorType.authExpired;
  if (statusCode == 404) return FamilyPlannerErrorType.notFound;
  if (statusCode >= 500) return FamilyPlannerErrorType.serverError;
  return FamilyPlannerErrorType.unknown;
}

class FamilyPlannerService {
  Future<List<PlannerItem>> getItems({
    required String supabaseUrl,
    required String idToken,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'family-planner-list',
      body: {},
    );

    final rows = response['items'] as List<dynamic>? ?? [];
    return rows
        .map((row) => PlannerItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<PlannerItem> upsertItem({
    required String supabaseUrl,
    required String idToken,
    String? id,
    required PlannerItemType type,
    required String title,
    String? description,
    required DateTime startDate,
    DateTime? endDate,
    required bool isAllDay,
    required bool isRecurringYearly,
    required PlannerPriority priority,
    String? location,
  }) async {
    final body = <String, dynamic>{
      'item_type': PlannerItem.typeKey(type),
      'title': title,
      'start_date': _fmtDate(startDate),
      'is_all_day': isAllDay,
      'is_recurring_yearly': isRecurringYearly,
      'priority': PlannerItem.priorityKey(priority),
    };

    if (id != null) body['id'] = id;
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (endDate != null) {
      body['end_date'] = _fmtDate(endDate);
    }
    if (location != null && location.trim().isNotEmpty) {
      body['location'] = location.trim();
    }

    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'family-planner-upsert',
      body: body,
    );

    final item = response['item'] as Map<String, dynamic>?;
    if (item == null) {
      throw const FamilyPlannerException('Invalid planner response from server');
    }

    return PlannerItem.fromJson(item);
  }

  Future<void> deleteItem({
    required String supabaseUrl,
    required String idToken,
    required String itemId,
  }) async {
    await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'family-planner-delete',
      body: {'item_id': itemId},
    );
  }

  Future<PlannerItem> setCompleted({
    required String supabaseUrl,
    required String idToken,
    required String itemId,
    required bool isCompleted,
  }) async {
    final response = await _post(
      supabaseUrl: supabaseUrl,
      idToken: idToken,
      functionName: 'family-planner-status',
      body: {'item_id': itemId, 'is_completed': isCompleted},
    );

    final item = response['item'] as Map<String, dynamic>?;
    if (item == null) {
      throw const FamilyPlannerException('Invalid planner response from server');
    }

    return PlannerItem.fromJson(item);
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

      throw FamilyPlannerException(
        data['error'] as String? ??
            data['message'] as String? ??
            'Request failed [HTTP ${response.statusCode}]',
        type: _classifyHttpError(response.statusCode),
        statusCode: response.statusCode,
      );
    } catch (e) {
      if (e is FamilyPlannerException) rethrow;
      throw const FamilyPlannerException(
        'Network error: could not reach the server.',
        type: FamilyPlannerErrorType.networkError,
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
