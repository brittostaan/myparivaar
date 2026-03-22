import 'dart:typed_data';
import 'package:excel/excel.dart';

/// A single row parsed from an Excel budget file.
class BudgetRow {
  final String category;
  final double amount;
  final bool isValid;
  final String? validationError;

  const BudgetRow({
    required this.category,
    required this.amount,
    this.isValid = true,
    this.validationError,
  });
}

/// Parses .xlsx files and extracts budget line items.
class ExcelBudgetParser {
  static const validCategories = [
    'food',
    'transport',
    'utilities',
    'shopping',
    'healthcare',
    'entertainment',
    'other',
  ];

  /// Parse an Excel file from raw bytes and return budget rows.
  /// Auto-detects header row and column mapping.
  List<BudgetRow> parseExcelFile(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('Excel file contains no sheets');
    }

    final sheet = excel.tables[excel.tables.keys.first]!;
    final rows = sheet.rows;
    if (rows.isEmpty) {
      throw const FormatException('Excel sheet is empty');
    }

    // Auto-detect header row (search first 10 rows)
    int headerRowIndex = -1;
    int? categoryCol;
    int? amountCol;

    for (var i = 0; i < rows.length && i < 10; i++) {
      final row = rows[i];
      for (var j = 0; j < row.length; j++) {
        final cellValue = row[j]?.value?.toString().toLowerCase().trim() ?? '';
        if (cellValue.contains('category') || cellValue.contains('item') ||
            cellValue.contains('description') || cellValue.contains('expense') ||
            cellValue.contains('type')) {
          categoryCol = j;
          headerRowIndex = i;
        }
        if (cellValue.contains('amount') || cellValue.contains('budget') ||
            cellValue.contains('planned') || cellValue.contains('cost') ||
            cellValue.contains('value')) {
          amountCol = j;
          headerRowIndex = i;
        }
      }
      if (categoryCol != null && amountCol != null) break;
    }

    // Fallback: assume first column is category, second is amount
    categoryCol ??= 0;
    amountCol ??= 1;
    headerRowIndex = headerRowIndex == -1 ? -1 : headerRowIndex;

    final dataStartRow = headerRowIndex + 1;
    final results = <BudgetRow>[];

    for (var i = dataStartRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell == null || cell.value == null ||
          cell.value.toString().trim().isEmpty)) {
        continue; // skip empty rows
      }

      final rawCategory = (categoryCol < row.length
              ? row[categoryCol]?.value?.toString().trim()
              : null) ??
          '';
      final rawAmount = amountCol < row.length
          ? row[amountCol]?.value?.toString().trim()
          : null;

      if (rawCategory.isEmpty && (rawAmount == null || rawAmount.isEmpty)) {
        continue; // skip fully empty data rows
      }

      // Parse amount – strip currency symbols and commas
      final cleanAmount = (rawAmount ?? '')
          .replaceAll(RegExp(r'[₹$,Rs\s]'), '');
      final amount = double.tryParse(cleanAmount);

      if (rawCategory.isEmpty) {
        results.add(BudgetRow(
          category: '',
          amount: 0,
          isValid: false,
          validationError: 'Missing category',
        ));
        continue;
      }

      if (amount == null || amount <= 0) {
        results.add(BudgetRow(
          category: _mapCategory(rawCategory),
          amount: 0,
          isValid: false,
          validationError: 'Invalid amount: ${rawAmount ?? "empty"}',
        ));
        continue;
      }

      final mappedCategory = _mapCategory(rawCategory);
      results.add(BudgetRow(
        category: mappedCategory,
        amount: amount,
      ));
    }

    return results;
  }

  /// Map a free-text category string to one of the valid budget categories.
  static String _mapCategory(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return 'other';

    const mapping = <String, List<String>>{
      'food': ['food', 'grocery', 'groceries', 'meal', 'dining', 'restaurant',
        'snack', 'breakfast', 'lunch', 'dinner', 'kitchen', 'provisions'],
      'transport': ['transport', 'travel', 'fuel', 'petrol', 'diesel', 'gas',
        'auto', 'cab', 'uber', 'ola', 'bus', 'train', 'metro', 'commute',
        'vehicle', 'car', 'bike', 'parking'],
      'utilities': ['utility', 'utilities', 'electric', 'electricity', 'water',
        'gas', 'internet', 'wifi', 'phone', 'mobile', 'recharge', 'bill',
        'maintenance', 'rent', 'housing', 'emi'],
      'shopping': ['shopping', 'cloth', 'clothes', 'apparel', 'fashion',
        'amazon', 'flipkart', 'online', 'gadget', 'electronics'],
      'healthcare': ['health', 'healthcare', 'medical', 'medicine', 'doctor',
        'hospital', 'pharmacy', 'insurance', 'gym', 'fitness', 'dental'],
      'entertainment': ['entertainment', 'movie', 'netflix', 'subscription',
        'hobby', 'game', 'sport', 'outing', 'party', 'fun', 'leisure'],
    };

    for (final entry in mapping.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }

    return 'other';
  }
}
