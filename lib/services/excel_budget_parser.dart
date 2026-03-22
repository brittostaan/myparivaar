import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A single row parsed from an Excel budget file.
class BudgetRow {
  final String category;
  final String subcategory;
  final double amount;
  final bool isValid;
  final String? validationError;

  const BudgetRow({
    required this.category,
    this.subcategory = '',
    required this.amount,
    this.isValid = true,
    this.validationError,
  });
}

/// Parses .xlsx files and extracts budget line items.
/// Handles grouped column layouts where each column group has a category header
/// with item names and amounts underneath.
class ExcelBudgetParser {
  /// Parse an Excel file from raw bytes and return budget rows.
  /// Detects grouped columns: each header cell is a category, items below are
  /// subcategories with amounts in the adjacent column.
  List<BudgetRow> parseExcelFile(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _parseSharedStrings(archive);

    final sheetFile = archive.files.firstWhere(
      (f) => f.name.contains('worksheets/sheet') && f.name.endsWith('.xml'),
      orElse: () =>
          throw const FormatException('No worksheet found in Excel file'),
    );
    final sheetXml = XmlDocument.parse(
        String.fromCharCodes(sheetFile.content as List<int>));

    final ns = sheetXml.rootElement.name.namespaceUri;
    final sheetData =
        sheetXml.rootElement.findAllElements('sheetData', namespace: ns).first;
    final xmlRows = sheetData.findAllElements('row', namespace: ns).toList();

    if (xmlRows.isEmpty) {
      throw const FormatException('Excel sheet is empty');
    }

    // Build a dense grid: List<List<String>>
    final allRows = _buildGrid(xmlRows, sharedStrings, ns);
    if (allRows.isEmpty) {
      throw const FormatException('Excel sheet is empty');
    }

    // Detect layout: grouped columns vs simple 2-column
    final headerRow = allRows.first;
    final columnGroups = _detectColumnGroups(allRows);

    if (columnGroups.isNotEmpty) {
      return _parseGroupedColumns(allRows, columnGroups);
    }

    // Fallback: simple 2-column layout (category, amount)
    return _parseSimpleLayout(allRows);
  }

  /// Detect column groups from the header row.
  /// A "group" is a text header followed by an amount column.
  /// E.g., the Excel has: [household, amount, classes, amount, savings, amount, others, amount]
  /// Each group = (headerCol, amountCol, categoryName)
  static List<_ColumnGroup> _detectColumnGroups(List<List<String>> allRows) {
    if (allRows.length < 2) return [];
    final headerRow = allRows.first;
    final groups = <_ColumnGroup>[];

    // Strategy: scan header row for text cells. Each text header that has
    // numeric values in rows below (in the same or next column) is a group.
    for (var col = 0; col < headerRow.length; col++) {
      final headerText = headerRow[col].trim();
      if (headerText.isEmpty) continue;

      // Skip if this looks like a numeric value rather than a header
      if (_isNumeric(headerText)) continue;

      // Find which column has the amounts: same column or next column
      int amountCol = -1;

      // Check if the next column has numeric data (paired text+amount layout)
      if (col + 1 < headerRow.length) {
        final nextHeader = headerRow[col + 1].trim();
        // Next column is empty/numeric header → amounts are there
        if (nextHeader.isEmpty || _isNumeric(nextHeader)) {
          // Verify: check a few data rows for numbers in col+1
          int numericCount = 0;
          for (var r = 1; r < allRows.length && r < 6; r++) {
            if (col + 1 < allRows[r].length &&
                _isNumeric(allRows[r][col + 1].trim())) {
              numericCount++;
            }
          }
          if (numericCount > 0) {
            amountCol = col + 1;
          }
        }
      }

      // Alternatively: check if amounts are in the same column as text
      // (items in col, amounts in col — unlikely but handle it)
      if (amountCol == -1) {
        // Check if data rows in this column are numeric
        int numericCount = 0;
        for (var r = 1; r < allRows.length && r < 6; r++) {
          if (col < allRows[r].length && _isNumeric(allRows[r][col].trim())) {
            numericCount++;
          }
        }
        if (numericCount > 0) continue; // This col is itself an amount column
      }

      if (amountCol != -1) {
        groups.add(_ColumnGroup(
          nameCol: col,
          amountCol: amountCol,
          category: headerText,
        ));
      }
    }

    return groups;
  }

  /// Parse grouped columns layout (e.g., household | amount | classes | amount | ...)
  static List<BudgetRow> _parseGroupedColumns(
      List<List<String>> allRows, List<_ColumnGroup> groups) {
    final results = <BudgetRow>[];

    for (var rowIdx = 1; rowIdx < allRows.length; rowIdx++) {
      final row = allRows[rowIdx];

      for (final group in groups) {
        final itemName =
            group.nameCol < row.length ? row[group.nameCol].trim() : '';
        final rawAmount =
            group.amountCol < row.length ? row[group.amountCol].trim() : '';

        if (itemName.isEmpty && rawAmount.isEmpty) continue;

        final cleanAmount = rawAmount.replaceAll(RegExp(r'[₹$,Rs\s]'), '');
        final amount = double.tryParse(cleanAmount);

        if (itemName.isEmpty) {
          // Amount exists but no item name — skip silently (aggregate rows, etc.)
          continue;
        }

        if (amount == null || amount <= 0) {
          results.add(BudgetRow(
            category: group.category,
            subcategory: itemName,
            amount: 0,
            isValid: false,
            validationError:
                'Invalid amount: ${rawAmount.isEmpty ? "empty" : rawAmount}',
          ));
          continue;
        }

        results.add(BudgetRow(
          category: group.category,
          subcategory: itemName,
          amount: amount,
        ));
      }
    }

    return results;
  }

