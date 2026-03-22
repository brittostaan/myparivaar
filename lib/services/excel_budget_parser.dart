import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

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
/// Uses archive + xml directly to avoid the excel package's numFmtId bug.
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
    // xlsx is a zip archive — extract it
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find shared strings (cell text values are stored here)
    final sharedStrings = _parseSharedStrings(archive);

    // Find the first worksheet (usually xl/worksheets/sheet1.xml)
    final sheetFile = archive.files.firstWhere(
      (f) => f.name.contains('worksheets/sheet') && f.name.endsWith('.xml'),
      orElse: () => throw const FormatException('No worksheet found in Excel file'),
    );
    final sheetXml = XmlDocument.parse(String.fromCharCodes(sheetFile.content as List<int>));

    // Parse all rows from the sheet
    final ns = sheetXml.rootElement.name.namespaceUri;
    final sheetData = sheetXml.rootElement.findAllElements('sheetData', namespace: ns).first;
    final xmlRows = sheetData.findAllElements('row', namespace: ns).toList();

    if (xmlRows.isEmpty) {
      throw const FormatException('Excel sheet is empty');
    }

    // Convert XML rows into List<List<String>>
    final allRows = <List<String>>[];
    for (final xmlRow in xmlRows) {
      final cells = xmlRow.findAllElements('c', namespace: ns);
      final rowValues = <String>[];
      int lastCol = 0;
      for (final cell in cells) {
        final ref = cell.getAttribute('r') ?? '';
        final colIndex = _colRefToIndex(ref);
        // Fill gaps with empty strings
        while (rowValues.length < colIndex) {
          rowValues.add('');
        }
        final value = _getCellValue(cell, sharedStrings, ns);
        rowValues.add(value);
        lastCol = colIndex;
      }
      allRows.add(rowValues);
    }

    if (allRows.isEmpty) {
      throw const FormatException('Excel sheet is empty');
    }

    // Auto-detect header row (search first 10 rows)
    int headerRowIndex = -1;
    int? categoryCol;
    int? amountCol;

    for (var i = 0; i < allRows.length && i < 10; i++) {
      final row = allRows[i];
      for (var j = 0; j < row.length; j++) {
        final cellValue = row[j].toLowerCase().trim();
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

    for (var i = dataStartRow; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((cell) => cell.trim().isEmpty)) {
        continue; // skip empty rows
      }

      final rawCategory = (categoryCol < row.length ? row[categoryCol].trim() : '');
      final rawAmount = amountCol < row.length ? row[amountCol].trim() : '';

      if (rawCategory.isEmpty && rawAmount.isEmpty) {
        continue; // skip fully empty data rows
      }

      // Parse amount – strip currency symbols and commas
      final cleanAmount = rawAmount.replaceAll(RegExp(r'[₹$,Rs\s]'), '');
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
          validationError: 'Invalid amount: ${rawAmount.isEmpty ? "empty" : rawAmount}',
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

  /// Parse shared strings from xl/sharedStrings.xml
  static List<String> _parseSharedStrings(Archive archive) {
    final ssFile = archive.files.cast<ArchiveFile?>().firstWhere(
      (f) => f!.name.contains('sharedStrings'),
      orElse: () => null,
    );
    if (ssFile == null) return [];

    final doc = XmlDocument.parse(String.fromCharCodes(ssFile.content as List<int>));
    final ns = doc.rootElement.name.namespaceUri;
    return doc.rootElement.findAllElements('si', namespace: ns).map((si) {
      // Handle both simple <t> and rich text <r><t>...</t></r>
      final parts = si.findAllElements('t', namespace: ns);
      return parts.map((t) => t.innerText).join();
    }).toList();
  }

  /// Get the string value of a cell element
  static String _getCellValue(XmlElement cell, List<String> sharedStrings, String? ns) {
    final type = cell.getAttribute('t');
    final vElement = cell.findAllElements('v', namespace: ns).firstOrNull;
    if (vElement == null) return '';

    final raw = vElement.innerText;
    if (type == 's') {
      // Shared string reference
      final idx = int.tryParse(raw);
      if (idx != null && idx < sharedStrings.length) {
        return sharedStrings[idx];
      }
      return '';
    }
    // Inline string
    if (type == 'inlineStr') {
      final is_ = cell.findAllElements('is', namespace: ns).firstOrNull;
      if (is_ != null) {
        return is_.findAllElements('t', namespace: ns).map((t) => t.innerText).join();
      }
    }
    // Number or other — return raw value
    return raw;
  }

  /// Convert Excel column reference (e.g. "B5") to 0-based column index
  static int _colRefToIndex(String ref) {
    var col = 0;
    for (var i = 0; i < ref.length; i++) {
      final ch = ref.codeUnitAt(i);
      if (ch >= 65 && ch <= 90) {
        // A-Z
        col = col * 26 + (ch - 64);
      } else {
        break;
      }
    }
    return col - 1; // 0-based
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
