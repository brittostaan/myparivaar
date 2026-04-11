import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xml/xml.dart';
import '../main.dart' show ViewModeProvider, ViewMode;
import '../models/import_result.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/expense_service.dart';
import '../services/family_service.dart';
import '../services/import_service.dart';
import '../models/expense.dart';
import '../models/budget.dart';
import '../widgets/app_header.dart';
import '../widgets/tag_input_section.dart';
import '../widgets/tag_wrap.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/tag_utils.dart';
import '../services/ai_service.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() =>
      _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  final ExpenseService _expenseService = ExpenseService();
  List<Expense> _expenses = [];
  bool _isLoading = true;
  String? _error;
  String? _errorDiagnostics;
  String _searchQuery = '';
  final BudgetService _budgetService = BudgetService();
  List<Budget> _budgets = [];

  // AI Smart Insights
  bool _loadingInsights = false;
  String? _smartInsights;
  String? _smartInsightsError;

  // Web: category filter & inline panels
  String? _selectedCategoryFilter;
  DateTime? _filterStartDate; // date range filter start
  DateTime? _filterEndDate; // date range filter end
  bool _showCalendarDropdown = false; // inline calendar dropdown
  DateTime _calendarDisplayMonth = DateTime(DateTime.now().year, DateTime.now().month); // separate from filter dates
  bool _showAddExpensePanel = false;
  bool _showImportPanel = false;
  bool _showHistoricalPanel = false;
  bool _showAnalyticsPanel = false;
  bool _showAIInsightsPanel = false;
  Expense? _selectedExpenseDetail;
  bool _showLeakageFlip = false; // flip between Projected ↔ Leakage when panel active
  final ScrollController _infoCardScrollController = ScrollController();

  // Compact toolbar state (matches budget screen pattern)
  String _expenseGroupBy = 'none'; // 'none', 'category', 'source'
  bool _expenseSortAscending = false; // false = high→low (default)
  String? _hoveredExpenseId;

  // Inline expense form (matches budget screen pattern)
  Expense? _editingExpense;
  bool _showInlineExpenseForm = false;
  String _formExpenseCategory = 'Groceries';
  final TextEditingController _formExpenseAmountController = TextEditingController();
  final TextEditingController _formExpenseDescController = TextEditingController();
  final TextEditingController _formExpenseTagsController = TextEditingController();

  static const _expenseCategories = [
    'Groceries', 'Entertainment', 'Education', 'Personal Care',
    'Physical Wellness', 'Mental Wellness', 'Convenience Food',
    'Senior Care', 'Pet Care', 'Vacation', 'Party',
  ];

  void _closeAllPanels() {
    _showAddExpensePanel = false;
    _showImportPanel = false;
    _showHistoricalPanel = false;
    _showAnalyticsPanel = false;
    _selectedExpenseDetail = null;
  }

  bool get _anyPanelOpen =>
      _showHistoricalPanel ||
      _showAnalyticsPanel || _selectedExpenseDetail != null;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _infoCardScrollController.dispose();
    _formExpenseAmountController.dispose();
    _formExpenseDescController.dispose();
    _formExpenseTagsController.dispose();
    super.dispose();
  }

  void _openExpenseForm({Expense? existing}) {
    setState(() {
      _editingExpense = existing;
      _showInlineExpenseForm = true;
      _formExpenseCategory = existing?.category ?? _expenseCategories.first;
      _formExpenseAmountController.text = existing == null ? '' : existing.amount.toStringAsFixed(2);
      _formExpenseDescController.text = existing?.description ?? '';
      _formExpenseTagsController.text = joinTags(existing?.tags);
    });
  }

  void _closeExpenseForm() {
    setState(() {
      _showInlineExpenseForm = false;
      _editingExpense = null;
      _formExpenseAmountController.clear();
      _formExpenseDescController.clear();
      _formExpenseTagsController.clear();
    });
  }

  Future<void> _saveExpenseForm() async {
    final amount = double.tryParse(_formExpenseAmountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    final description = _formExpenseDescController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }
    final isEditing = _editingExpense != null;
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      final tags = parseTags(_formExpenseTagsController.text);
      if (isEditing) {
        await _expenseService.updateExpense(
          expenseId: _editingExpense!.id,
          amount: amount,
          category: _formExpenseCategory,
          description: description,
          date: _editingExpense!.date,
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      } else {
        await _expenseService.createExpense(
          amount: amount,
          category: _formExpenseCategory,
          description: description,
          date: DateTime.now(),
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      }
      if (!mounted) return;
      _loadExpenses();
      if (!isEditing) {
        _formExpenseAmountController.clear();
        _formExpenseDescController.clear();
        _formExpenseTagsController.clear();
      } else {
        _closeExpenseForm();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Expense updated' : 'Expense added'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Convert xlsx column reference (e.g. "A1", "B2", "AA3") to 0-based column index.
  static int _colRefToIndex(String cellRef) {
    int col = 0;
    for (int i = 0; i < cellRef.length; i++) {
      final ch = cellRef.codeUnitAt(i);
      if (ch >= 65 && ch <= 90) {
        col = col * 26 + (ch - 64);
      } else {
        break;
      }
    }
    return col - 1;
  }

  /// Parse .xlsx bytes into structured expense rows (description, category, date, amount).
  /// Handles: DD-MM-YYYY dates, ₹-prefixed amounts, Excel date serials.
  static List<_ExpenseEditableRow> _parseExpenseExcel(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Parse shared strings
    final ssFile = archive.files.firstWhere(
      (f) => f.name.contains('sharedStrings'),
      orElse: () => ArchiveFile('empty', 0, []),
    );
    final sharedStrings = <String>[];
    if (ssFile.size > 0) {
      final ssXml = XmlDocument.parse(String.fromCharCodes(ssFile.content as List<int>));
      final ns = ssXml.rootElement.name.namespaceUri;
      for (final si in ssXml.rootElement.findAllElements('si', namespace: ns)) {
        final buf = StringBuffer();
        for (final t in si.findAllElements('t', namespace: ns)) {
          buf.write(t.innerText);
        }
        sharedStrings.add(buf.toString());
      }
    }

    // Parse first worksheet
    final sheetFile = archive.files.firstWhere(
      (f) => f.name.contains('worksheets/sheet') && f.name.endsWith('.xml'),
      orElse: () => throw const FormatException('No worksheet found'),
    );
    final sheetXml = XmlDocument.parse(String.fromCharCodes(sheetFile.content as List<int>));
    final ns = sheetXml.rootElement.name.namespaceUri;
    final sheetData = sheetXml.rootElement.findAllElements('sheetData', namespace: ns).first;
    final xmlRows = sheetData.findAllElements('row', namespace: ns).toList();

    if (xmlRows.isEmpty) throw const FormatException('Excel sheet is empty');

    // Find max column index
    int maxCol = 0;
    for (final row in xmlRows) {
      for (final cell in row.findAllElements('c', namespace: ns)) {
        final ref = cell.getAttribute('r') ?? '';
        final colIdx = _colRefToIndex(ref);
        if (colIdx > maxCol) maxCol = colIdx;
      }
    }

    // Parse all rows into List<List<String>>
    final allRows = <List<String>>[];
    for (final row in xmlRows) {
      final cells = row.findAllElements('c', namespace: ns);
      final values = List<String>.filled(maxCol + 1, '');
      for (final cell in cells) {
        final ref = cell.getAttribute('r') ?? '';
        final colIdx = _colRefToIndex(ref);
        final type = cell.getAttribute('t') ?? '';
        final vElem = cell.findElements('v', namespace: ns);
        final raw = vElem.isNotEmpty ? vElem.first.innerText : '';
        if (type == 's' && raw.isNotEmpty) {
          final idx = int.tryParse(raw) ?? 0;
          values[colIdx] = idx < sharedStrings.length ? sharedStrings[idx] : raw;
        } else {
          values[colIdx] = raw;
        }
      }
      allRows.add(values);
    }

    if (allRows.length < 2) return [];

    // Detect column mapping from header row
    final headers = allRows[0].map((h) => h.toLowerCase().trim()).toList();
    int descCol = -1, catCol = -1, dateCol = -1, amtCol = -1;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.contains('desc') || h.contains('narration') || h.contains('particular')) {
        descCol = i;
      } else if (h.contains('categ')) {
        catCol = i;
      } else if (h.contains('date')) {
        dateCol = i;
      } else if (h.contains('amount') || h.contains('amt') || h.contains('total') || h.contains('debit')) {
        amtCol = i;
      }
    }

    // Fallback: if no headers matched, assume A=Description, B=Category, C=Date, D=Amount
    if (descCol < 0 && catCol < 0 && dateCol < 0 && amtCol < 0) {
      descCol = 0;
      catCol = 1;
      dateCol = 2;
      amtCol = 3;
    }

    final rows = <_ExpenseEditableRow>[];
    for (int i = 1; i < allRows.length; i++) {
      final vals = allRows[i];
      // Skip fully empty rows
      if (vals.every((v) => v.trim().isEmpty)) continue;

      final rawDesc = descCol >= 0 && descCol < vals.length ? vals[descCol].trim() : '';
      final rawCat = catCol >= 0 && catCol < vals.length ? vals[catCol].trim() : '';
      final rawDate = dateCol >= 0 && dateCol < vals.length ? vals[dateCol].trim() : '';
      final rawAmt = amtCol >= 0 && amtCol < vals.length ? vals[amtCol].trim() : '';

      // Parse amount: strip ₹, commas, spaces
      final cleanAmt = rawAmt.replaceAll(RegExp(r'[₹,\s]'), '');
      final amount = double.tryParse(cleanAmt);

      // Parse date: handle DD-MM-YYYY, DD/MM/YYYY, YYYY-MM-DD, Excel serial
      DateTime? date;
      if (rawDate.isNotEmpty) {
        // Try DD-MM-YYYY or DD/MM/YYYY
        final ddmmyyyy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(rawDate);
        if (ddmmyyyy != null) {
          final d = int.parse(ddmmyyyy.group(1)!);
          final m = int.parse(ddmmyyyy.group(2)!);
          final y = int.parse(ddmmyyyy.group(3)!);
          date = DateTime(y, m, d);
        }
        // Try YYYY-MM-DD
        if (date == null) {
          final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(rawDate);
          if (isoMatch != null) {
            date = DateTime(
              int.parse(isoMatch.group(1)!),
              int.parse(isoMatch.group(2)!),
              int.parse(isoMatch.group(3)!),
            );
          }
        }
        // Try Excel serial number
        if (date == null) {
          final serial = double.tryParse(rawDate);
          if (serial != null && serial > 1) {
            date = DateTime(1899, 12, 30).add(Duration(days: serial.toInt()));
          }
        }
      }

      // Map category
      final mappedCategory = _ExpenseExcelPreviewDialogState._mapToValidCategory(rawCat);

      // Validation
      String? error;
      if (amount == null || amount <= 0) {
        error = 'Invalid amount: $rawAmt';
      } else if (date == null) {
        error = 'Invalid date: $rawDate';
      }

      rows.add(_ExpenseEditableRow(
        description: rawDesc,
        category: mappedCategory,
        date: date ?? DateTime.now(),
        amount: amount ?? 0,
        isValid: error == null,
        validationError: error,
      ));
    }
    return rows;
  }

  Future<void> _uploadExpenseFile() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file data')),
        );
        return;
      }

      List<_ExpenseEditableRow> rows;
      try {
        rows = _parseExpenseExcel(Uint8List.fromList(bytes));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not parse Excel file: $e')),
        );
        return;
      }

      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No expense data found in the Excel file')),
        );
        return;
      }

      if (!mounted) return;

      final dialogResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ExpenseExcelPreviewDialog(
          rows: rows,
          authService: authService,
        ),
      );

      if (dialogResult == null || !mounted) return;
      final editedRows = dialogResult['rows'] as List<_ExpenseEditableRow>;

      final validRows = editedRows.where((r) => r.isValid).toList();
      int successCount = 0;
      final errors = <String>[];

      for (final row in validRows) {
        try {
          await _expenseService.createExpense(
            supabaseUrl: authService.supabaseUrl,
            idToken: await authService.getIdToken(),
            amount: row.amount,
            category: row.category.toLowerCase().trim(),
            description: row.description,
            date: row.date,
          );
          successCount++;
        } catch (e) {
          errors.add('${row.description.isNotEmpty ? row.description : row.category}: $e');
        }
      }

      if (!mounted) return;
      _loadExpenses();

      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $successCount expense(s)'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warningDark),
                const SizedBox(width: 8),
                Text('Imported $successCount, ${errors.length} failed'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (successCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('$successCount expenses imported successfully.',
                          style: const TextStyle(color: AppColors.success)),
                    ),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...errors.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process Excel file: $e')),
      );
    }
  }

  Future<void> _loadExpenses() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final idToken = await authService.getIdToken();
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: authService.supabaseUrl,
        idToken: idToken,
      );

      // Load budgets for the web budget status card (optional)
      List<Budget> budgets = [];
      try {
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        budgets = await _budgetService.getBudgets(
          supabaseUrl: authService.supabaseUrl,
          idToken: idToken,
          month: month,
        );
      } catch (_) {
        // Budget loading is optional; proceed without it
      }

      if (mounted) {
        setState(() {
          _expenses = expenses;
          _budgets = budgets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorDiagnostics = e is ExpenseException
              ? e.diagnostics
              : 'Exception type: ${e.runtimeType}\n$e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addExpense() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditExpenseScreen(),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _editExpense(Expense expense) async {
    // On web desktop, show inline detail panel instead of navigating
    if (kIsWeb && MediaQuery.of(context).size.width >= 900) {
      setState(() {
        _closeAllPanels();
        _selectedExpenseDetail = expense;
      });
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditExpenseScreen(expense: expense),
      ),
    );

    if (result == true) {
      _loadExpenses();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content:
            Text('Are you sure you want to delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _expenseService.deleteExpense(
        expenseId: expense.id,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      _loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: $e')),
        );
      }
    }
  }

  String _formatCurrency(double amount) {
    return '₹${amount.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final viewMode = context.watch<ViewModeProvider>().mode;
    if (kIsWeb && viewMode == ViewMode.desktop) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Action Pane ──────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Expenses',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildActionChip(
                        icon: Icons.auto_awesome,
                        label: 'AI Insights',
                        onTap: () => Navigator.of(context).pushNamed('/ai-features'),
                      ),
                      const SizedBox(width: 8),
                      _buildActionChip(
                        icon: Icons.upload_file,
                        label: 'Import',
                        onTap: () => Navigator.of(context).pushNamed('/csv-import'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _addExpense,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Expense'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _buildViewTab('Current Month', Icons.calendar_month, true),
                      const SizedBox(width: 6),
                      _buildViewTab('Historical', Icons.history, false, comingSoon: true),
                      const SizedBox(width: 6),
                      _buildViewTab('Analytics', Icons.insights, false, comingSoon: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadExpenses,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Unified modern control pill ──────────────────────────────────────────

  Widget _buildControlPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
    bool locked = false,
  }) {
    final bg = active ? color : color.withOpacity(0.08);
    final fg = active ? Colors.white : color;
    return Tooltip(
      message: locked ? 'Coming soon' : '',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        elevation: active ? 2 : 0,
        shadowColor: color.withOpacity(0.3),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 11, color: fg.withOpacity(0.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Keep legacy methods as thin wrappers for mobile layout
  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return _buildControlPill(icon: icon, label: label, color: Colors.grey, onTap: onTap);
  }

  Widget _buildViewTab(String label, IconData icon, bool active, {bool comingSoon = false}) {
    return _buildControlPill(
      icon: icon,
      label: label,
      color: AppColors.primary,
      active: active,
      locked: comingSoon,
      onTap: () {},
    );
  }

  // Kept for backwards compatibility — unused references
  Widget _buildViewTabLegacy(String label, IconData icon, bool active, {bool comingSoon = false}) {
    return Tooltip(
      message: comingSoon ? 'Coming soon' : '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border(bottom: BorderSide(color: AppColors.primary, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? AppColors.primary : Colors.grey[400]),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.primary : Colors.grey[500],
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_outline, size: 11, color: Colors.grey[400]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(AppIcons.error, size: 32, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Error loading expenses',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.errorDark)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                border: Border.all(color: AppColors.errorLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _errorDiagnostics ?? _error!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Diagnostic info above is selectable — long-press to copy.',
              style: TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadExpenses,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.receiptOutlined,
                size: 64, color: AppColors.grey400),
            const SizedBox(height: 16),
            Text('No expenses yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Tap the + button to add your first expense'),
          ],
        ),
      );
    }

    // Group expenses by month
    final groupedExpenses = <String, List<Expense>>{};
    for (final expense in _expenses) {
      final monthKey =
          '${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}';
      groupedExpenses.putIfAbsent(monthKey, () => []).add(expense);
    }
    final now = DateTime.now();
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    return ListView.builder(
      itemCount: groupedExpenses.length,
      itemBuilder: (context, index) {
        final monthKey = groupedExpenses.keys.elementAt(index);
        final monthExpenses = groupedExpenses[monthKey]!;
        final totalAmount =
            monthExpenses.fold<double>(0, (sum, e) => sum + e.amount);

        final monthName = _getMonthName(monthKey);

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            initiallyExpanded: monthKey == currentMonthKey,
            title: Text(monthName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${monthExpenses.length} transactions • ${_formatCurrency(totalAmount)}'),
            children: monthExpenses
                .map((expense) => _buildExpenseItem(expense))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildExpenseItem(Expense expense) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.getCategoryColor(expense.category),
        child: Icon(_getCategoryIcon(expense.category), size: 20),
      ),
      title: Text(expense.description),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${expense.category} • ${_formatDate(expense.date)}'),
          if (expense.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            TagWrap(tags: expense.tags),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatCurrency(expense.amount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (expense.source == 'email')
            const Icon(AppIcons.email, size: 16, color: AppColors.grey600),
        ],
      ),
      onTap: () => _editExpense(expense),
      onLongPress: () => _deleteExpense(expense),
    );
  }

  IconData _getCategoryIcon(String category) {
    return AppIcons.getCategoryIcon(category);
  }

  String _getMonthName(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    return '${monthNames[month - 1]} $year';
  }

  // ── Web (Desktop) Layout ─────────────────────────────────────────────────

  Widget _buildWebLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildWebError(context)
              : _buildWebContent(context, isDark, theme, primary),
    );
  }

  Widget _buildWebError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.error, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Error loading expenses',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          SelectableText(_errorDiagnostics ?? _error ?? '',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadExpenses,
            icon: const Icon(AppIcons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent(
      BuildContext context, bool isDark, ThemeData theme, Color primary) {
    final filtered = _webFilteredExpenses;

    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Expense',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    ),
                    const Spacer(),
                    // Daily Wisdom
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF3E5F5), Color(0xFFE8EAF6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: Colors.deepPurple[300]),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              '"${_financeProverbs[DateTime.now().day % _financeProverbs.length]}"',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.deepPurple[700], fontStyle: FontStyle.italic),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Main content below title ──
          Expanded(
            child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pending review banner
                    if (_pendingEmailExpenses.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.pending_actions, color: Colors.amber, size: 22),
                          const SizedBox(width: 12),
                          Text(
                            '${_pendingEmailExpenses.length} email transaction(s) pending your review',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    // ── Main Content: fills remaining viewport height ──
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Col 1: Transaction List (always visible)
                          Expanded(
                            flex: _selectedExpenseDetail != null ? 4 : 5,
                            child: _buildWebTransactionList(filtered, isDark, primary),
                          ),
                          const SizedBox(width: 12),
                          // When transaction detail is open: Col2=Detail, Col3=Rewards+InfoCards
                          if (_selectedExpenseDetail != null) ...[
                            Expanded(
                              flex: 3,
                              child: _buildInlineTransactionDetail(isDark, primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  _buildRewardsRow(isDark),
                                  const SizedBox(height: 8),
                                  Expanded(child: _buildInfoCardsColumn(isDark, primary)),
                                ],
                              ),
                            ),
                          ]
                          // When other panel is open: Col2=InfoCards, Col3=Panel
                          else if (_anyPanelOpen) ...[
                            Expanded(
                              flex: 4,
                              child: _buildInfoCardsColumn(isDark, primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  if (_showHistoricalPanel)
                                    Expanded(child: _buildHistoricalPerformancePanel(isDark, primary)),
                                  if (_showAnalyticsPanel)
                                    Expanded(child: _buildSpendingAnalyticsPanel(isDark, primary)),
                                ],
                              ),
                            ),
                          ]
                          // Default: Col2=InfoCards, Col3=Rewards+AI Insights
                          else ...[
                            Expanded(
                              flex: 4,
                              child: _buildInfoCardsColumn(isDark, primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildRewardsRow(isDark),
                                  const SizedBox(height: 8),
                                  Expanded(child: _buildAIInsightsPanel(isDark, primary)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Three info cards: Budget vs Expense, Over-budget bars, AI proverb ────

  static const _financeProverbs = [
    'A family that budgets together, grows together.',
    'Small savings today build big dreams for tomorrow.',
    'Track every rupee — awareness is the first step to wealth.',
    'The best time to start budgeting was yesterday. The next best is now.',
    'Financial peace isn\'t about how much you earn — it\'s about how wisely you spend.',
    'Every expense tracked is a step closer to financial freedom.',
    'Teach your children about money, and you give them wings for life.',
    'A budget is telling your money where to go instead of wondering where it went.',
    'Consistency beats intensity — save a little every day.',
    'The secret to wealth is simple: spend less than you earn, invest the rest.',
    'Your family\'s financial health is the foundation for everything else.',
    'Don\'t save what\'s left after spending. Spend what\'s left after saving.',
  ];

  // ── Custom Inline Calendar Widget ────────────────────────────────────────

  Widget _buildInlineCalendar(bool isDark, Color primary) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final calMonth = DateTime(_calendarDisplayMonth.year, _calendarDisplayMonth.month, 1);
    final daysInMonth = DateTime(calMonth.year, calMonth.month + 1, 0).day;
    final firstWeekday = calMonth.weekday % 7; // Sunday=0

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF651FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _calendarDisplayMonth = DateTime(calMonth.year, calMonth.month - 1, 1);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_left, size: 16, color: Colors.white),
                ),
              ),
              Text(
                '${months[calMonth.month - 1]} ${calMonth.year}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              GestureDetector(
                onTap: () {
                  final next = DateTime(calMonth.year, calMonth.month + 1, 1);
                  if (!next.isAfter(today)) {
                    setState(() {
                      _calendarDisplayMonth = next;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right, size: 16,
                    color: DateTime(calMonth.year, calMonth.month + 1, 1).isAfter(today) ? Colors.white38 : Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Weekday headers
          Row(
            children: weekdays.map((d) => Expanded(
              child: Center(child: Text(d, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white70))),
            )).toList(),
          ),
          const SizedBox(height: 4),
          // Day grid
          ...List.generate(6, (week) {
            return Row(
              children: List.generate(7, (dow) {
                final dayIdx = week * 7 + dow - firstWeekday + 1;
                if (dayIdx < 1 || dayIdx > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 28));
                }
                final date = DateTime(calMonth.year, calMonth.month, dayIdx);
                final isFuture = date.isAfter(today);
                final isToday = date == today;
                final isStart = _filterStartDate != null &&
                    date.year == _filterStartDate!.year && date.month == _filterStartDate!.month && date.day == _filterStartDate!.day;
                final isEnd = _filterEndDate != null &&
                    date.year == _filterEndDate!.year && date.month == _filterEndDate!.month && date.day == _filterEndDate!.day;
                final inRange = _filterStartDate != null && _filterEndDate != null &&
                    date.isAfter(_filterStartDate!.subtract(const Duration(days: 1))) &&
                    date.isBefore(_filterEndDate!.add(const Duration(days: 1)));
                final isSelected = isStart || isEnd;

                return Expanded(
                  child: GestureDetector(
                    onTap: isFuture ? null : () {
                      setState(() {
                        if (_filterStartDate == null || (_filterStartDate != null && _filterEndDate != null)) {
                          // First tap or reset: set start date
                          _filterStartDate = date;
                          _filterEndDate = null;
                        } else {
                          // Second tap: set end date (ensure start < end)
                          if (date.isBefore(_filterStartDate!)) {
                            _filterEndDate = _filterStartDate;
                            _filterStartDate = date;
                          } else {
                            _filterEndDate = date;
                          }
                          _showCalendarDropdown = false;
                        }
                      });
                    },
                    child: Container(
                      height: 28,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white
                            : inRange
                                ? Colors.white24
                                : null,
                        borderRadius: BorderRadius.circular(isSelected ? 8 : 4),
                      ),
                      child: Center(
                        child: Text(
                          '$dayIdx',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isFuture
                                ? Colors.white24
                                : isSelected
                                    ? const Color(0xFF651FFF)
                                    : isToday
                                        ? Colors.amber
                                        : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 8),
          // Quick select buttons
          Row(
            children: [
              _calQuickBtn('Today', () {
                setState(() {
                  _filterStartDate = today;
                  _filterEndDate = today;
                  _showCalendarDropdown = false;
                });
              }),
              const SizedBox(width: 6),
              _calQuickBtn('Yesterday', () {
                final y = today.subtract(const Duration(days: 1));
                setState(() {
                  _filterStartDate = y;
                  _filterEndDate = y;
                  _showCalendarDropdown = false;
                });
              }),
              const SizedBox(width: 6),
              _calQuickBtn('Last 7 days', () {
                setState(() {
                  _filterStartDate = today.subtract(const Duration(days: 6));
                  _filterEndDate = today;
                  _showCalendarDropdown = false;
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calQuickBtn(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  // ── Rewards Row: extracted to reuse in Col 3 ──

  Widget _buildRewardsRow(bool isDark) {
    final rewards = <_RewardIcon>[
      _RewardIcon(Icons.emoji_events_rounded, Colors.amber, 'Budget Champion'),
      _RewardIcon(Icons.savings_rounded, Colors.green, 'Smart Saver'),
      _RewardIcon(Icons.auto_graph_rounded, Colors.blue, 'Trend Watcher'),
      _RewardIcon(Icons.favorite_rounded, Colors.pink, 'Impulse Control'),
      _RewardIcon(Icons.shield_rounded, Colors.purple, 'No Leaks'),
      _RewardIcon(Icons.star_rounded, Colors.orange, 'Consistent'),
      _RewardIcon(Icons.diamond_rounded, Colors.teal, 'Goal Achiever'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('Rewards', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: rewards.map((r) => Tooltip(
              message: r.label,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [r.color.withOpacity(0.15), r.color.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: r.color.withOpacity(0.3)),
                ),
                child: Icon(r.icon, size: 15, color: r.color),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Info Cards column (without rewards) ──

  Widget _buildInfoCardsColumn(bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildAllInfoCards(isDark, primary),
      ),
    );
  }

  // ── All 14 AI Info Cards in a single scrollable column with arrow nav ──

  Widget _buildAllInfoCards(bool isDark, Color primary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canScrollDown = _infoCardScrollController.hasClients &&
            _infoCardScrollController.offset < _infoCardScrollController.position.maxScrollExtent;
        final canScrollUp = _infoCardScrollController.hasClients &&
            _infoCardScrollController.offset > 0;

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (_) {
                // Trigger rebuild for arrow visibility
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
                return false;
              },
              child: SingleChildScrollView(
                controller: _infoCardScrollController,
                child: _buildInfoCardsList(isDark, primary),
              ),
            ),
            // Up arrow
            if (canScrollUp)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    _infoCardScrollController.animateTo(
                      (_infoCardScrollController.offset - constraints.maxHeight * 0.7).clamp(0, _infoCardScrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (isDark ? Colors.grey.shade900 : Colors.white),
                          (isDark ? Colors.grey.shade900 : Colors.white).withOpacity(0),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: Colors.grey.shade500),
                    ),
                  ),
                ),
              ),
            // Down arrow
            if (canScrollDown)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    _infoCardScrollController.animateTo(
                      (_infoCardScrollController.offset + constraints.maxHeight * 0.7).clamp(0, _infoCardScrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          (isDark ? Colors.grey.shade900 : Colors.white),
                          (isDark ? Colors.grey.shade900 : Colors.white).withOpacity(0),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey.shade500),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Build the flat list of all 14 info cards ──

  Widget _buildInfoCardsList(bool isDark, Color primary) {
    final now = DateTime.now();
    final currentMonthExpenses = _expenses.where((e) =>
        e.date.year == now.year && e.date.month == now.month).toList();
    final totalSpend = currentMonthExpenses.fold<double>(0, (s, e) => s + e.amount);
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);

    // Category spends
    final catSpend = <String, double>{};
    final catCount = <String, int>{};
    for (final e in currentMonthExpenses) {
      catSpend[e.category] = (catSpend[e.category] ?? 0) + e.amount;
      catCount[e.category] = (catCount[e.category] ?? 0) + 1;
    }

    // Previous month data
    final prevMonth = DateTime(now.year, now.month - 1);
    final prevMonthExpenses = _expenses.where((e) =>
        e.date.year == prevMonth.year && e.date.month == prevMonth.month).toList();
    final prevTotal = prevMonthExpenses.fold<double>(0, (s, e) => s + e.amount);
    final prevCatSpend = <String, double>{};
    for (final e in prevMonthExpenses) {
      prevCatSpend[e.category] = (prevCatSpend[e.category] ?? 0) + e.amount;
    }

    // Daily spend pattern
    final dailySpends = <int, double>{};
    for (final e in currentMonthExpenses) {
      dailySpends[e.date.weekday] = (dailySpends[e.date.weekday] ?? 0) + e.amount;
    }

    // Small recurring (silent expenses)
    final smallExpenses = currentMonthExpenses.where((e) => e.amount < 200).toList();
    final smallTotal = smallExpenses.fold<double>(0, (s, e) => s + e.amount);

    // Impulse: late night or unplanned categories
    final impulseCategories = {'convenience food', 'entertainment', 'shopping', 'party'};
    final impulseCount = currentMonthExpenses.where((e) =>
        impulseCategories.contains(e.category.toLowerCase())).length;

    // Budget drift
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthPct = now.day / daysInMonth * 100;

    // Weekend vs weekday variance
    final weekendSpend = (dailySpends[6] ?? 0) + (dailySpends[7] ?? 0);
    final weekdaySpend = [1, 2, 3, 4, 5].fold<double>(0, (s, d) => s + (dailySpends[d] ?? 0));
    final avgWeekend = weekendSpend / 2;
    final avgWeekday = weekdaySpend > 0 ? weekdaySpend / 5 : 1;
    final volatilityPct = avgWeekday > 0 ? ((avgWeekend - avgWeekday) / avgWeekday * 100) : 0.0;

    // Essential ratio
    final essentialCats = {'groceries', 'education', 'healthcare', 'utilities', 'housing', 'senior care'};
    final essentialSpend = catSpend.entries
        .where((e) => essentialCats.contains(e.key.toLowerCase()))
        .fold<double>(0, (s, e) => s + e.value);
    final goodRatio = totalSpend > 0 ? (essentialSpend / totalSpend * 100) : 100;

    // Lifestyle creep
    final prevQ = _expenses.where((e) {
      final m = (now.year - e.date.year) * 12 + now.month - e.date.month;
      return m >= 3 && m <= 5;
    }).toList();
    final prevQTotal = prevQ.fold<double>(0, (s, e) => s + e.amount);
    final prevQAvg = prevQTotal / 3;
    final creepPct = prevQAvg > 0 ? ((totalSpend - prevQAvg) / prevQAvg * 100) : 0.0;

    // Budget drift per category
    String? driftingCat;
    double driftPct = 0;
    for (final b in _budgets) {
      if (b.amount > 0) {
        final usedPct = b.spent / b.amount * 100;
        if (usedPct > monthPct + 10) {
          if (usedPct > driftPct) {
            driftPct = usedPct;
            driftingCat = b.category;
          }
        }
      }
    }

    // Category overshoot
    String? overshootCat;
    double overshootAmt = 0;
    for (final entry in catSpend.entries) {
      final prev = prevCatSpend[entry.key] ?? 0;
      if (prev > 0 && entry.value > prev * 1.3) {
        final diff = entry.value - prev;
        if (diff > overshootAmt) {
          overshootAmt = diff;
          overshootCat = entry.key;
        }
      }
    }

    // Avoided spend (less impulse than last month)
    final prevImpulse = prevMonthExpenses.where((e) =>
        impulseCategories.contains(e.category.toLowerCase())).length;
    final avoidedCount = prevImpulse - impulseCount;

    // Projected expense
    final dailyRate = now.day > 0 ? totalSpend / now.day : 0.0;
    final projectedTotal = dailyRate * daysInMonth;

    // Over-budget count
    final overBudgetCount = _budgets.where((b) => b.spent > b.amount).length;
    final usagePct = totalBudget > 0 ? (totalSpend / totalBudget * 100).clamp(0, 999) : 0.0;
    final withinBudget = totalSpend <= totalBudget;

    // Spend leakage count
    final leakageCount = catSpend.entries.where((entry) {
      final budget = _budgets.where((b) => b.category == entry.key).firstOrNull;
      if (budget != null && entry.value > budget.amount) return true;
      final count = catCount[entry.key] ?? 0;
      final avgTxn = count > 0 ? entry.value / count : 0.0;
      if (count >= 3 && avgTxn < 1000) return true;
      if (totalSpend > 0 && entry.value / totalSpend > 0.3) return true;
      return false;
    }).length;

    // Build all 14 cards and distribute into 2 columns
    final allCards = <Widget>[
      _aiCard('💵', 'Budget vs Expense', '${_fmtCurrency(totalSpend)} / ${_fmtCurrency(totalBudget)} spent (${usagePct.toStringAsFixed(0)}%)', withinBudget ? Colors.green : Colors.red, withinBudget ? 'On track' : 'Over budget'),
      _aiCard('📊', 'Over Budget', overBudgetCount > 0 ? '$overBudgetCount categor${overBudgetCount == 1 ? 'y' : 'ies'} over budget' : 'All within budget!', overBudgetCount > 0 ? Colors.red : Colors.green, '$overBudgetCount'),
      _aiCard('💧', 'Spend Leakage', leakageCount > 0 ? '$leakageCount spending leak${leakageCount == 1 ? '' : 's'} detected' : 'No spending leaks detected! Your finances look healthy.', leakageCount > 0 ? Colors.pink : Colors.green, leakageCount > 0 ? 'Review' : 'Healthy'),
      _aiCard('💰', 'Projected Expense', '₹${projectedTotal.toStringAsFixed(0)} projected this month', Colors.green, '₹${dailyRate.toStringAsFixed(0)}/day'),
      _aiCard('🔔', 'Subscription Drain', currentMonthExpenses.isEmpty ? 'Connect email to track subscriptions' : '${catCount.length} active spending categories detected', Colors.red, 'Track recurring'),
      _aiCard('⚡', 'Impulse Spend', impulseCount > 0 ? '$impulseCount impulse spend${impulseCount == 1 ? '' : 's'} detected this month' : 'No impulse spending detected!', Colors.orange, impulseCount > 0 ? 'Review spending' : 'Great control!'),
      _aiCard('🔍', 'Silent Expenses', smallExpenses.isNotEmpty ? '${smallExpenses.length} small spends totaling ₹${smallTotal.toStringAsFixed(0)}' : 'No silent expenses detected', Colors.indigo, 'Under ₹200 each'),
      _aiCard('📈', 'Lifestyle Creep', creepPct.abs() > 5 ? 'Spending ${creepPct > 0 ? 'up' : 'down'} ${creepPct.abs().toStringAsFixed(0)}% vs last quarter' : 'Spending stable vs last quarter', creepPct > 10 ? Colors.red : Colors.teal, 'Quarter comparison'),
      _aiCard('🎯', 'Budget Drift', driftingCat != null ? '$driftingCat drifting—${driftPct.toStringAsFixed(0)}% used with ${(100 - monthPct).toStringAsFixed(0)}% of month left' : 'All categories on track', Colors.amber, 'Budget pace'),
      _aiCard('⚠️', 'Category Overshoot', overshootCat != null ? '$overshootCat spend up ₹${overshootAmt.toStringAsFixed(0)} vs last month' : 'No unusual category spikes', overshootCat != null ? Colors.deepOrange : Colors.green, 'Category watch'),
      _aiCard('📊', 'Spend Volatility', volatilityPct.abs() > 20 ? 'Weekend spending ${volatilityPct > 0 ? '${volatilityPct.toStringAsFixed(0)}% higher' : '${volatilityPct.abs().toStringAsFixed(0)}% lower'} than weekdays' : 'Spending pattern is stable', Colors.purple, 'Daily patterns'),
      _aiCard('💡', 'Smart Saving', totalBudget > 0 && totalSpend < totalBudget ? 'Potential to save ₹${(totalBudget - totalSpend).toStringAsFixed(0)} this month' : 'Set budgets to unlock saving tips', Colors.blue, 'Opportunity'),
      _aiCard('✅', 'Good Spend Ratio', '${goodRatio.toStringAsFixed(0)}% of spending on essentials & goals', goodRatio >= 70 ? Colors.green : Colors.orange, goodRatio >= 70 ? 'Healthy!' : 'Could improve'),
      _aiCard('🛡️', 'Avoided Spend', avoidedCount > 0 ? 'You avoided $avoidedCount impulse spend${avoidedCount == 1 ? '' : 's'} vs last month' : prevImpulse == 0 ? 'Clean record both months!' : '${impulseCount - prevImpulse} more impulse spends than last month', avoidedCount > 0 ? Colors.green : Colors.grey, 'Habit tracking'),
    ];

    // Distribute cards alternately into 2 columns
    final leftCards = <Widget>[];
    final rightCards = <Widget>[];
    for (int i = 0; i < allCards.length; i++) {
      if (i.isEven) {
        if (leftCards.isNotEmpty) leftCards.add(const SizedBox(height: 8));
        leftCards.add(allCards[i]);
      } else {
        if (rightCards.isNotEmpty) rightCards.add(const SizedBox(height: 8));
        rightCards.add(allCards[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: leftCards)),
        const SizedBox(width: 8),
        Expanded(child: Column(children: rightCards)),
      ],
    );
  }

  Widget _aiCard(String emoji, String title, String message, Color color, String badge) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(badge, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreeInfoCards(bool isDark, Color primary) {
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final totalExpense = _monthlySpendTotal;
    final remaining = totalBudget - totalExpense;
    final usagePct = totalBudget > 0 ? (totalExpense / totalBudget * 100).clamp(0, 999) : 0.0;
    final withinBudget = totalExpense <= totalBudget;

    // Over-budget categories
    final overBudgetItems = <MapEntry<String, double>>[];
    for (final b in _budgets) {
      if (b.spent > b.amount) {
        overBudgetItems.add(MapEntry(b.category, b.spent - b.amount));
      }
    }
    overBudgetItems.sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        // Card 1: Budget vs Expense
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: withinBudget
                  ? [const Color(0xFF43A047), const Color(0xFF66BB6A)]
                  : [const Color(0xFFE53935), const Color(0xFFEF5350)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Budget vs Expense', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_fmtCurrency(totalExpense), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('/ ${_fmtCurrency(totalBudget)}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalBudget > 0 ? (totalExpense / totalBudget).clamp(0, 1) : 0,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Icon(withinBudget ? Icons.check_circle : Icons.warning_rounded, color: Colors.white, size: 22),
                  const SizedBox(height: 2),
                  Text('${usagePct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Card 3: Over-budget bar graph
        Container(
          height: 100,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 13, color: Colors.red[400]),
                  const SizedBox(width: 4),
                  Text('Over Budget', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red[400])),
                  const Spacer(),
                  Text('${overBudgetItems.length}', style: TextStyle(fontSize: 9, color: Colors.grey[400])),
                ],
              ),
              const SizedBox(height: 6),
              if (overBudgetItems.isEmpty)
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.thumb_up_alt_outlined, size: 14, color: Colors.green[400]),
                        const SizedBox(width: 4),
                        Text('All within budget!', style: TextStyle(fontSize: 11, color: Colors.green[600], fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ...overBudgetItems.take(4).map((item) {
                        final maxVal = overBudgetItems.first.value;
                        final fraction = maxVal > 0 ? (item.value / maxVal).clamp(0.15, 1.0) : 0.3;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Tooltip(
                              message: '${item.key}: +${_fmtCurrency(item.value)}',
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: FractionallySizedBox(
                                      heightFactor: fraction.toDouble(),
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red[300],
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.key.length > 4 ? '${item.key.substring(0, 3)}…' : item.key,
                                    style: TextStyle(fontSize: 7, color: Colors.grey[500]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Flippable Projected Expense (shown under info cards when panel active) ──

  Widget _buildFlippableProjectedSection(bool isDark, Color primary) {
    return Column(
      children: [
        if (_showLeakageFlip)
          _buildProjectedExpenseSection(isDark, primary),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _showLeakageFlip = !_showLeakageFlip),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showLeakageFlip ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  _showLeakageFlip ? 'Hide Projection' : 'Show Projection',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Projected Expense This Month ─────────────────────────────────────────

  Widget _buildProjectedExpenseSection(bool isDark, Color primary) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed = now.day;
    final daysRemaining = daysInMonth - daysPassed;

    // Current month spend
    final currentSpend = _monthlySpendTotal;

    // Historical average (from past months in _expenses)
    final monthlyTotals = <String, double>{};
    for (final e in _expenses) {
      final key = '${e.date.year}-${e.date.month}';
      final currentKey = '${now.year}-${now.month}';
      if (key != currentKey) {
        monthlyTotals[key] = (monthlyTotals[key] ?? 0) + e.amount;
      }
    }
    final historicalAvg = monthlyTotals.isNotEmpty
        ? monthlyTotals.values.fold<double>(0, (a, b) => a + b) / monthlyTotals.length
        : 0.0;

    // Budget total
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);

    // Daily burn rate — use current data, or fall back to historical, or budget
    final double dailyRate;
    final double projected;
    if (currentSpend > 0 && daysPassed > 0) {
      dailyRate = currentSpend / daysPassed;
      projected = dailyRate * daysInMonth;
    } else if (historicalAvg > 0) {
      dailyRate = historicalAvg / daysInMonth;
      projected = historicalAvg;
    } else if (totalBudget > 0) {
      dailyRate = totalBudget / daysInMonth;
      projected = totalBudget;
    } else {
      dailyRate = 0;
      projected = 0;
    }

    final projectedOverBudget = projected > totalBudget && totalBudget > 0;
    final projectedOverflowAmt = projected - totalBudget;
    final projectedPct = totalBudget > 0 ? (projected / totalBudget * 100) : 0.0;

    // Compare projected to historical
    final vsHistorical = historicalAvg > 0 ? ((projected - historicalAvg) / historicalAvg * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: projectedOverBudget
              ? [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)]
              : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: projectedOverBudget ? Colors.orange.shade200 : Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: projectedOverBudget ? Colors.orange.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  size: 20,
                  color: projectedOverBudget ? Colors.orange.shade700 : Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Projected Expense This Month', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: projectedOverBudget ? Colors.orange.shade600 : Colors.green.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'AI',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Projected amount with gauge
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${projected.toStringAsFixed(0)}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: projectedOverBudget ? Colors.orange.shade800 : Colors.green.shade800)),
                    const SizedBox(height: 2),
                    Text('projected by month end', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Circular gauge indicator
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: (projectedPct / 100).clamp(0, 1).toDouble(),
                            strokeWidth: 6,
                            backgroundColor: Colors.grey.shade200,
                            color: projectedOverBudget ? Colors.orange.shade600 : Colors.green.shade600,
                          ),
                          Text(
                            '${projectedPct.toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: projectedOverBudget ? Colors.orange.shade700 : Colors.green.shade700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('of budget', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _projStatChip(
                '₹${dailyRate.toStringAsFixed(0)}',
                'Daily Rate',
                Icons.speed_rounded,
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _projStatChip(
                '$daysRemaining',
                'Days Left',
                Icons.hourglass_bottom_rounded,
                Colors.purple,
              ),
              const SizedBox(width: 8),
              _projStatChip(
                '${vsHistorical >= 0 ? '+' : ''}${vsHistorical.toStringAsFixed(0)}%',
                'vs History',
                vsHistorical > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                vsHistorical > 5 ? Colors.red : Colors.green,
              ),
            ],
          ),

          if (projectedOverBudget && totalBudget > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'May overflow budget by ₹${projectedOverflowAmt.toStringAsFixed(0)} based on current spending pattern',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Top 5 Projected Expenses ──
          const SizedBox(height: 14),
          Text('Top Projected Expenses', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          ..._buildTop5ProjectedExpenses(now, dailyRate, projectedOverBudget),
        ],
      ),
    );
  }

  Widget _projStatChip(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTop5ProjectedExpenses(DateTime now, double dailyRate, bool isOverBudget) {
    // Find top recurring/largest expenses from current + recent months to project
    final categoryHighest = <String, _ProjectedItem>{};
    for (final e in _expenses) {
      // Consider last 3 months of data
      final monthsDiff = (now.year - e.date.year) * 12 + (now.month - e.date.month);
      if (monthsDiff > 3) continue;
      final existing = categoryHighest[e.category];
      if (existing == null || e.amount > existing.amount) {
        categoryHighest[e.category] = _ProjectedItem(
          description: e.description,
          category: e.category,
          amount: e.amount,
          date: e.date,
        );
      }
    }

    final items = categoryHighest.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top5 = items.take(5).toList();

    if (top5.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('No expense data to project', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
      ];
    }

    final accent = isOverBudget ? Colors.orange.shade700 : Colors.green.shade700;
    return top5.map((item) {
      final dayStr = '${item.date.day}/${item.date.month}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(dayStr, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: accent)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description.length > 28 ? '${item.description.substring(0, 25)}…' : item.description,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(item.category, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Text('₹${item.amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ── Spend Leakage Section ────────────────────────────────────────────────

  Widget _buildSpendLeakageSection(bool isDark, Color primary) {
    final now = DateTime.now();

    // Identify "leakage" — categories where spend is disproportionately high
    // or items with small recurring charges that add up
    final categorySpend = <String, double>{};
    final categoryCount = <String, int>{};
    for (final e in _expenses) {
      if (e.date.year == now.year && e.date.month == now.month) {
        categorySpend[e.category] = (categorySpend[e.category] ?? 0) + e.amount;
        categoryCount[e.category] = (categoryCount[e.category] ?? 0) + 1;
      }
    }

    // Find leakage: categories with high frequency low-value txns, or over-budget
    final leakageItems = <_LeakageItem>[];
    for (final entry in categorySpend.entries) {
      final budget = _budgets.where((b) => b.category == entry.key).firstOrNull;
      final count = categoryCount[entry.key] ?? 0;
      final avgTxn = count > 0 ? entry.value / count : 0.0;

      // Over-budget leak
      if (budget != null && entry.value > budget.amount) {
        final overAmt = entry.value - budget.amount;
        leakageItems.add(_LeakageItem(
          category: entry.key,
          amount: overAmt,
          reason: 'Over budget by ₹${overAmt.toStringAsFixed(0)}',
          severity: overAmt / budget.amount,
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
        ));
      }
      // High frequency small transactions (potential impulse spending)
      else if (count >= 3 && avgTxn < 1000) {
        leakageItems.add(_LeakageItem(
          category: entry.key,
          amount: entry.value,
          reason: '$count transactions, avg ₹${avgTxn.toStringAsFixed(0)} each',
          severity: count / 10,
          icon: Icons.repeat_rounded,
          color: Colors.orange,
        ));
      }
      // Large single outlier (> 30% of total spend)
      else if (_monthlySpendTotal > 0 && entry.value / _monthlySpendTotal > 0.3) {
        leakageItems.add(_LeakageItem(
          category: entry.key,
          amount: entry.value,
          reason: '${(entry.value / _monthlySpendTotal * 100).toStringAsFixed(0)}% of total spend',
          severity: entry.value / _monthlySpendTotal,
          icon: Icons.pie_chart_outline_rounded,
          color: Colors.deepPurple,
        ));
      }
    }

    leakageItems.sort((a, b) => b.severity.compareTo(a.severity));
    final totalLeakage = leakageItems.fold<double>(0, (s, i) => s + i.amount);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pink.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.water_drop_outlined, size: 20, color: Colors.pink.shade600),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Spend Leakage', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.pink.shade400, Colors.purple.shade400]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (leakageItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 22, color: Colors.green.shade600),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('No spending leaks detected! Your finances look healthy.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                ],
              ),
            )
          else ...[
            // Total leakage header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    '₹${totalLeakage.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.pink.shade700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('identified across ${leakageItems.length} area${leakageItems.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Leakage items
            ...leakageItems.take(5).map((item) {
              final barFraction = totalLeakage > 0 ? (item.amount / totalLeakage).clamp(0.1, 1.0) : 0.3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: item.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(item.icon, size: 14, color: item.color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                          Text('₹${item.amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: item.color)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: barFraction,
                          backgroundColor: Colors.grey.shade200,
                          color: item.color.withOpacity(0.6),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(item.reason, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildExpenseCategoryGrid(bool isDark) {
    const categories = [
      _ExpenseCategoryItem(
        label: 'Entertainment',
        icon: Icons.movie_outlined,
        color: Color(0xFFE91E63),
        bgColor: Color(0xFFFCE4EC),
      ),
      _ExpenseCategoryItem(
        label: 'Groceries',
        icon: Icons.shopping_cart_outlined,
        color: Color(0xFF4CAF50),
        bgColor: Color(0xFFE8F5E9),
      ),
      _ExpenseCategoryItem(
        label: 'Mental Wellness',
        icon: Icons.self_improvement,
        color: Color(0xFF7C4DFF),
        bgColor: Color(0xFFEDE7F6),
      ),
      _ExpenseCategoryItem(
        label: 'Physical Wellness',
        icon: Icons.fitness_center,
        color: Color(0xFFFF5722),
        bgColor: Color(0xFFFBE9E7),
      ),
      _ExpenseCategoryItem(
        label: 'Party',
        icon: Icons.celebration_outlined,
        color: Color(0xFFFF9800),
        bgColor: Color(0xFFFFF3E0),
      ),
      _ExpenseCategoryItem(
        label: 'Personal Care',
        icon: Icons.spa_outlined,
        color: Color(0xFFEC407A),
        bgColor: Color(0xFFFCE4EC),
      ),
      _ExpenseCategoryItem(
        label: 'Pet Care',
        icon: Icons.pets_outlined,
        color: Color(0xFF8D6E63),
        bgColor: Color(0xFFEFEBE9),
      ),
      _ExpenseCategoryItem(
        label: 'Senior Care',
        icon: Icons.elderly_outlined,
        color: Color(0xFF00897B),
        bgColor: Color(0xFFE0F2F1),
      ),
      _ExpenseCategoryItem(
        label: 'Education',
        icon: Icons.school_outlined,
        color: Color(0xFF1565C0),
        bgColor: Color(0xFFE3F2FD),
      ),
      _ExpenseCategoryItem(
        label: 'Vacation',
        icon: Icons.flight_outlined,
        color: Color(0xFF00ACC1),
        bgColor: Color(0xFFE0F7FA),
      ),
      _ExpenseCategoryItem(
        label: 'Convenience Food',
        icon: Icons.fastfood_outlined,
        color: Color(0xFFEF6C00),
        bgColor: Color(0xFFFFF8E1),
      ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final count = _getCategoryExpenseCount(cat.label);
          final total = _getCategoryExpenseTotal(cat.label);
          return _buildCategoryChip(cat, count, total);
        },
      ),
    );
  }

  int _getCategoryExpenseCount(String categoryLabel) {
    final now = DateTime.now();
    final lbl = categoryLabel.toLowerCase();
    return _expenses.where((e) {
      if (e.date.year != now.year || e.date.month != now.month) return false;
      return _matchesCategory(e, lbl);
    }).length;
  }

  double _getCategoryExpenseTotal(String categoryLabel) {
    final now = DateTime.now();
    final lbl = categoryLabel.toLowerCase();
    return _expenses.where((e) {
      if (e.date.year != now.year || e.date.month != now.month) return false;
      return _matchesCategory(e, lbl);
    }).fold(0.0, (s, e) => s + e.amount);
  }

  bool _matchesCategory(Expense e, String lbl) {
    final cat = e.category.toLowerCase();
    final desc = e.description.toLowerCase();
    final tags = e.tags.map((t) => t.toLowerCase()).join(' ');
    final blob = '$cat $desc $tags';

    switch (lbl) {
      case 'entertainment':
        return cat == 'entertainment' || blob.contains('movie') || blob.contains('netflix') || blob.contains('concert') || blob.contains('game');
      case 'groceries':
        return cat == 'groceries' || cat == 'grocery' || blob.contains('grocery') || blob.contains('supermarket') || blob.contains('vegetables');
      case 'mental wellness':
        return blob.contains('therapy') || blob.contains('counseling') || blob.contains('meditation') || blob.contains('mental') || blob.contains('wellness app');
      case 'physical wellness':
        return blob.contains('gym') || blob.contains('fitness') || blob.contains('yoga') || blob.contains('sports') || blob.contains('workout');
      case 'party':
        return blob.contains('party') || blob.contains('celebration') || blob.contains('birthday') || blob.contains('event');
      case 'personal care':
        return blob.contains('salon') || blob.contains('spa') || blob.contains('grooming') || blob.contains('haircut') || blob.contains('beauty');
      case 'pet care':
        return blob.contains('pet') || blob.contains('vet') || blob.contains('dog') || blob.contains('cat') || blob.contains('animal');
      case 'senior care':
        return blob.contains('senior') || blob.contains('elderly') || blob.contains('parent care') || blob.contains('old age');
      case 'education':
        return cat == 'education' || blob.contains('school') || blob.contains('tuition') || blob.contains('course') || blob.contains('book') || blob.contains('training');
      case 'vacation':
        return blob.contains('travel') || blob.contains('vacation') || blob.contains('trip') || blob.contains('hotel') || blob.contains('flight') || blob.contains('holiday');
      case 'convenience food':
        return blob.contains('swiggy') || blob.contains('zomato') || blob.contains('food delivery') || blob.contains('takeaway') || blob.contains('fast food') || blob.contains('convenience food');
      default:
        return cat == lbl;
    }
  }

  Widget _buildCategoryChip(_ExpenseCategoryItem cat, int count, double total) {
    final isActive = _selectedCategoryFilter == cat.label;
    return Material(
      color: isActive ? cat.color.withOpacity(0.2) : cat.bgColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() {
            _selectedCategoryFilter = isActive ? null : cat.label;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cat.icon, size: 18, color: cat.color),
              const SizedBox(width: 6),
              Text(
                cat.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cat.color,
                ),
              ),
              if (count > 0) ...[                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cat.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebTransactionRow(Expense expense, bool isDark) {
    final isIncome = expense.category.toLowerCase() == 'income' ||
        expense.category.toLowerCase() == 'salary';
    final isPending = expense.source == 'email' && !expense.isApproved;
    final bgColor = AppColors.getCategoryColor(expense.category);
    final iconColor = AppColors.getCategoryIconColor(expense.category);
    final d = expense.date;
    final dateStr = '${_webMonthAbbr(d.month)} ${d.day}, ${d.year}';
    final isHovered = _hoveredExpenseId == expense.id;

    // Find matching budget for this expense's category to show progress
    final matchingBudget = _budgets.cast<Budget?>().firstWhere(
      (b) => b!.category.toLowerCase() == expense.category.toLowerCase(),
      orElse: () => null,
    );
    final hasBudget = matchingBudget != null && matchingBudget.amount > 0;
    final amountColor = isIncome ? AppColors.successDark : (hasBudget && matchingBudget.spent > matchingBudget.amount ? AppColors.error : const Color(0xFF334155));

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredExpenseId = expense.id),
      onExit: (_) => setState(() { if (_hoveredExpenseId == expense.id) _hoveredExpenseId = null; }),
      child: InkWell(
        onTap: () => _editExpense(expense),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isHovered
                ? (isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC))
                : isPending
                    ? Colors.amber.withOpacity(0.04)
                    : null,
            border: Border(top: BorderSide(color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              // Category icon bubble
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(AppIcons.getCategoryIcon(expense.category), size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row: description + badges
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            expense.description,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Category badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_webCapitalize(expense.category), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                        ),
                        const SizedBox(width: 4),
                        // Source badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                expense.source == 'email' ? Icons.email_outlined : expense.source == 'csv' ? Icons.upload_file_outlined : Icons.qr_code_2,
                                size: 10, color: Colors.blue[300],
                              ),
                              const SizedBox(width: 3),
                              Text(_paymentMethodLabel(expense.source), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.blue[400])),
                            ],
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('\u23F3 Pending', style: TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.w700)),
                          ),
                        ],
                        if (expense.tags.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              expense.tags.take(2).join(', '),
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.purple[400]),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress bar (if budget exists for this category)
                    if (hasBudget) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (matchingBudget.spent / matchingBudget.amount).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: isDark ? AppColors.grey800 : const Color(0xFFEEF2F6),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            matchingBudget.spent > matchingBudget.amount
                                ? AppColors.error
                                : matchingBudget.spent / matchingBudget.amount >= 0.8
                                    ? AppColors.warningDark
                                    : AppColors.successDark,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Thin accent bar when no budget
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Amount + date row
                    Row(
                      children: [
                        Text(
                          '${isIncome ? '+' : ''}${_fmtCurrency(expense.amount)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: amountColor),
                        ),
                        if (hasBudget) ...[
                          const SizedBox(width: 4),
                          Text(
                            'of ${_fmtCurrency(matchingBudget.amount)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                        const Spacer(),
                        Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                    // Telemetry chips for email transactions
                    if (expense.source == 'email' && expense.notes != null && expense.notes!.contains('|')) ...[
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 2, children: _buildTelemetryChips(expense.notes!, isDark)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Edit icon — visible on hover
              AnimatedOpacity(
                opacity: isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Tooltip(
                  message: 'Edit',
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                  ),
                ),
              ),
              // Approve/Reject for pending email items
              if (isPending) ...[
                const SizedBox(width: 8),
                _approveRejectButton(icon: Icons.check_circle_outline, label: 'Approve', color: AppColors.success, onTap: () => _approveExpense(expense)),
                const SizedBox(width: 4),
                _approveRejectButton(icon: Icons.cancel_outlined, label: 'Reject', color: AppColors.error, onTap: () => _rejectExpense(expense)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetStatusCard(bool isDark, Color primary) {
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final monthlySpend = _monthlySpendTotal;
    final hasData = totalBudget > 0;
    final ratio = hasData ? (monthlySpend / totalBudget).clamp(0.0, 1.0) : 0.0;
    final withinBudget = !hasData || monthlySpend <= totalBudget;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Weekly Budget Status',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                hasData
                    ? (withinBudget
                        ? 'You are within your spending limit.'
                        : 'You have exceeded your budget.')
                    : 'Set up budgets to track spending here.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13),
              ),
              if (hasData) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    color: withinBudget ? Colors.white : Colors.red[200],
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmtCurrency(monthlySpend)} of ${_fmtCurrency(totalBudget)}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/budget'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Edit Budget',
                      style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            withinBudget
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            color: Colors.white,
            size: 32,
          ),
        ),
      ]),
    );
  }

  Widget _webStatCard({
    required bool isDark,
    required Color primary,
    required IconData icon,
    required String label,
    required String value,
    required String trendLabel,
    required bool trendUp,
    required String footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: primary, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: trendUp
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  children: [
                    Icon(
                      trendUp ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: trendUp ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trendLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: trendUp ? AppColors.error : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            footer,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _webCategoryDistCard(bool isDark, Color primary) {
    final totals = <String, double>{};
    for (final e in _filteredExpenses) {
      if (e.category.toLowerCase() != 'income' &&
          e.category.toLowerCase() != 'salary') {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
    }
    final grand = totals.values.fold(0.0, (s, v) => s + v);
    final sorted = (totals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .toList();
    final colors = [primary, Colors.amber, Colors.green, Colors.red];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Category Distribution',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border(
                  top: BorderSide(color: colors[0], width: 12),
                  right: BorderSide(color: colors[1], width: 12),
                  bottom: BorderSide(color: colors[2], width: 12),
                  left: BorderSide(color: colors[3], width: 12),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtCurrency(grand),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (sorted.isEmpty)
            Text('No data', style: TextStyle(color: Colors.grey[400]))
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final cat = entry.value;
                final pct = grand > 0
                    ? '${(cat.value / grand * 100).toStringAsFixed(0)}%'
                    : '0%';
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${_webCapitalize(cat.key)} ($pct)',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ]);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _trendBar(double heightFactor, Color color) {
    return Expanded(
      child: Container(
        height: 90,
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          widthFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchSmartInsights() async {
    setState(() {
      _loadingInsights = true;
      _smartInsightsError = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _smartInsights = result['analysis'] as String?;
        _loadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInsights = false;
        _smartInsightsError = e.toString();
      });
    }
  }

  Widget _buildSmartInsightsCard(bool isDark, Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 20),
            const SizedBox(width: 8),
            const Text('Smart Insights',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_loadingInsights)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              InkWell(
                onTap: _fetchSmartInsights,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _smartInsights != null ? 'Refresh' : 'Analyze',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (_smartInsightsError != null)
            Text(_smartInsightsError!, style: const TextStyle(color: AppColors.error, fontSize: 12))
          else if (_smartInsights != null)
            Text(_smartInsights!, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4))
          else
            Text(
              'Tap Analyze for AI-powered spending insights.',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }

  Widget _webComingSoonCard({
    required bool isDark,
    required Color primary,
    required String title,
    required IconData icon,
    required String message,
    bool dark = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1E2836)
            : (isDark ? AppColors.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: dark ? Colors.white70 : primary, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: dark ? Colors.white : null)),
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Feature coming soon',
              child: Icon(Icons.close_rounded, size: 13, color: Colors.red),
            ),
          ]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  fontSize: 12,
                  color: dark ? Colors.white54 : Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _filterChip(bool isDark, String label, IconData icon) {
    return Tooltip(
      message: 'Feature coming soon',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(width: 6),
          Icon(Icons.expand_more, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 4),
          const Icon(Icons.close_rounded, size: 11, color: Colors.red),
        ]),
      ),
    );
  }

  // ── Computed helpers ──────────────────────────────────────────────────────

  List<Expense> get _filteredExpenses {
    final now = DateTime.now();
    return _expenses.where((e) {
      // Show only current month expenses
      final inPeriod = e.date.year == now.year && e.date.month == now.month;
      if (!inPeriod) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return e.description.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.tags.any((tag) => tag.toLowerCase().contains(q));
      }
      return true;
    }).toList();
  }

  /// Filtered expenses for web layout, with optional category filter applied.
  List<Expense> get _webFilteredExpenses {
    List<Expense> base;
    // When date range is active, bypass current-month restriction
    if (_filterStartDate != null) {
      final start = DateTime(_filterStartDate!.year, _filterStartDate!.month, _filterStartDate!.day);
      final end = _filterEndDate != null
          ? DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day, 23, 59, 59)
          : DateTime(start.year, start.month, start.day, 23, 59, 59);
      base = _expenses.where((e) => !e.date.isBefore(start) && !e.date.isAfter(end)).toList();
      // Apply search query if present
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        base = base.where((e) =>
            e.description.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.tags.any((tag) => tag.toLowerCase().contains(q))).toList();
      }
    } else {
      base = _filteredExpenses;
    }
    if (_selectedCategoryFilter != null) {
      final lbl = _selectedCategoryFilter!.toLowerCase();
      base = base.where((e) => _matchesCategory(e, lbl)).toList();
    }
    // Apply sort
    base.sort((a, b) => _expenseSortAscending
        ? a.amount.compareTo(b.amount)
        : b.amount.compareTo(a.amount));
    return base;
  }

  Map<String, List<Expense>> _groupedExpenses(List<Expense> expenses) {
    if (_expenseGroupBy == 'none') {
      return {'': expenses};
    }
    final Map<String, List<Expense>> groups = {};
    for (final e in expenses) {
      final key = _expenseGroupBy == 'category'
          ? '${e.category[0].toUpperCase()}${e.category.substring(1)}'
          : _expenseGroupBy == 'source'
              ? '${e.source[0].toUpperCase()}${e.source.substring(1)}'
              : '';
      (groups[key] ??= []).add(e);
    }
    return Map.fromEntries(groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  List<Expense> get _pendingEmailExpenses =>
      _filteredExpenses.where((e) => e.source == 'email' && !e.isApproved).toList();

  double get _monthlySpendTotal {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get _previousMonthSpend {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 1);
    return _expenses
        .where((e) =>
            e.date.year == previous.year &&
            e.date.month == previous.month &&
            e.category.toLowerCase() != 'income' &&
            e.category.toLowerCase() != 'salary')
        .fold(0.0, (s, e) => s + e.amount);
  }

  String _paymentMethodLabel(String source) {
    if (source == 'email') return 'Email Imported';
    if (source == 'csv') return 'CSV Imported';
    return 'Manual Entry';
  }

  String _fmtCurrency(double amount) {
    final formatted = amount.abs().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '\u20B9$formatted';
  }

  String _webCapitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _webMonthAbbr(int month) {
    const abbrs = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return abbrs[(month - 1).clamp(0, 11)];
  }

  List<Widget> _buildTelemetryChips(String notes, bool isDark) {
    // Notes format: "HDFC Bank | Credit Card | Card **4860 | VPA: xyz@upi | AI from email [INBOX]"
    final segments = notes.split('|').map((s) => s.trim()).toList();
    final chips = <Widget>[];
    for (final seg in segments) {
      // Skip the "AI/Regex from email@addr [folder]" suffix
      if (seg.contains(' from ') && seg.contains('[')) continue;
      if (seg.isEmpty) continue;

      IconData? icon;
      Color? chipColor;
      if (seg.contains('Bank')) {
        icon = Icons.account_balance_outlined;
        chipColor = Colors.blue;
      } else if (seg.contains('Credit Card')) {
        icon = Icons.credit_card;
        chipColor = Colors.deepPurple;
      } else if (seg.contains('Debit Card')) {
        icon = Icons.credit_card_outlined;
        chipColor = Colors.teal;
      } else if (seg.startsWith('UPI') || seg.startsWith('VPA')) {
        icon = Icons.phone_android;
        chipColor = Colors.green;
      } else if (seg.startsWith('Card')) {
        icon = Icons.credit_card;
        chipColor = Colors.indigo;
      } else if (seg.startsWith('Acct')) {
        icon = Icons.account_balance_wallet_outlined;
        chipColor = Colors.orange;
      } else if (seg.startsWith('Ref')) {
        icon = Icons.tag;
        chipColor = Colors.grey;
      } else if (seg.contains('NEFT') || seg.contains('IMPS') || seg.contains('RTGS')) {
        icon = Icons.swap_horiz;
        chipColor = Colors.brown;
      } else {
        continue; // Skip unknown segments
      }

      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: (chipColor ?? Colors.grey).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 10, color: chipColor),
              if (icon != null) const SizedBox(width: 3),
              Text(seg, style: TextStyle(fontSize: 9, color: chipColor, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }
    return chips;
  }

  Widget _approveRejectButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _approveExpense(Expense expense) async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await _expenseService.approveTransaction(
        expenseId: expense.id,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction approved')),
        );
      }
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _rejectExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Transaction'),
        content: Text('Reject "${expense.description}"? This will mark it as rejected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await _expenseService.rejectTransaction(
        expenseId: expense.id,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction rejected')),
        );
      }
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Web: Compact Expense List Controls (matches budget toolbar pattern) ──

  Widget _buildExpenseListControls() {
    final hasDateFilter = _filterStartDate != null || _filterEndDate != null;
    final hasCatFilter = _selectedCategoryFilter != null;

    final allCategoryLabels = [
      'Entertainment', 'Groceries', 'Mental Wellness', 'Physical Wellness',
      'Party', 'Personal Care', 'Pet Care', 'Senior Care', 'Education',
      'Vacation', 'Convenience Food',
    ];

    const iconColor = Color(0xFF64748B);
    const activeColor = Color(0xFFE65100);
    const iconSize = 20.0;
    const btnConstraints = BoxConstraints(minWidth: 34, minHeight: 34);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Filter by Category
        PopupMenuButton<String?>(
          tooltip: hasCatFilter ? 'Filtered: $_selectedCategoryFilter' : 'Filter by Category',
          icon: Icon(Icons.filter_list_rounded, color: hasCatFilter ? activeColor : iconColor, size: iconSize),
          constraints: btnConstraints,
          padding: EdgeInsets.zero,
          onSelected: (value) => setState(() => _selectedCategoryFilter = value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white.withOpacity(0.92),
          elevation: 6,
          menuPadding: EdgeInsets.zero,
          itemBuilder: (context) => [
            PopupMenuItem<String?>(
              value: null,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.clear_all_rounded, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                const Text('All', style: TextStyle(fontSize: 12)),
              ]),
            ),
            const PopupMenuDivider(height: 1),
            ...allCategoryLabels.map((cat) => PopupMenuItem<String?>(
              value: cat,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                if (_selectedCategoryFilter == cat)
                  const Icon(Icons.check_rounded, size: 14, color: activeColor)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 6),
                Text(cat, style: const TextStyle(fontSize: 12)),
              ]),
            )),
          ],
        ),
        // 2. Group By
        PopupMenuButton<String>(
          tooltip: _expenseGroupBy == 'none' ? 'Group By' : 'Grouped: ${_expenseGroupBy[0].toUpperCase()}${_expenseGroupBy.substring(1)}',
          icon: Icon(Icons.workspaces_outlined, color: _expenseGroupBy != 'none' ? activeColor : iconColor, size: iconSize),
          constraints: btnConstraints,
          padding: EdgeInsets.zero,
          onSelected: (value) => setState(() => _expenseGroupBy = value),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'none', child: Row(children: [
              if (_expenseGroupBy == 'none') const Icon(Icons.check_rounded, size: 16, color: activeColor) else const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('No Grouping', style: TextStyle(fontSize: 13)),
            ])),
            PopupMenuItem(value: 'category', child: Row(children: [
              if (_expenseGroupBy == 'category') const Icon(Icons.check_rounded, size: 16, color: activeColor) else const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('By Category', style: TextStyle(fontSize: 13)),
            ])),
            PopupMenuItem(value: 'source', child: Row(children: [
              if (_expenseGroupBy == 'source') const Icon(Icons.check_rounded, size: 16, color: activeColor) else const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('By Source', style: TextStyle(fontSize: 13)),
            ])),
          ],
        ),
        // 3. Sort by Amount
        Tooltip(
          message: _expenseSortAscending ? 'Sort: Low → High' : 'Sort: High → Low',
          child: IconButton(
            icon: Icon(
              _expenseSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: iconColor, size: iconSize,
            ),
            onPressed: () => setState(() => _expenseSortAscending = !_expenseSortAscending),
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
        // 4. Date Filter
        Tooltip(
          message: hasDateFilter ? 'Date Filter active' : 'Date Filter',
          child: IconButton(
            icon: Icon(Icons.date_range_rounded, color: (_showCalendarDropdown || hasDateFilter) ? activeColor : iconColor, size: iconSize),
            onPressed: () => setState(() {
              _showCalendarDropdown = !_showCalendarDropdown;
              if (_showCalendarDropdown) {
                _calendarDisplayMonth = _filterStartDate ?? DateTime(DateTime.now().year, DateTime.now().month);
              }
            }),
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
        // 5. Historical Performance
        Tooltip(
          message: _showHistoricalPanel ? 'Close Historical' : 'Historical Performance',
          child: IconButton(
            icon: Icon(Icons.history, color: _showHistoricalPanel ? activeColor : iconColor, size: iconSize),
            onPressed: () => setState(() {
              final opening = !_showHistoricalPanel;
              _closeAllPanels();
              _showHistoricalPanel = opening;
            }),
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
        // 6. Spending Analytics
        Tooltip(
          message: _showAnalyticsPanel ? 'Close Analytics' : 'Spending Analytics',
          child: IconButton(
            icon: Icon(Icons.insights, color: _showAnalyticsPanel ? activeColor : iconColor, size: iconSize),
            onPressed: () => setState(() {
              final opening = !_showAnalyticsPanel;
              _closeAllPanels();
              _showAnalyticsPanel = opening;
            }),
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
        // 7. Import (direct file picker, like budget screen)
        Tooltip(
          message: 'Import File',
          child: IconButton(
            icon: const Icon(Icons.upload_file, color: iconColor, size: iconSize),
            onPressed: _uploadExpenseFile,
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
        // 8. Add Expense (inline form toggle)
        Tooltip(
          message: _showInlineExpenseForm ? 'Close' : 'Add Expense',
          child: IconButton(
            icon: Icon(Icons.add_rounded, color: _showInlineExpenseForm ? activeColor : iconColor, size: iconSize),
            onPressed: () {
              if (_showInlineExpenseForm) { _closeExpenseForm(); } else { _openExpenseForm(); }
            },
            constraints: btnConstraints,
            padding: EdgeInsets.zero,
            splashRadius: 18,
          ),
        ),
      ],
    );
  }

  // ── Web: Inline Expense Form (matches budget inline form pattern) ──────

  Widget _buildInlineExpenseForm() {
    final isEditing = _editingExpense != null;
    const controlColor = Color(0xFF64748B);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Label
          Icon(
            isEditing ? Icons.edit_note_rounded : Icons.add_rounded,
            color: AppColors.primary, size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            isEditing ? 'Edit Expense' : 'Add Expense',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(width: 12),
          // Category dropdown
          SizedBox(
            width: 130, height: 32,
            child: DropdownButtonFormField<String>(
              value: _formExpenseCategory,
              isDense: true,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary)),
              ),
              items: _expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) { if (v != null) setState(() => _formExpenseCategory = v); },
            ),
          ),
          const SizedBox(width: 8),
          // Amount
          SizedBox(
            width: 90, height: 32,
            child: TextField(
              controller: _formExpenseAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: '₹ 0.00',
                hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Description
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _formExpenseDescController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Description',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Tags
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _formExpenseTagsController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g. mom, school',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Action icons
          IconButton(
            tooltip: isEditing ? 'Update' : 'Save',
            onPressed: _saveExpenseForm,
            icon: const Icon(Icons.check_circle_outline_rounded),
            color: controlColor, iconSize: 20,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero, splashRadius: 18,
          ),
          if (!isEditing)
            IconButton(
              tooltip: 'Add & new',
              onPressed: () async { await _saveExpenseForm(); },
              icon: const Icon(Icons.add_circle_outline_rounded),
              color: controlColor, iconSize: 20,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero, splashRadius: 18,
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: _closeExpenseForm,
            icon: const Icon(Icons.close_rounded),
            color: controlColor, iconSize: 20,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero, splashRadius: 18,
          ),
        ],
      ),
    );
  }

  // ── Web: Transaction List widget ─────────────────────────────────────────

  Widget _buildWebTransactionList(List<Expense> filtered, bool isDark, Color primary) {
    final controls = _buildExpenseListControls();

    if (filtered.isEmpty) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [controls],
                  ),
                ),
                if (_showInlineExpenseForm)
                  _buildInlineExpenseForm(),
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(AppIcons.receiptOutlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        _selectedCategoryFilter != null
                            ? 'No $_selectedCategoryFilter transactions this month'
                            : 'No transactions this month',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 4),
                      Text('Add your first expense to get started', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          if (_showCalendarDropdown)
            Positioned(
              top: 48, right: 8,
              child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), child: _buildInlineCalendar(isDark, primary)),
            ),
        ],
      );
    }

    final filteredTotal = filtered.fold<double>(0.0, (s, e) => s + e.amount);
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final overallRatio = totalBudget > 0 ? (filteredTotal / totalBudget).clamp(0.0, 1.0) : 0.0;
    final overallColor = overallRatio > 0.9 ? AppColors.error : overallRatio > 0.7 ? AppColors.warningDark : AppColors.successDark;

    // Build grouped rows
    final grouped = _groupedExpenses(filtered);
    final showGroupHeaders = _expenseGroupBy != 'none';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with summary + controls
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Transactions',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text('${filtered.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary)),
                        ),
                        const Spacer(),
                        controls,
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Overall progress bar
                    if (totalBudget > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: overallRatio,
                          minHeight: 6,
                          backgroundColor: isDark ? AppColors.grey800 : const Color(0xFFEEF2F6),
                          valueColor: AlwaysStoppedAnimation<Color>(overallColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Spent: ${_fmtCurrency(filteredTotal)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                        if (totalBudget > 0)
                          Text('Budget: ${_fmtCurrency(totalBudget)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              // Inline expense form slides down, pushing rows
              if (_showInlineExpenseForm)
                _buildInlineExpenseForm(),
              // Transaction rows (scrollable) — grouped or flat
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in grouped.entries) ...[
                        if (showGroupHeaders && entry.key.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                            child: Row(children: [
                              Container(width: 3, height: 14, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 8),
                              Text(entry.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.3)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                                child: Text('${entry.value.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey[500])),
                              ),
                            ]),
                          ),
                        ...entry.value.map((expense) => _buildWebTransactionRow(expense, isDark)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Calendar overlay inside card
        if (_showCalendarDropdown)
          Positioned(
            top: 48, right: 8,
            child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), child: _buildInlineCalendar(isDark, primary)),
          ),
      ],
    );
  }

  // ── Web: Inline Add Expense Panel ────────────────────────────────────────

  Widget _buildInlineAddExpensePanel(bool isDark, Color primary) {
    return _InlineAddExpensePanel(
      onSaved: () {
        setState(() => _showAddExpensePanel = false);
        _loadExpenses();
      },
      onCancel: () => setState(() => _showAddExpensePanel = false),
    );
  }

  // ── Web: Inline Import Panel ─────────────────────────────────────────────

  Widget _buildInlineImportPanel(bool isDark, Color primary) {
    return _InlineImportPanel(
      onDone: () {
        setState(() => _showImportPanel = false);
        _loadExpenses();
      },
      onCancel: () => setState(() => _showImportPanel = false),
    );
  }

  // ── Web: Inline Transaction Detail ───────────────────────────────────────

  Widget _buildInlineTransactionDetail(bool isDark, Color primary) {
    final expense = _selectedExpenseDetail!;
    return _InlineTransactionDetailPanel(
      expense: expense,
      onSaved: () {
        setState(() => _selectedExpenseDetail = null);
        _loadExpenses();
      },
      onDelete: () => _deleteExpenseInline(expense),
      onClose: () => setState(() => _selectedExpenseDetail = null),
    );
  }

  Future<void> _deleteExpenseInline(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Are you sure you want to delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _expenseService.deleteExpense(
        expenseId: expense.id,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      setState(() => _selectedExpenseDetail = null);
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: $e')),
        );
      }
    }
  }

  // ── Web: Historical Performance Panel ────────────────────────────────────

  Widget _buildHistoricalPerformancePanel(bool isDark, Color primary) {
    return _HistoricalPerformancePanel(
      expenses: _expenses,
      budgets: _budgets,
      onClose: () => setState(() => _showHistoricalPanel = false),
    );
  }

  // ── Web: Spending Analytics Panel ────────────────────────────────────────

  Widget _buildSpendingAnalyticsPanel(bool isDark, Color primary) {
    return _SpendingAnalyticsPanel(
      expenses: _expenses,
      budgets: _budgets,
      onClose: () => setState(() => _showAnalyticsPanel = false),
    );
  }

  // ── Web: AI Insights Panel ───────────────────────────────────────────────

  Widget _buildAIInsightsPanel(bool isDark, Color primary) {
    return _AIInsightsPanel(
      onClose: () => setState(() => _showAIInsightsPanel = false),
    );
  }

  Widget _webTabChip({
    required String label,
    required IconData icon,
    required bool active,
    bool comingSoon = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? const Color(0xFF0D7FF2) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: active ? const Color(0xFF0D7FF2) : null),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF0D7FF2) : null,
            ),
          ),
          if (comingSoon) ...[
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded, size: 11, color: Colors.red),
          ],
        ],
      ),
    );
  }
}

class _ExpenseCategoryItem {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _ExpenseCategoryItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

// ── Inline Add Expense Panel (shown in web layout) ───────────────────────

class _InlineAddExpensePanel extends StatefulWidget {
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _InlineAddExpensePanel({required this.onSaved, required this.onCancel});

  @override
  State<_InlineAddExpensePanel> createState() => _InlineAddExpensePanelState();
}

class _InlineAddExpensePanelState extends State<_InlineAddExpensePanel> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  String _selectedCategory = 'Groceries';
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;
  bool _showDatePicker = false;

  static const _categories = [
    'Groceries', 'Entertainment', 'Education', 'Personal Care',
    'Physical Wellness', 'Mental Wellness', 'Convenience Food',
    'Senior Care', 'Pet Care', 'Vacation', 'Party',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final tags = parseTags(_tagsController.text);
      await ExpenseService().createExpense(
        amount: amount,
        category: _selectedCategory,
        description: description,
        date: _selectedDate,
        tags: tags,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added successfully')),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  late DateTime _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month);

  void _toggleDatePicker() => setState(() => _showDatePicker = !_showDatePicker);
  void _prevMonth() => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1));
  void _nextMonth() {
    final next = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
    if (!next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) {
      setState(() => _calendarMonth = next);
    }
  }

  Widget _buildInlineCalendar() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday % 7; // Sunday = 0
    final earliest = today.subtract(const Duration(days: 365));
    // Allow selecting up to end of current month
    final lastSelectable = DateTime(now.year, now.month + 1, 0); // last day of current month
    final canGoPrev = DateTime(_calendarMonth.year, _calendarMonth.month - 1).isAfter(DateTime(earliest.year, earliest.month - 1));
    final canGoNext = !DateTime(_calendarMonth.year, _calendarMonth.month + 1).isAfter(DateTime(now.year, now.month));

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        children: [
          // Month nav
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: canGoPrev ? _prevMonth : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: canGoPrev ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_left_rounded, size: 20, color: canGoPrev ? const Color(0xFF7C4DFF) : Colors.grey[300]),
                ),
              ),
              Text(
                '${_monthNames[_calendarMonth.month]} ${_calendarMonth.year}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.deepPurple[700]),
              ),
              InkWell(
                onTap: canGoNext ? _nextMonth : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: canGoNext ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: canGoNext ? const Color(0xFF7C4DFF) : Colors.grey[300]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day-of-week headers
          Row(
            children: _dayLabels.map((d) => Expanded(
              child: Center(child: Text(d, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepPurple[300]))),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Day grid
          ...List.generate(6, (week) {
            return Row(
              children: List.generate(7, (dow) {
                final dayIndex = week * 7 + dow - startWeekday + 1;
                if (dayIndex < 1 || dayIndex > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }
                final date = DateTime(_calendarMonth.year, _calendarMonth.month, dayIndex);
                final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
                final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
                final isFuture = date.isAfter(lastSelectable);
                final isTooOld = date.isBefore(earliest);
                final isDisabled = isFuture || isTooOld;

                return Expanded(
                  child: GestureDetector(
                    onTap: isDisabled ? null : () {
                      setState(() {
                        _selectedDate = date;
                        _showDatePicker = false;
                      });
                    },
                    child: Container(
                      height: 32,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)])
                            : null,
                        color: isToday && !isSelected ? Colors.deepPurple.shade100 : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$dayIndex',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : isDisabled
                                    ? Colors.grey[300]
                                    : isToday
                                        ? Colors.deepPurple[700]
                                        : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          // Quick pick row
          const SizedBox(height: 8),
          Row(
            children: [
              _quickPickChip('Today', today),
              const SizedBox(width: 6),
              _quickPickChip('Yesterday', today.subtract(const Duration(days: 1))),
              const SizedBox(width: 6),
              _quickPickChip('2 days ago', today.subtract(const Duration(days: 2))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickPickChip(String label, DateTime date) {
    final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedDate = date;
          _calendarMonth = DateTime(date.year, date.month);
          _showDatePicker = false;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)]) : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? null : Border.all(color: Colors.deepPurple.shade100),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.deepPurple[400]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Add Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Amount
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'e.g. Weekly groceries',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          // Category dropdown
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedCategory = v); },
          ),
          const SizedBox(height: 12),
          // ── Modern inline date picker ────────────────────────────
          InkWell(
            onTap: _toggleDatePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _showDatePicker
                      ? [const Color(0xFF7C4DFF), const Color(0xFF536DFE)]
                      : [Colors.grey.shade50, Colors.grey.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _showDatePicker ? const Color(0xFF7C4DFF) : Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: _showDatePicker ? Colors.white : const Color(0xFF7C4DFF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedDate.day} ${_monthNames[_selectedDate.month]} ${_selectedDate.year}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _showDatePicker ? Colors.white : Colors.grey[800],
                      ),
                    ),
                  ),
                  Icon(
                    _showDatePicker ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: _showDatePicker ? Colors.white : Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),
          // Slide-down calendar
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildInlineCalendar(),
            crossFadeState: _showDatePicker ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
          const SizedBox(height: 12),
          // Tags
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: 'Tags (optional)',
              hintText: 'mom, school, medical',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),
          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, size: 18),
                        SizedBox(width: 6),
                        Text('Save Transaction', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddEditExpenseScreen extends StatefulWidget {
  final Expense? expense;

  const AddEditExpenseScreen({super.key, this.expense});

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();

  List<String> _tagSuggestions = [];
  String _selectedCategory = 'food';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isCategorizing = false;

  @override
  void initState() {
    super.initState();
    if (widget.expense != null) {
      _amountController.text = widget.expense!.amount.toStringAsFixed(2);
      _notesController.text = widget.expense!.notes ?? '';
      _tagsController.text = joinTags(widget.expense!.tags);
      _selectedCategory = widget.expense!.category;
      _selectedDate = widget.expense!.date;
    }
    _loadTagSuggestions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadTagSuggestions() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final familyService = FamilyService(
        supabaseUrl: authService.supabaseUrl,
        authService: authService,
      );
      final members = await familyService.fetchMembers();
      if (!mounted) return;
      setState(() {
        _tagSuggestions = members
            .map((member) => member.displayLabel.trim())
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    } catch (_) {
      // Tag suggestions are optional.
    }
  }

  Future<void> _autoCategorize() async {
    final description = _notesController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a note first so AI can suggest a category')),
      );
      return;
    }

    setState(() => _isCategorizing = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().categorizeExpense(
        description: description,
        amount: double.tryParse(_amountController.text),
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      final category = (result['category'] as String?)?.toLowerCase() ?? '';
      const validCategories = ['food', 'transport', 'shopping', 'utilities', 'entertainment', 'other'];
      setState(() {
        _selectedCategory = validCategories.contains(category) ? category : 'other';
        _isCategorizing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCategorizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto-categorize failed: $e')),
      );
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'New Expense',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Amount Display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            '\$',
                            style: TextStyle(
                              fontSize: 40,
                              color: Colors.grey,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _amountController.text.isEmpty
                              ? '0.00'
                              : _amountController.text,
                          style: const TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Note field
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'Add a note...',
                        hintStyle: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 32),

                    TagInputSection(
                      controller: _tagsController,
                      suggestions: _tagSuggestions,
                      helperText:
                          'Use family members or keywords like mom, school, medical, trip.',
                    ),

                    const SizedBox(height: 28),

                    // Category Selection
                    Row(
                      children: [
                        Text(
                          'SELECT CATEGORY',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (_isCategorizing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          InkWell(
                            onTap: _autoCategorize,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 14, color: Colors.deepPurple),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Auto',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Category Grid
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.0,
                      children: [
                        _buildCategoryButton(
                            'food', 'Food', AppIcons.food, Colors.orange),
                        _buildCategoryButton('transport', 'Transport',
                            AppIcons.transport, Colors.blue),
                        _buildCategoryButton('shopping', 'Shopping',
                            AppIcons.shopping, Colors.pink),
                        _buildCategoryButton('utilities', 'Bills',
                            AppIcons.utilities, Colors.green),
                        _buildCategoryButton('entertainment', 'Entertain',
                            AppIcons.entertainment, Colors.purple),
                        _buildCategoryButton(
                            'other', 'Others', Icons.more_horiz, Colors.grey),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Bottom options row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Today button
                        InkWell(
                          onTap: _selectDate,
                          child: Row(
                            children: [
                              Icon(AppIcons.calendar,
                                  color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _selectedDate.day == DateTime.now().day &&
                                        _selectedDate.month ==
                                            DateTime.now().month &&
                                        _selectedDate.year ==
                                            DateTime.now().year
                                    ? 'Today'
                                    : '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Add Receipt button
                        InkWell(
                          onTap: () {
                            // TODO: Add receipt upload functionality
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Receipt upload coming soon!')),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(Icons.camera_alt_outlined,
                                  color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Add Receipt',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Save Button
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _isLoading ? null : () => _showAmountDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1D2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Save Transaction',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.check, size: 20),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryButton(
      String category, String label, IconData icon, Color color) {
    final isSelected = _selectedCategory == category;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = category;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 36,
              color: isSelected ? color : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? color : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAmountDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Amount'),
        content: TextFormField(
          controller: _amountController,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '\$ ',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          onFieldSubmitted: (value) {
            Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _amountController.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {});
      // Now save the expense
      await _saveExpenseWithValidation();
    }
  }

  Future<void> _saveExpenseWithValidation() async {
    // Validate amount
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final expenseService = ExpenseService();

      final description = _notesController.text.trim();
      final notes = _notesController.text.trim();
      final tags = parseTags(_tagsController.text);

      if (widget.expense == null) {
        // Create new expense
        await expenseService.createExpense(
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      } else {
        // Update existing expense
        await expenseService.updateExpense(
          expenseId: widget.expense!.id,
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
          tags: tags,
          supabaseUrl: authService.supabaseUrl,
          idToken: await authService.getIdToken(),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.expense == null
                ? 'Expense added successfully'
                : 'Expense updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e')),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline Import Panel (right side, same look as Add Expense)
// ══════════════════════════════════════════════════════════════════════════════

class _InlineImportPanel extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const _InlineImportPanel({required this.onDone, required this.onCancel});

  @override
  State<_InlineImportPanel> createState() => _InlineImportPanelState();
}

class _InlineImportPanelState extends State<_InlineImportPanel> {
  String _importType = 'expenses';
  String? _csvText;
  String? _fileName;
  String? _errorMessage;
  bool _isValidating = false;
  bool _isImporting = false;
  ImportPreviewResult? _preview;
  ImportCommitResult? _commitResult;

  bool get _fileSelected => _csvText != null;

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    if (file.bytes == null) {
      setState(() => _errorMessage = 'Could not read file. Please try again.');
      return;
    }

    const maxBytes = 5 * 1024 * 1024;
    if (file.bytes!.length > maxBytes) {
      setState(() => _errorMessage = 'File exceeds the 5 MB limit.');
      return;
    }

    String text;
    try {
      text = utf8.decode(file.bytes!);
    } catch (_) {
      setState(() => _errorMessage = 'File must be UTF-8 encoded.');
      return;
    }

    if (text.trim().isEmpty) {
      setState(() => _errorMessage = 'The selected file is empty.');
      return;
    }

    setState(() {
      _csvText = text;
      _fileName = file.name;
      _preview = null;
      _commitResult = null;
    });
  }

  Future<void> _validate() async {
    if (_csvText == null) return;
    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _preview = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = ImportService(supabaseUrl: auth.supabaseUrl, authService: auth);
      final result = await svc.preview(type: _importType, csvText: _csvText!);
      setState(() {
        _preview = result;
        _isValidating = false;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isValidating = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during validation.';
        _isValidating = false;
      });
    }
  }

  Future<void> _import() async {
    if (_csvText == null) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = ImportService(supabaseUrl: auth.supabaseUrl, authService: auth);
      final result = await svc.commit(type: _importType, csvText: _csvText!);
      setState(() {
        _commitResult = result;
        _isImporting = false;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isImporting = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during import.';
        _isImporting = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _csvText = null;
      _fileName = null;
      _preview = null;
      _commitResult = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _commitResult != null ? _buildDone() : _buildForm(),
    );
  }

  Widget _buildDone() {
    final result = _commitResult!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Icon(Icons.check_circle_outline, color: Colors.green[600], size: 56),
        const SizedBox(height: 12),
        Text(
          '${result.imported} ${result.type} imported',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('Batch: ${result.batchId}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _reset,
                child: const Text('Import Another'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: widget.onDone,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          children: [
            const Text('Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Type selector
        Row(
          children: [
            ChoiceChip(
              label: const Text('Expenses'),
              selected: _importType == 'expenses',
              onSelected: (_) => setState(() {
                _importType = 'expenses';
                _csvText = null;
                _fileName = null;
                _preview = null;
              }),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Budgets'),
              selected: _importType == 'budgets',
              onSelected: (_) => setState(() {
                _importType = 'budgets';
                _csvText = null;
                _fileName = null;
                _preview = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // File picker
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(_fileName ?? 'Select Excel / PDF / Word / Image'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
        ),

        if (_fileName != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green[600], size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(_fileName!, style: TextStyle(color: Colors.green[600], fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              InkWell(
                onTap: () => setState(() {
                  _csvText = null;
                  _fileName = null;
                  _preview = null;
                }),
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ],
          ),
        ],

        // Error
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 12, color: Colors.red[700]))),
              ],
            ),
          ),
        ],

        // Preview results
        if (_preview != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _preview!.isClean ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_preview!.validCount} valid, ${_preview!.errorCount} error${_preview!.errorCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _preview!.isClean ? Colors.green[700] : Colors.orange[800]),
                ),
                if (_preview!.hasErrors) ...[
                  const SizedBox(height: 6),
                  ...(_preview!.errors.take(5).map((e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Row ${e.row}: ${e.field} — ${e.message}', style: TextStyle(fontSize: 11, color: Colors.red[600])),
                  ))),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),

        // Action buttons
        if (_preview == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _fileSelected && !_isValidating ? _validate : null,
              icon: _isValidating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(_isValidating ? 'Validating...' : 'Validate'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

        if (_preview != null && _preview!.isClean)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_isImporting ? _import : null,
              icon: _isImporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload, size: 18),
              label: Text(_isImporting ? 'Importing...' : 'Import ${_preview!.validCount} rows'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

        if (_preview != null && _preview!.hasErrors) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload corrected file'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline Transaction Detail Panel (right side, same look as Add Expense)
// ══════════════════════════════════════════════════════════════════════════════

class _InlineTransactionDetailPanel extends StatefulWidget {
  final Expense expense;
  final VoidCallback onSaved;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _InlineTransactionDetailPanel({
    required this.expense,
    required this.onSaved,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<_InlineTransactionDetailPanel> createState() => _InlineTransactionDetailPanelState();
}

class _InlineTransactionDetailPanelState extends State<_InlineTransactionDetailPanel> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _amountCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _tagsCtrl;
  late String _editCategory;
  late DateTime _editDate;

  static const _categories = [
    'Groceries', 'Entertainment', 'Education', 'Personal Care',
    'Physical Wellness', 'Mental Wellness', 'Convenience Food',
    'Senior Care', 'Pet Care', 'Vacation', 'Party', 'Income', 'Salary',
  ];

  @override
  void initState() {
    super.initState();
    _initEditing();
  }

  void _initEditing() {
    _amountCtrl = TextEditingController(text: widget.expense.amount.toStringAsFixed(2));
    _descCtrl = TextEditingController(text: widget.expense.description);
    _tagsCtrl = TextEditingController(text: widget.expense.tags.join(', '));
    _editCategory = widget.expense.category;
    _editDate = widget.expense.date;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final tags = parseTags(_tagsCtrl.text);
      await ExpenseService().updateExpense(
        expenseId: widget.expense.id,
        amount: amount,
        category: _editCategory,
        description: desc,
        date: _editDate,
        tags: tags,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense updated')));
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _isEditing ? _buildEditView() : _buildDetailView(),
    );
  }

  Widget _buildDetailView() {
    final e = widget.expense;
    final isIncome = e.category.toLowerCase() == 'income' || e.category.toLowerCase() == 'salary';
    final d = e.date;
    final dateStr = '${d.day}/${d.month}/${d.year}';
    final bgColor = AppColors.getCategoryColor(e.category);
    final iconColor = AppColors.getCategoryIconColor(e.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Transaction Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
              child: Icon(AppIcons.getCategoryIcon(e.category), size: 28, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              '${isIncome ? '+' : '-'} ₹${e.amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isIncome ? AppColors.success : AppColors.error),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        _detailRow(Icons.description_outlined, 'Description', e.description),
        _detailRow(Icons.category_outlined, 'Category', e.category),
        _detailRow(Icons.calendar_today_outlined, 'Date', dateStr),
        _detailRow(Icons.source_outlined, 'Source', e.source),
        if (e.notes != null && e.notes!.isNotEmpty) _detailRow(Icons.notes_outlined, 'Notes', e.notes!),
        if (e.tags.isNotEmpty) _detailRow(Icons.label_outlined, 'Tags', e.tags.join(', ')),
        _detailRow(Icons.verified_outlined, 'Status', e.isApproved ? 'Approved' : 'Pending'),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onDelete,
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[600]),
              label: Text('Delete', style: TextStyle(color: Colors.red[600])),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: BorderSide(color: Colors.red[300]!)),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildEditView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Edit Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: () => setState(() => _isEditing = false),
              icon: const Icon(Icons.close, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (₹)', prefixText: '₹ ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          decoration: InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _categories.contains(_editCategory) ? _editCategory : _categories.first,
          decoration: InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: (v) { if (v != null) setState(() => _editCategory = v); },
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _editDate,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now(),
            );
            if (date != null && mounted) setState(() => _editDate = date);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text('${_editDate.day}/${_editDate.month}/${_editDate.year}', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tagsCtrl,
          decoration: InputDecoration(
            labelText: 'Tags (optional)', hintText: 'mom, school, medical',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : () => setState(() => _isEditing = false),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _isSaving ? null : _saveEdit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check, size: 18), SizedBox(width: 6),
                      Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Historical Performance Panel
// ══════════════════════════════════════════════════════════════════════════════

class _HistoricalPerformancePanel extends StatelessWidget {
  final List<Expense> expenses;
  final List<Budget> budgets;
  final VoidCallback onClose;

  const _HistoricalPerformancePanel({
    required this.expenses,
    required this.budgets,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Group expenses by month for last 6 months
    final monthlyData = <String, double>{};
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final key = '${_monthAbbr(m.month)} ${m.year}';
      monthlyData[key] = 0;
    }
    for (final e in expenses) {
      final d = e.date;
      final diff = (now.year * 12 + now.month) - (d.year * 12 + d.month);
      if (diff >= 0 && diff < 6) {
        final key = '${_monthAbbr(d.month)} ${d.year}';
        monthlyData[key] = (monthlyData[key] ?? 0) + e.amount;
      }
    }

    final maxSpend = monthlyData.values.fold<double>(0, (a, b) => a > b ? a : b);
    final totalBudget = budgets.fold<double>(0, (s, b) => s + b.amount);
    final currentMonthSpend = monthlyData.values.lastOrNull ?? 0;
    final prevMonthSpend = monthlyData.values.length >= 2
        ? monthlyData.values.toList()[monthlyData.values.length - 2]
        : 0.0;
    final trend = prevMonthSpend > 0
        ? ((currentMonthSpend - prevMonthSpend) / prevMonthSpend * 100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 20, color: const Color(0xFF7C4DFF)),
              const SizedBox(width: 8),
              const Text('Historical Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary cards
          Row(
            children: [
              Expanded(child: _miniCard('This Month', '₹${currentMonthSpend.toStringAsFixed(0)}', Colors.deepPurple)),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Budget', '₹${totalBudget.toStringAsFixed(0)}', Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _miniCard(
                'Trend',
                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                trend > 0 ? Colors.red : Colors.green,
              )),
            ],
          ),
          const SizedBox(height: 20),

          // Monthly bar chart
          const Text('Last 6 Months', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 12),

          ...monthlyData.entries.map((entry) {
            final fraction = maxSpend > 0 ? (entry.value / maxSpend).clamp(0.02, 1.0) : 0.02;
            final isCurrentMonth = entry.key == monthlyData.keys.last;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text(entry.key, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: isCurrentMonth ? FontWeight.w700 : FontWeight.w400))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: Colors.grey[100],
                        color: isCurrentMonth ? const Color(0xFF7C4DFF) : Colors.deepPurple[200],
                        minHeight: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: Text('₹${entry.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]), textAlign: TextAlign.right)),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Budget utilization
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: currentMonthSpend <= totalBudget ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  currentMonthSpend <= totalBudget ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  size: 18,
                  color: currentMonthSpend <= totalBudget ? Colors.green[700] : Colors.red[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentMonthSpend <= totalBudget
                        ? 'Within budget — ₹${(totalBudget - currentMonthSpend).toStringAsFixed(0)} remaining'
                        : 'Over budget by ₹${(currentMonthSpend - totalBudget).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: currentMonthSpend <= totalBudget ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  static String _monthAbbr(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m.clamp(1, 12)];
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Spending Analytics Panel
// ══════════════════════════════════════════════════════════════════════════════

class _SpendingAnalyticsPanel extends StatelessWidget {
  final List<Expense> expenses;
  final List<Budget> budgets;
  final VoidCallback onClose;

  const _SpendingAnalyticsPanel({
    required this.expenses,
    required this.budgets,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Current month expenses
    final currentMonthExpenses = expenses.where((e) =>
        e.date.year == now.year && e.date.month == now.month).toList();

    // Category breakdown
    final categorySpend = <String, double>{};
    for (final e in currentMonthExpenses) {
      categorySpend[e.category] = (categorySpend[e.category] ?? 0) + e.amount;
    }
    final sortedCategories = categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalSpend = sortedCategories.fold<double>(0, (s, e) => s + e.value);
    final topCategory = sortedCategories.isNotEmpty ? sortedCategories.first : null;

    // Daily average
    final daysInMonth = now.day;
    final dailyAvg = daysInMonth > 0 ? totalSpend / daysInMonth : 0.0;

    // Transaction count
    final txnCount = currentMonthExpenses.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 20, color: const Color(0xFF00ACC1)),
              const SizedBox(width: 8),
              const Text('Spending Analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary stats
          Row(
            children: [
              Expanded(child: _statCard('Total', '₹${totalSpend.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, const Color(0xFF00ACC1))),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Daily Avg', '₹${dailyAvg.toStringAsFixed(0)}', Icons.trending_up_outlined, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Txns', txnCount.toString(), Icons.receipt_long_outlined, Colors.indigo)),
            ],
          ),
          const SizedBox(height: 20),

          // Category breakdown heading
          Row(
            children: [
              const Text('Category Breakdown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
              const Spacer(),
              if (topCategory != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Top: ${topCategory.key}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red[600])),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Category bars
          if (sortedCategories.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('No expenses this month', style: TextStyle(color: Colors.grey))),
            )
          else
            ...sortedCategories.take(8).map((entry) {
              final pct = totalSpend > 0 ? (entry.value / totalSpend * 100) : 0.0;
              final budgetForCategory = budgets.where((b) => b.category == entry.key).firstOrNull;
              final isOverBudget = budgetForCategory != null && entry.value > budgetForCategory.amount;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.getCategoryIcon(entry.key), size: 14, color: AppColors.getCategoryIconColor(entry.key)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                        Text('₹${entry.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isOverBudget ? Colors.red[600] : Colors.grey[700])),
                        const SizedBox(width: 4),
                        Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0, 1),
                        backgroundColor: Colors.grey[100],
                        color: isOverBudget ? Colors.red[400] : AppColors.getCategoryColor(entry.key),
                        minHeight: 6,
                      ),
                    ),
                    if (budgetForCategory != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Budget: ₹${budgetForCategory.amount.toStringAsFixed(0)}${isOverBudget ? ' (over by ₹${(entry.value - budgetForCategory.amount).toStringAsFixed(0)})' : ''}',
                        style: TextStyle(fontSize: 9, color: isOverBudget ? Colors.red[400] : Colors.grey[400]),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AI Insights Panel
// ══════════════════════════════════════════════════════════════════════════════

class _AIInsightsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _AIInsightsPanel({required this.onClose});

  @override
  State<_AIInsightsPanel> createState() => _AIInsightsPanelState();
}

class _AIInsightsPanelState extends State<_AIInsightsPanel> {
  bool _loading = false;
  String? _analysis;
  String? _error;

  String _chatInput = '';
  final _chatController = TextEditingController();
  final List<_ChatMessage> _chatMessages = [];
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalysis() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) setState(() { _analysis = result['analysis'] as String?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _sendChat() async {
    final msg = _chatController.text.trim();
    if (msg.isEmpty) return;
    _chatController.clear();
    setState(() {
      _chatMessages.add(_ChatMessage(text: msg, isUser: true));
      _chatLoading = true;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().sendChatMessage(
        message: msg,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(text: result['response'] as String? ?? 'No response', isUser: false));
          _chatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(text: 'Error: $e', isUser: false));
          _chatLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: const Color(0xFF9C27B0)),
              const SizedBox(width: 8),
              const Text('AI Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _fetchAnalysis,
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh analysis',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Budget Analysis section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.purple.shade50, Colors.blue.shade50]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 16, color: Colors.purple[600]),
                    const SizedBox(width: 6),
                    Text('Budget Analysis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple[700])),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  ))
                else if (_error != null)
                  Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red[600]))
                else if (_analysis != null)
                  Text(_analysis!, style: const TextStyle(fontSize: 12, height: 1.5))
                else
                  Text('Tap refresh to generate AI analysis', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Chat section - fills remaining space
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 16, color: Colors.purple[400]),
                    const SizedBox(width: 6),
                    Text('Ask AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple[600])),
                  ],
                ),
                const SizedBox(height: 8),

                // Chat messages
                if (_chatMessages.isNotEmpty) ...[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _chatMessages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _chatMessages[i];
                          return Align(
                            alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: msg.isUser ? Colors.purple[100] : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: msg.isUser ? null : Border.all(color: Colors.grey[200]!),
                              ),
                              child: Text(msg.text, style: const TextStyle(fontSize: 12)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_chatLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text('Thinking...', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ] else
                  const Spacer(),

                // Chat input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: 'Ask about your finances...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _sendChat(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _chatLoading ? null : _sendChat,
                      icon: Icon(Icons.send_rounded, color: Colors.purple[600]),
                      tooltip: 'Send',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}

class _LeakageItem {
  final String category;
  final double amount;
  final String reason;
  final double severity;
  final IconData icon;
  final Color color;
  const _LeakageItem({required this.category, required this.amount, required this.reason, required this.severity, required this.icon, required this.color});
}

class _ProjectedItem {
  final String description;
  final String category;
  final double amount;
  final DateTime date;
  const _ProjectedItem({required this.description, required this.category, required this.amount, required this.date});
}

class _RewardIcon {
  final IconData icon;
  final Color color;
  final String label;
  const _RewardIcon(this.icon, this.color, this.label);
}

/// Mutable row for the expense preview dialog
class _ExpenseEditableRow {
  String description;
  String category;
  DateTime date;
  double amount;
  final bool isValid;
  final String? validationError;
  bool aiCategorized;
  String aiConfidence;

  _ExpenseEditableRow({
    required this.description,
    required this.category,
    required this.date,
    required this.amount,
    this.isValid = true,
    this.validationError,
    this.aiCategorized = false,
    this.aiConfidence = '',
  });
}

/// Rich Excel import preview dialog for expenses — matches budget's _ExcelPreviewDialog
class _ExpenseExcelPreviewDialog extends StatefulWidget {
  final List<_ExpenseEditableRow> rows;
  final AuthService authService;

  const _ExpenseExcelPreviewDialog({
    required this.rows,
    required this.authService,
  });

  @override
  State<_ExpenseExcelPreviewDialog> createState() => _ExpenseExcelPreviewDialogState();
}

class _ExpenseExcelPreviewDialogState extends State<_ExpenseExcelPreviewDialog> {
  late List<_ExpenseEditableRow> _editableRows;
  bool _isCategorizingWithAI = false;
  bool _aiCategorizationDone = false;
  String? _aiError;
  final List<String> _userAddedCategories = [];

  static const _validCategories = [
    'food', 'transport', 'utilities', 'shopping',
    'healthcare', 'entertainment', 'bank', 'other',
  ];

  static const _indianBanks = <String>[
    'iob', 'sbi', 'hdfc', 'icici', 'axis', 'kotak', 'pnb', 'bob', 'boi',
    'canara', 'union', 'idbi', 'yes bank', 'indusind', 'rbl', 'federal',
    'bandhan', 'au bank', 'au small', 'idfc', 'idfc first', 'cbi',
    'indian overseas', 'uco', 'allahabad', 'syndicate', 'andhra bank',
    'vijaya', 'dena', 'oriental', 'corporation bank', 'mahanagar',
    'city union', 'karur vysya', 'kvb', 'south indian', 'tamilnad mercantile',
    'tmb', 'lakshmi vilas', 'dhanlaxmi', 'j&k bank', 'karnataka bank',
    'nainital', 'saraswat', 'fino', 'paytm', 'airtel payments', 'jio payments',
    'nps', 'ppf', 'mutual fund', 'mf', 'lic', 'bajaj', 'tata capital',
  ];

  static String _mapToValidCategory(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return 'other';
    if (_validCategories.contains(lower)) return lower;

    for (final bank in _indianBanks) {
      if (lower.contains(bank) || bank.contains(lower)) return 'bank';
    }

    const mapping = <String, List<String>>{
      'food': ['food', 'grocery', 'groceries', 'meal', 'dining', 'provisions',
        'kitchen', 'vegetables', 'fruits', 'milk', 'snack'],
      'transport': ['transport', 'travel', 'fuel', 'petrol', 'commut',
        'vehicle', 'car', 'bike', 'parking', 'auto', 'cab'],
      'utilities': ['utility', 'utilities', 'electric', 'water', 'internet',
        'wifi', 'phone', 'mobile', 'recharge', 'bill', 'maintenance', 'rent',
        'housing', 'household', 'emi', 'act'],
      'shopping': ['shopping', 'cloth', 'fashion', 'amazon', 'flipkart',
        'online', 'gadget', 'electronics'],
      'healthcare': ['health', 'medical', 'medicine', 'doctor', 'hospital',
        'pharmacy', 'insurance', 'gym', 'fitness', 'dental', 'parlour'],
      'entertainment': ['entertainment', 'movie', 'netflix', 'subscription',
        'hobby', 'game', 'sport', 'outing', 'party', 'fun', 'leisure',
        'class', 'classes', 'yoga', 'violin', 'cello', 'music'],
      'bank': ['bank', 'neft', 'imps', 'rtgs', 'upi', 'transfer', 'deposit',
        'withdrawal', 'atm', 'cheque', 'saving', 'current account', 'fd',
        'fixed deposit', 'rd', 'recurring'],
    };

    for (final entry in mapping.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'other';
  }

  @override
  void initState() {
    super.initState();
    _editableRows = List.of(widget.rows);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runAICategorization();
    });
  }

  Future<void> _runAICategorization() async {
    if (!mounted) return;
    setState(() {
      _isCategorizingWithAI = true;
      _aiError = null;
    });

    try {
      final authService = widget.authService;
      final validRows = _editableRows.where((r) => r.isValid).toList();
      if (validRows.isEmpty) return;

      final items = validRows.map((r) => <String, dynamic>{
        'description': r.description.isNotEmpty ? r.description : r.category,
        'amount': r.amount,
      }).toList();

      final results = await AIService().categorizeBudgetItems(
        items: items,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      setState(() {
        int ri = 0;
        for (final row in _editableRows) {
          if (row.isValid && ri < results.length) {
            row.category = results[ri]['category'] ?? row.category;
            row.aiConfidence = results[ri]['confidence'] ?? 'low';
            row.aiCategorized = true;
            ri++;
          }
        }
        _isCategorizingWithAI = false;
        _aiCategorizationDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCategorizingWithAI = false;
        _aiError = 'AI categorization failed: $e';
      });
    }
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${_monthNames[d.month - 1]}-${d.year}';

  @override
  Widget build(BuildContext context) {
    final validRows = _editableRows.where((r) => r.isValid).toList();
    final invalidRows = _editableRows.where((r) => !r.isValid).toList();
    final totalAmount = validRows.fold<double>(0, (sum, r) => sum + r.amount);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Excel Import Preview')),
        ],
      ),
      content: SizedBox(
        width: 850,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _chip('${validRows.length} valid', AppColors.success),
                  const SizedBox(width: 8),
                  if (invalidRows.isNotEmpty)
                    _chip('${invalidRows.length} invalid', AppColors.error),
                  const Spacer(),
                  Text(
                    'Total: ₹${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Review expenses below. You can change categories before importing.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
            ),
            if (_isCategorizingWithAI)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('AI is categorizing items...', style: TextStyle(fontSize: 11, color: Colors.deepPurple[400], fontWeight: FontWeight.w600)),
                ]),
              ),
            if (_aiCategorizationDone)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.deepPurple[400]),
                  const SizedBox(width: 6),
                  Text('AI categorized. Review & correct if needed.', style: TextStyle(fontSize: 11, color: Colors.deepPurple[400], fontWeight: FontWeight.w600)),
                ]),
              ),
            if (_aiError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_aiError!, style: const TextStyle(fontSize: 11, color: AppColors.warningDark)),
              ),
            const SizedBox(height: 8),
            // Table
            Expanded(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const <int, TableColumnWidth>{
                    0: FixedColumnWidth(32),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1),
                    4: FlexColumnWidth(0.8),
                    5: FixedColumnWidth(36),
                    6: FixedColumnWidth(36),
                  },
                  border: TableBorder.all(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                      children: const [
                        _ExpTableHeader('#'),
                        _ExpTableHeader('Description'),
                        _ExpTableHeader('Category'),
                        _ExpTableHeader('Date'),
                        _ExpTableHeader('Amount'),
                        _ExpTableHeader(''),
                        _ExpTableHeader(''),
                      ],
                    ),
                    for (int idx = 0; idx < _editableRows.length; idx++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: _editableRows[idx].isValid
                              ? null
                              : AppColors.error.withValues(alpha: 0.06),
                        ),
                        children: [
                          _ExpTableCell(
                            Text('${idx + 1}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                          _ExpTableCell(
                            Text(
                              _editableRows[idx].description,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _ExpTableCell(
                            _ExpCategoryEditor(
                              value: _editableRows[idx].category,
                              enabled: _editableRows[idx].isValid,
                              extraCategories: _userAddedCategories,
                              onChanged: (v) {
                                setState(() {
                                  _editableRows[idx].category = v;
                                  if (!_validCategories.contains(v) &&
                                      !_userAddedCategories.contains(v)) {
                                    _userAddedCategories.add(v);
                                  }
                                });
                              },
                            ),
                          ),
                          _ExpTableCell(
                            Text(
                              _editableRows[idx].isValid
                                  ? _formatDate(_editableRows[idx].date)
                                  : _editableRows[idx].validationError ?? 'Invalid',
                              style: TextStyle(
                                fontSize: 12,
                                color: _editableRows[idx].isValid ? null : AppColors.error,
                              ),
                            ),
                          ),
                          _ExpTableCell(
                            Text(
                              _editableRows[idx].isValid
                                  ? '₹${_editableRows[idx].amount.toStringAsFixed(0)}'
                                  : '',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          _ExpTableCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _editableRows[idx].isValid ? Icons.check_circle : Icons.error,
                                  color: _editableRows[idx].isValid ? AppColors.success : AppColors.error,
                                  size: 15,
                                ),
                                if (_editableRows[idx].aiCategorized) ...[
                                  const SizedBox(width: 3),
                                  Tooltip(
                                    message: 'AI: ${_editableRows[idx].aiConfidence} confidence',
                                    child: Container(
                                      width: 7, height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _editableRows[idx].aiConfidence == 'high'
                                            ? AppColors.success
                                            : _editableRows[idx].aiConfidence == 'medium'
                                                ? AppColors.warningDark
                                                : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _ExpTableCell(
                            Tooltip(
                              message: 'Remove row',
                              child: InkWell(
                                onTap: () => setState(() => _editableRows.removeAt(idx)),
                                borderRadius: BorderRadius.circular(4),
                                child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (invalidRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Invalid rows will be skipped. You can correct or delete them.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: validRows.isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'rows': _editableRows,
                  }),
          icon: const Icon(Icons.upload),
          label: Text('Import ${validRows.length} Items'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _ExpTableHeader extends StatelessWidget {
  final String text;
  const _ExpTableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class _ExpTableCell extends StatelessWidget {
  final Widget child;
  const _ExpTableCell(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    );
  }
}

class _ExpCategoryEditor extends StatefulWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final List<String>? extraCategories;

  const _ExpCategoryEditor({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.extraCategories,
  });

  static const _defaultCategories = [
    'food', 'transport', 'utilities', 'shopping',
    'healthcare', 'entertainment', 'bank', 'other',
  ];

  @override
  State<_ExpCategoryEditor> createState() => _ExpCategoryEditorState();
}

class _ExpCategoryEditorState extends State<_ExpCategoryEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<String> get _allCategories {
    final cats = [..._ExpCategoryEditor._defaultCategories];
    if (widget.extraCategories != null) {
      for (final c in widget.extraCategories!) {
        if (!cats.contains(c.toLowerCase())) cats.add(c.toLowerCase());
      }
    }
    return cats;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        _removeOverlay();
        if (_controller.text.trim().isNotEmpty) {
          widget.onChanged(_controller.text.trim().toLowerCase());
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ExpCategoryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) {
      final filtered = _allCategories
          .where((c) => c.contains(_controller.text.toLowerCase()))
          .toList();
      return Positioned(
        width: 180,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 34),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: filtered.map((cat) {
                  return ListTile(
                    dense: true,
                    title: Text(cat, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      _controller.text = cat;
                      widget.onChanged(cat);
                      _focusNode.unfocus();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          onChanged: (_) {
            _overlayEntry?.markNeedsBuild();
          },
        ),
      ),
    );
  }
}
