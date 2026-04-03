import 'dart:convert';
import 'package:http/http.dart' as http;

String _supabaseAnonKey() =>
    const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpbXFha2ZqcnlwdHloeG1yanNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NDQ3NzQsImV4cCI6MjA4ODQyMDc3NH0.SIySX0aILaLTp08K-TurhhS4dMWl0VqKzgKp3PPFlM0');

String _extractErrorMessage(http.Response response, String fallback) {
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final msg = decoded['error'] ?? decoded['message'] ?? decoded['msg'] ?? decoded['details'];
      if (msg is String && msg.trim().isNotEmpty) {
        return msg.trim();
      }
    }
  } catch (_) {
    // Ignore parse errors and fall back below.
  }

  if (response.body.trim().isNotEmpty) {
    return '$fallback (HTTP ${response.statusCode})';
  }
  return fallback;
}

class EmailAccount {
  final String id;
  final String emailAddress;
  final String provider;
  final DateTime createdAt;
  final bool isActive;

  EmailAccount({
    required this.id,
    required this.emailAddress,
    required this.provider,
    required this.createdAt,
    required this.isActive,
  });

  factory EmailAccount.fromJson(Map<String, dynamic> json) {
    return EmailAccount(
      id: json['id'],
      emailAddress: json['email_address'],
      provider: json['provider'],
      createdAt: DateTime.parse(json['created_at']),
      isActive: json['is_active'] ?? true,
    );
  }
}

class EmailSyncResult {
  final int totalEmailsProcessed;
  final int totalTransactionsFound;
  final List<String> errors;

  EmailSyncResult({
    required this.totalEmailsProcessed,
    required this.totalTransactionsFound,
    required this.errors,
  });

  factory EmailSyncResult.fromJson(Map<String, dynamic> json) {
    return EmailSyncResult(
      totalEmailsProcessed: json['total_emails_processed'] ?? 0,
      totalTransactionsFound: json['total_transactions_found'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}

class EmailService {
  Future<List<EmailAccount>> getEmailAccounts({
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-accounts'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': 'list'}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to get email accounts'),
      );
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => EmailAccount.fromJson(json)).toList();
  }

  Future<String> getEmailConnectUrl({
    required String provider,
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-connectUrl'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'provider': provider,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to get connect URL'),
      );
    }

    final data = jsonDecode(response.body);
    return data['auth_url'];
  }

  Future<void> disconnectEmailAccount({
    required String accountId,
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-accounts'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': 'delete', 'account_id': accountId}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to disconnect account'),
      );
    }
  }

  Future<Map<String, dynamic>> syncEmails({
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-syncNow'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to sync emails'),
      );
    }

    return jsonDecode(response.body);
  }

  // ── Inbox Scanning ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listFolders({
    required String accountId,
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-scanInbox'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': 'list_folders',
        'email_account_id': accountId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to list folders'),
      );
    }

    final data = jsonDecode(response.body);
    return (data['folders'] as List<dynamic>?)
            ?.map((f) => Map<String, dynamic>.from(f as Map))
            .toList() ??
        [];
  }

  Future<Map<String, dynamic>> scanInbox({
    required String accountId,
    required String supabaseUrl,
    required String? idToken,
    List<String>? folderIds,
    bool useAi = true,
    int daysBack = 7,
  }) async {
    if (idToken == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-scanInbox'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': 'scan',
        'email_account_id': accountId,
        if (folderIds != null && folderIds.isNotEmpty) 'folder_ids': folderIds,
        'use_ai': useAi,
        'days_back': daysBack,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to scan inbox'),
      );
    }

    return jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> getScanHistory({
    required String accountId,
    required String supabaseUrl,
    required String? idToken,
  }) async {
    if (idToken == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/email-scanInbox'),
      headers: {
        'apikey': _supabaseAnonKey(),
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': 'scan_history',
        'email_account_id': accountId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to fetch scan history'),
      );
    }

    final data = jsonDecode(response.body);
    return (data['scans'] as List<dynamic>?)
            ?.map((s) => Map<String, dynamic>.from(s as Map))
            .toList() ??
        [];
  }
}