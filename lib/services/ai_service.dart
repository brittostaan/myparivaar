import 'dart:convert';
import 'package:http/http.dart' as http;

class AIException implements Exception {
  final String message;
  AIException(this.message);
  
  @override
  String toString() => message;
}

class AIService {
  /// Get weekly AI summary for the household
  Future<Map<String, dynamic>> getWeeklySummary({
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-weeklySummary'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else if (response.statusCode == 429) {
        throw AIException('Weekly summary limit reached. ${data['limit']} summaries per week allowed.');
      } else {
        throw AIException(data['error'] ?? 'Failed to get weekly summary');
      }
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to get weekly summary');
    }
  }

  /// Send a chat message to AI and get response
  Future<Map<String, dynamic>> sendChatMessage({
    required String message,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-chat'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': message,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else if (response.statusCode == 429) {
        final resetDate = data['reset_date'] ?? 'next month';
        throw AIException('Monthly chat limit reached (${data['limit']} questions per month). Resets on $resetDate.');
      } else {
        throw AIException(data['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to send message');
    }
  }

  /// Get AI usage statistics for the current month
  Future<Map<String, dynamic>> getUsageStats({
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-usage'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw AIException(error['error'] ?? 'Failed to get usage stats');
      }
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to get usage stats');
    }
  }
}