import 'dart:async';
import 'package:flutter/foundation.dart';

/// Mock voice recognition service for MVP
/// In production, this would use speech_to_text package or similar
class VoiceService extends ChangeNotifier {
  bool _isListening = false;
  String _lastResult = '';
  Timer? _mockTimer;

  bool get isListening => _isListening;
  String get lastResult => _lastResult;

  /// Simulates starting voice recognition
  Future<void> startListening({
    required Function(String) onResult,
    required Function(String) onError,
  }) async {
    if (_isListening) {
      onError('Already listening');
      return;
    }

    _isListening = true;
    notifyListeners();

    try {
      // Simulate voice recognition delay
      _mockTimer = Timer(const Duration(seconds: 3), () {
        // Mock transcription results for expense entries
        final mockResults = [
          'Spent 150 rupees on groceries at reliance fresh',
          'Paid 500 for electricity bill',
          'Auto rickshaw fare 80 rupees',
          'Restaurant dinner 1200 rupees',
          'Petrol 2000 rupees',
          'Medicine from pharmacy 320 rupees',
          'Coffee 180 rupees',
          'Movie tickets 600 rupees',
        ];

        final result = mockResults[DateTime.now().millisecond % mockResults.length];
        _lastResult = result;
        _isListening = false;
        notifyListeners();
        onResult(result);
      });
    } catch (e) {
      _isListening = false;
      notifyListeners();
      onError('Voice recognition failed: $e');
    }
  }

  /// Stops voice recognition
  void stopListening() {
    _mockTimer?.cancel();
    _mockTimer = null;
    _isListening = false;
    notifyListeners();
  }

  /// Parses voice input to extract expense details
  ExpenseFromVoice? parseExpenseFromVoice(String voiceText) {
    try {
      final text = voiceText.toLowerCase();
      
      // Extract amount — prefer the number closest to (immediately before) a
      // currency keyword so "bought 2 coffees at 150 rupees" captures 150, not 2.
      RegExp amountWithCurrency = RegExp(r'(\d+(?:\.\d{1,2})?)\s*(?:rupees?|rs\.?|inr)');
      RegExp amountAny = RegExp(r'(\d+(?:\.\d{1,2})?)');

      RegExpMatch? amountMatch = amountWithCurrency.firstMatch(text);
      amountMatch ??= amountAny.allMatches(text).lastOrNull;
      if (amountMatch == null) return null;
      
      final amount = double.parse(amountMatch.group(1)!);

      // Extract description (everything except amount and common words)
      String description = text;
      description = description.replaceAll(amountMatch.group(0)!, '');
      description = description.replaceAll(RegExp(r'\b(spent|paid|for|on|at|rupees?|rs\.?|inr)\b'), '');
      description = description.trim();
      description = description.replaceAll(RegExp(r'\s+'), ' ');
      
      if (description.isEmpty) {
        description = 'Voice expense';
      }

      // Determine category based on keywords
      String category = _categorizeFromDescription(description);

      return ExpenseFromVoice(
        amount: amount,
        description: description,
        category: category,
        originalText: voiceText,
      );
    } catch (e) {
      return null;
    }
  }

  String _categorizeFromDescription(String description) {
    final keywords = {
      'Food': ['food', 'restaurant', 'dinner', 'lunch', 'breakfast', 'coffee', 'tea', 'snack', 'meal'],
      'Transport': ['auto', 'taxi', 'bus', 'train', 'metro', 'uber', 'ola', 'rickshaw', 'fuel', 'petrol', 'diesel'],
      'Bills': ['electricity', 'water', 'gas', 'internet', 'phone', 'mobile', 'bill'],
      'Shopping': ['shopping', 'clothes', 'shoes', 'grocery', 'groceries', 'supermarket', 'mall'],
      'Healthcare': ['doctor', 'medicine', 'hospital', 'pharmacy', 'medical', 'health'],
      'Entertainment': ['movie', 'cinema', 'game', 'party', 'entertainment', 'fun'],
    };

    for (final category in keywords.keys) {
      for (final keyword in keywords[category]!) {
        if (description.contains(keyword)) {
          return category;
        }
      }
    }

    return 'Other';
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

class ExpenseFromVoice {
  final double amount;
  final String description;
  final String category;
  final String originalText;

  ExpenseFromVoice({
    required this.amount,
    required this.description,
    required this.category,
    required this.originalText,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'description': description,
      'category': category,
      'originalText': originalText,
    };
  }
}