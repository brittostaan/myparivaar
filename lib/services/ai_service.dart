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

  /// Auto-categorize a transaction description using AI
  Future<Map<String, dynamic>> categorizeExpense({
    required String description,
    double? amount,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-categorize'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'description': description,
          if (amount != null) 'amount': amount,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      throw AIException(data['error'] ?? 'Failed to categorize expense');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to categorize expense');
    }
  }

  /// Batch-categorize budget items using AI.
  /// Returns a list of {category, confidence} maps, one per input item.
  Future<List<Map<String, String>>> categorizeBudgetItems({
    required List<Map<String, dynamic>> items,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-categorize'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'items': items}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['categories'] != null) {
        return (data['categories'] as List)
            .map((c) => <String, String>{
                  'category': (c['category'] ?? 'other').toString(),
                  'confidence': (c['confidence'] ?? 'low').toString(),
                })
            .toList();
      }
      throw AIException(data['error'] ?? 'Failed to categorize items');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to categorize budget items');
    }
  }

  /// Get AI-driven budget analysis and suggestions
  Future<Map<String, dynamic>> getBudgetAnalysis({
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-budget-analysis'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      if (response.statusCode == 429) {
        throw AIException('Monthly budget analysis limit reached (${data['limit']} per month).');
      }
      throw AIException(data['error'] ?? 'Failed to get budget analysis');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to get budget analysis');
    }
  }

  /// Process voice transcription via AI to extract expense details
  Future<Map<String, dynamic>> processVoiceText({
    required String transcription,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-voice-process'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'transcription': transcription}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      throw AIException(data['error'] ?? 'Failed to process voice text');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to process voice text');
    }
  }

  /// Parse a bank email to extract transaction data
  Future<Map<String, dynamic>> parseEmail({
    required String emailBody,
    String? emailSubject,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-email-parse'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email_body': emailBody,
          if (emailSubject != null) 'email_subject': emailSubject,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      throw AIException(data['error'] ?? 'Failed to parse email');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to parse email');
    }
  }

  /// Detect anomalies in spending patterns
  Future<Map<String, dynamic>> detectAnomalies({
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-anomaly-detect'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      if (response.statusCode == 429) {
        throw AIException('Monthly anomaly detection limit reached (${data['limit']} per month).');
      }
      throw AIException(data['error'] ?? 'Failed to detect anomalies');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to detect anomalies');
    }
  }

  /// Run a financial simulation / what-if scenario
  Future<Map<String, dynamic>> runFinancialSimulation({
    required double monthlyIncome,
    required double monthlyExpenses,
    double monthlySavings = 0,
    int scenarioMonths = 6,
    double expenseChangePct = 0,
    double incomeChangePct = 0,
    required String supabaseUrl,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ai-financial-simulator'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'monthly_income': monthlyIncome,
          'monthly_expenses': monthlyExpenses,
          'monthly_savings': monthlySavings,
          'scenario_months': scenarioMonths,
          'expense_change_pct': expenseChangePct,
          'income_change_pct': incomeChangePct,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data;
      if (response.statusCode == 429) {
        throw AIException('Monthly simulation limit reached (${data['limit']} per month).');
      }
      throw AIException(data['error'] ?? 'Failed to run simulation');
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Network error: Unable to run simulation');
    }
  }
}