  /// Fallback: simple layout with category and amount columns
  static List<BudgetRow> _parseSimpleLayout(List<List<String>> allRows) {
    int headerRowIndex = -1;
    int? categoryCol;
    int? amountCol;

    for (var i = 0; i < allRows.length && i < 10; i++) {
      final row = allRows[i];
      for (var j = 0; j < row.length; j++) {
        final cellValue = row[j].toLowerCase().trim();
        if (cellValue.contains('category') ||
            cellValue.contains('item') ||
            cellValue.contains('description') ||
            cellValue.contains('expense') ||
            cellValue.contains('type')) {
          categoryCol = j;
          headerRowIndex = i;
        }
        if (cellValue.contains('amount') ||
            cellValue.contains('budget') ||
            cellValue.contains('planned') ||
            cellValue.contains('cost') ||
            cellValue.contains('value')) {
          amountCol = j;
          headerRowIndex = i;
        }
      }
      if (categoryCol != null && amountCol != null) break;
    }

    categoryCol ??= 0;
    amountCol ??= 1;
    final dataStartRow = headerRowIndex == -1 ? 0 : headerRowIndex + 1;
    final results = <BudgetRow>[];

    for (var i = dataStartRow; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;

      final rawCategory =
          categoryCol < row.length ? row[categoryCol].trim() : '';
      final rawAmount = amountCol < row.length ? row[amountCol].trim() : '';

      if (rawCategory.isEmpty && rawAmount.isEmpty) continue;

      final cleanAmount = rawAmount.replaceAll(RegExp(r'[₹$,Rs\s]'), '');
      final amount = double.tryParse(cleanAmount);

      if (rawCategory.isEmpty) continue;

      if (amount == null || amount <= 0) {
        results.add(BudgetRow(
          category: rawCategory,
          amount: 0,
          isValid: false,
          validationError:
              'Invalid amount: ${rawAmount.isEmpty ? "empty" : rawAmount}',
        ));
        continue;
      }

      results.add(BudgetRow(
        category: rawCategory,
        amount: amount,
      ));
    }

    return results;
  }

  /// Build a dense grid from XML rows
  static List<List<String>> _buildGrid(
      List<XmlElement> xmlRows, List<String> sharedStrings, String? ns) {
    final allRows = <List<String>>[];
    for (final xmlRow in xmlRows) {
      final cells = xmlRow.findAllElements('c', namespace: ns);
      final rowValues = <String>[];
      for (final cell in cells) {
        final ref = cell.getAttribute('r') ?? '';
        final colIndex = _colRefToIndex(ref);
        while (rowValues.length < colIndex) {
          rowValues.add('');
        }
        rowValues.add(_getCellValue(cell, sharedStrings, ns));
      }
      allRows.add(rowValues);
    }
    return allRows;
  }

  static bool _isNumeric(String s) {
    if (s.isEmpty) return false;
    final cleaned = s.replaceAll(RegExp(r'[₹$,Rs\s]'), '');
    return double.tryParse(cleaned) != null;
  }

  /// Parse shared strings from xl/sharedStrings.xml
  static List<String> _parseSharedStrings(Archive archive) {
    final ssFile = archive.files.cast<ArchiveFile?>().firstWhere(
          (f) => f!.name.contains('sharedStrings'),
          orElse: () => null,
        );
    if (ssFile == null) return [];

    final doc = XmlDocument.parse(
        String.fromCharCodes(ssFile.content as List<int>));
    final ns = doc.rootElement.name.namespaceUri;
    return doc.rootElement.findAllElements('si', namespace: ns).map((si) {
      final parts = si.findAllElements('t', namespace: ns);
      return parts.map((t) => t.innerText).join();
    }).toList();
  }

  static String _getCellValue(
      XmlElement cell, List<String> sharedStrings, String? ns) {
    final type = cell.getAttribute('t');
    final vElement = cell.findAllElements('v', namespace: ns).firstOrNull;
    if (vElement == null) return '';

    final raw = vElement.innerText;
    if (type == 's') {
      final idx = int.tryParse(raw);
      if (idx != null && idx < sharedStrings.length) {
        return sharedStrings[idx];
      }
      return '';
    }
    if (type == 'inlineStr') {
      final is_ = cell.findAllElements('is', namespace: ns).firstOrNull;
      if (is_ != null) {
        return is_
            .findAllElements('t', namespace: ns)
            .map((t) => t.innerText)
            .join();
      }
    }
    return raw;
  }

  static int _colRefToIndex(String ref) {
    var col = 0;
    for (var i = 0; i < ref.length; i++) {
      final ch = ref.codeUnitAt(i);
      if (ch >= 65 && ch <= 90) {
        col = col * 26 + (ch - 64);
      } else {
        break;
      }
    }
    return col - 1;
  }
}

/// Internal helper to represent a column group in the Excel sheet
class _ColumnGroup {
  final int nameCol;
  final int amountCol;
  final String category;

  const _ColumnGroup({
    required this.nameCol,
    required this.amountCol,
    required this.category,
  });
}
