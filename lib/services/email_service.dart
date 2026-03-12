import 'dart:convert';
import 'package:http/http.dart' as http;

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

    final response = await http.get(
      Uri.parse('$supabaseUrl/functions/v1/email-accounts'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to get email accounts');
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
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'provider': provider,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to get connect URL');
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

    final response = await http.delete(
      Uri.parse('$supabaseUrl/functions/v1/email-accounts/$accountId'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to disconnect account');
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
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to sync emails');
    }

    return jsonDecode(response.body);
  }
}