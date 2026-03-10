import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/import_result.dart';
import 'auth_service.dart';

/// Thrown by [ImportService] for all API-level failures.
class ImportException implements Exception {
  const ImportException(this.message, {this.errors});

  final String         message;
  final List<RowError>? errors;

  @override
  String toString() => 'ImportException: $message';
}

/// Calls the import-csv Supabase Edge Function for preview and commit actions.
class ImportService {
  ImportService({
    required String supabaseUrl,
    required AuthService authService,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl.replaceAll(RegExp(r'/$'), ''),
        _authService = authService,
        _http = httpClient ?? http.Client();

  final String       _supabaseUrl;
  final AuthService  _authService;
  final http.Client  _http;

  /// Validates the CSV server-side without writing anything to the database.
  /// Returns row-level validation results.
  Future<ImportPreviewResult> preview({
    required String type,
    required String csvText,
  }) async {
    final data = await _call(
      action:  'preview',
      type:    type,
      csvText: csvText,
    );
    return ImportPreviewResult.fromJson(data);
  }

  /// Commits a validated CSV. All rows must be clean (no errors).
  /// Returns the number of rows imported and the batch id.
  Future<ImportCommitResult> commit({
    required String type,
    required String csvText,
  }) async {
    final data = await _call(
      action:  'commit',
      type:    type,
      csvText: csvText,
    );
    return ImportCommitResult.fromJson(data);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call({
    required String action,
    required String type,
    required String csvText,
  }) async {
    if (!_authService.isLoggedIn) {
      throw const ImportException('Not authenticated.');
    }

    final idToken = await _authService.getIdToken(true);

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_supabaseUrl/functions/v1/import-csv'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'type': type, 'action': action, 'csv': csvText}),
      );
    } catch (_) {
      throw const ImportException('Network error: unable to reach the server.');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ImportException('Unexpected response from server.');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }

    // 422 = validation errors on commit — attach row errors for display
    if (response.statusCode == 422) {
      final errors = (data['errors'] as List?)
          ?.map((e) => RowError.fromJson(e as Map<String, dynamic>))
          .toList();
      throw ImportException(
        data['error'] as String? ?? 'Validation errors found.',
        errors: errors,
      );
    }

    throw ImportException(data['error'] as String? ?? 'Import failed.');
  }
}
