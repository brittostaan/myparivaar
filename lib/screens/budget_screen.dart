import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/excel_budget_parser.dart';
import '../services/family_service.dart';
import '../services/ai_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/tag_utils.dart';
import '../widgets/app_header.dart';
import '../widgets/tag_input_section.dart';
import '../widgets/tag_wrap.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

enum _BudgetWebView {
  currentMonth,
  historicalPerformance,
  spendingAnalytics,
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetService _budgetService = BudgetService();
  final ScrollController _infoCardScrollController = ScrollController();
  final List<String> _categories = const [
    'food',
    'transport',
    'utilities',
    'shopping',
    'healthcare',
    'entertainment',
    'other',
  ];

  List<Budget> _budgets = [];
  List<String> _tagSuggestions = [];
  bool _isLoading = false;
  String? _error;
  // Technical detail (HTTP status + raw body) shown under the error for debugging.
  String? _errorDetail;
  // Budget Edge Functions are deployed. Set to false to disable the feature.
  final bool _backendAvailable = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  _BudgetWebView _selectedWebView = _BudgetWebView.currentMonth;
  Map<String, List<Budget>> _historicalBudgets = {};
  // Incremented on every load; stale async responses are discarded.
  int _loadGeneration = 0;

  // Excel upload
  bool _isUploading = false;

  // Panel toggles
  String? _selectedCategoryFilter;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  bool _showCalendarDropdown = false;
  DateTime _calendarDisplayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _showAddBudgetPanel = false;
  bool _showImportPanel = false;
  bool _showHistoricalPanel = false;
  bool _showAnalyticsPanel = false;
  bool _showAIInsightsPanel = false;

  void _closeAllPanels() {
    _showAddBudgetPanel = false;
    _showImportPanel = false;
    _showHistoricalPanel = false;
    _showAnalyticsPanel = false;
    _showAIInsightsPanel = false;
  }

  bool get _anyPanelOpen =>
      _showAddBudgetPanel || _showImportPanel || _showHistoricalPanel ||
      _showAnalyticsPanel || _showAIInsightsPanel;

  // AI Budget Insights
  bool _isLoadingInsights = false;
  String? _aiAnalysis;
  List<String> _aiSuggestions = [];
  String? _aiInsightsError;

  @override
  void initState() {
    super.initState();
    if (_backendAvailable) _loadBudgets();
    _loadTagSuggestions();
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

  Future<void> _fetchAIInsights() async {
    setState(() {
      _isLoadingInsights = true;
      _aiInsightsError = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _aiAnalysis = result['analysis'] as String?;
        _aiSuggestions = (result['suggestions'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        _isLoadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingInsights = false;
        _aiInsightsError = e.toString();
      });
    }
  }

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

    String _monthKeyFor(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  Future<void> _loadBudgets() async {
    if (!_backendAvailable) return;
    final gen = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
      _errorDetail = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final idToken = await authService.getIdToken();
      final months = List.generate(
        6,
        (index) => DateTime(_selectedMonth.year, _selectedMonth.month - index),
      );
      final monthKeys = months.map(_monthKeyFor).toList();
      final historyResults = await Future.wait(
        monthKeys.map(
          (monthKey) => _budgetService.getBudgets(
            supabaseUrl: authService.supabaseUrl,
            idToken: idToken,
            month: monthKey,
          ),
        ),
      );
      final historicalBudgets = <String, List<Budget>>{};
      for (var i = 0; i < monthKeys.length; i++) {
        historicalBudgets[monthKeys[i]] = historyResults[i];
      }
      final budgets = historicalBudgets[_monthKey] ?? const <Budget>[];

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _budgets = budgets;
        _historicalBudgets = historicalBudgets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      final detail = _buildErrorDetail(e);
      setState(() {
        _error = e is BudgetException
            ? e.message
            : 'Unexpected error: ${e.runtimeType}';
        _errorDetail = detail;
        _isLoading = false;
      });
    }
  }

  /// Formats the technical diagnostic string shown under the error message.
  String _buildErrorDetail(Object e) {
    if (e is BudgetException) {
      final lines = <String>[];
      if (e.statusCode != null) lines.add('HTTP ${e.statusCode}');
      if (e.rawBody != null && e.rawBody!.isNotEmpty) {
        lines.add('Response: ${e.rawBody}');
      }
      return lines.isEmpty ? e.message : lines.join('\n');
    }
    return e.toString();
  }

  Future<void> _addOrEditBudget({Budget? existing}) async {
    // Capture authService before any await to avoid BuildContext across async gaps.
    final authService = Provider.of<AuthService>(context, listen: false);
    final result = await showDialog<_BudgetFormResult>(
      context: context,
      builder: (context) {
        final amountController = TextEditingController(
          text: existing == null ? '' : existing.amount.toStringAsFixed(2),
        );
        final tagsController = TextEditingController(
          text: joinTags(existing?.tags),
        );
        String selectedCategory = existing?.category ?? _categories.first;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Budget' : 'Edit Budget'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    items: _categories
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(_titleCase(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedCategory = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monthly Budget',
                      prefixText: 'Rs ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TagInputSection(
                    controller: tagsController,
                    suggestions: _tagSuggestions,
                    helperText:
                        'Tag this budget with family members or intent like mom, school, travel.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      _BudgetFormResult(
                        category: selectedCategory,
                        amount: amount,
                        tags: parseTags(tagsController.text),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    final selectedCategory = result.category;
    final selectedAmount = result.amount;

    try {
      await _budgetService.upsertBudget(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        category: selectedCategory,
        amount: selectedAmount,
        month: _monthKey,
        tags: result.tags,
      );
      if (!mounted) return;
      await _loadBudgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? 'Budget added successfully'
              : 'Budget updated successfully'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save budget: $e')),
      );
    }
  }

  Future<void> _deleteBudget(Budget budget) async {
    // Capture authService before any await to avoid BuildContext across async gaps.
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text(
            'Delete ${_titleCase(budget.category)} budget for $_monthKey?'),
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

    if (confirm != true) return;
    if (!mounted) return;

    try {
      await _budgetService.deleteBudget(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
        budgetId: budget.id,
      );
      if (!mounted) return;
      await _loadBudgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Budget deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete budget: $e')),
      );
    }
  }

  void _moveMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadBudgets();
  }

  Future<void> _uploadExcelBudget() async {
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

      setState(() => _isUploading = true);

      final parser = ExcelBudgetParser();
      final rows = parser.parseExcelFile(Uint8List.fromList(bytes));

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No budget data found in the Excel file')),
        );
        return;
      }

      setState(() => _isUploading = false);
      if (!mounted) return;

      // Show preview dialog with month/year picker
      final dialogResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ExcelPreviewDialog(
          rows: rows,
          initialMonth: _monthKey,
        ),
      );

      if (dialogResult == null || !mounted) return;
      final selectedMonth = dialogResult['month'] as String;
      final editedRows = dialogResult['rows'] as List<_EditableRow>;

      setState(() => _isUploading = true);

      // Import each row individually
      // Use "category - subcategory" as the budget category to keep items separate
      final validRows = editedRows.where((r) => r.isValid).toList();
      int successCount = 0;
      final errors = <String>[];

      for (final row in validRows) {
        try {
          // Build a unique category: if there's a subcategory, combine them
          final budgetCategory = row.subcategory.isNotEmpty
              ? '${row.category} - ${row.subcategory}'.toLowerCase().trim()
              : row.category.toLowerCase().trim();

          await _budgetService.upsertBudget(
            supabaseUrl: authService.supabaseUrl,
            idToken: await authService.getIdToken(),
            category: budgetCategory,
            amount: row.amount,
            month: selectedMonth,
          );
          successCount++;
        } catch (e) {
          final label = row.subcategory.isNotEmpty
              ? '${row.category} - ${row.subcategory}'
              : row.category;
          errors.add('${_titleCase(label)}: $e');
        }
      }

      if (!mounted) return;
      setState(() => _isUploading = false);
      await _loadBudgets();

      if (!mounted) return;
      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $successCount budget items'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        // Show detailed error dialog
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
                      child: Text('$successCount categories imported successfully.',
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
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process Excel file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = BudgetSummary(month: _monthKey, budgets: _budgets);
    if (kIsWeb) {
      return _buildWebLayout(context, summary);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header + Controls ──────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Budget',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildControlsRow(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

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

  Widget _buildControlsRow() {
    final hasDateFilter = _filterStartDate != null || _filterEndDate != null;
    String dateFilterLabel = 'Date Filter';
    if (_filterStartDate != null && _filterEndDate != null) {
      dateFilterLabel = '${_filterStartDate!.day}/${_filterStartDate!.month} – ${_filterEndDate!.day}/${_filterEndDate!.month}';
    } else if (_filterStartDate != null) {
      dateFilterLabel = 'From ${_filterStartDate!.day}/${_filterStartDate!.month}';
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildControlPill(
          icon: Icons.date_range_rounded,
          label: hasDateFilter ? dateFilterLabel : 'Date Filter',
          color: const Color(0xFFE65100),
          active: _showCalendarDropdown || hasDateFilter,
          onTap: () => setState(() {
            _showCalendarDropdown = !_showCalendarDropdown;
            if (_showCalendarDropdown) {
              _calendarDisplayMonth = _filterStartDate ?? DateTime(DateTime.now().year, DateTime.now().month);
            }
          }),
        ),
        _buildControlPill(
          icon: Icons.calendar_month,
          label: 'Current Month',
          color: const Color(0xFF1565C0),
          active: false,
          onTap: () => setState(() {
            _filterStartDate = null;
            _filterEndDate = null;
            _showCalendarDropdown = false;
            _calendarDisplayMonth = DateTime(DateTime.now().year, DateTime.now().month);
            _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
            _loadBudgets();
          }),
        ),
        _buildControlPill(
          icon: _showHistoricalPanel ? Icons.close_rounded : Icons.history,
          label: _showHistoricalPanel ? 'Close' : 'Historical Performance',
          color: const Color(0xFF7C4DFF),
          active: _showHistoricalPanel,
          onTap: () => setState(() {
            final opening = !_showHistoricalPanel;
            _closeAllPanels();
            _showHistoricalPanel = opening;
          }),
        ),
        _buildControlPill(
          icon: _showAnalyticsPanel ? Icons.close_rounded : Icons.insights,
          label: _showAnalyticsPanel ? 'Close' : 'Budget Analytics',
          color: const Color(0xFF00ACC1),
          active: _showAnalyticsPanel,
          onTap: () => setState(() {
            final opening = !_showAnalyticsPanel;
            _closeAllPanels();
            _showAnalyticsPanel = opening;
          }),
        ),
        _buildControlPill(
          icon: _showImportPanel ? Icons.close_rounded : Icons.upload_file,
          label: _showImportPanel ? 'Close' : 'Import',
          color: const Color(0xFF43A047),
          active: _showImportPanel,
          onTap: () => setState(() {
            final opening = !_showImportPanel;
            _closeAllPanels();
            _showImportPanel = opening;
          }),
        ),
        _buildControlPill(
          icon: _showAddBudgetPanel ? Icons.close_rounded : Icons.add_rounded,
          label: _showAddBudgetPanel ? 'Close' : 'Add Budget',
          color: const Color(0xFFFF6D00),
          active: _showAddBudgetPanel,
          onTap: () => setState(() {
            final opening = !_showAddBudgetPanel;
            _closeAllPanels();
            _showAddBudgetPanel = opening;
          }),
        ),
      ],
    );
  }

  Widget _buildBudgetViewTab(String label, IconData icon, bool active, {bool comingSoon = false, VoidCallback? onTap}) {
    return Tooltip(
      message: comingSoon ? 'Coming soon' : '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
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
      ),
    );
  }

  // ── Rewards Row ──

  Widget _buildRewardsRow(bool isDark) {
    final rewards = <_BudgetRewardIcon>[
      _BudgetRewardIcon(Icons.emoji_events_rounded, Colors.amber, 'Budget Champion'),
      _BudgetRewardIcon(Icons.savings_rounded, Colors.green, 'Smart Saver'),
      _BudgetRewardIcon(Icons.auto_graph_rounded, Colors.blue, 'Trend Watcher'),
      _BudgetRewardIcon(Icons.favorite_rounded, Colors.pink, 'Impulse Control'),
      _BudgetRewardIcon(Icons.shield_rounded, Colors.purple, 'No Leaks'),
      _BudgetRewardIcon(Icons.star_rounded, Colors.orange, 'Consistent'),
      _BudgetRewardIcon(Icons.diamond_rounded, Colors.teal, 'Goal Achiever'),
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

  // ── Info Cards Column ──

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
            if (canScrollUp)
              Positioned(
                top: 0, left: 0, right: 0,
                child: GestureDetector(
                  onTap: () {
                    _infoCardScrollController.animateTo(
                      (_infoCardScrollController.offset - constraints.maxHeight * 0.7)
                          .clamp(0, _infoCardScrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [
                          (isDark ? Colors.grey.shade900 : Colors.white),
                          (isDark ? Colors.grey.shade900 : Colors.white).withOpacity(0),
                        ],
                      ),
                    ),
                    child: Center(child: Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: Colors.grey.shade500)),
                  ),
                ),
              ),
            if (canScrollDown)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: GestureDetector(
                  onTap: () {
                    _infoCardScrollController.animateTo(
                      (_infoCardScrollController.offset + constraints.maxHeight * 0.7)
                          .clamp(0, _infoCardScrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [
                          (isDark ? Colors.grey.shade900 : Colors.white),
                          (isDark ? Colors.grey.shade900 : Colors.white).withOpacity(0),
                        ],
                      ),
                    ),
                    child: Center(child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey.shade500)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _fmtCurrency(double amount) {
    final formatted = amount.abs().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '\u20B9$formatted';
  }

  Widget _buildInfoCardsList(bool isDark, Color primary) {
    final now = DateTime.now();
    final totalBudget = _budgets.fold<double>(0, (s, b) => s + b.amount);
    final totalSpent = _budgets.fold<double>(0, (s, b) => s + b.spent);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthPct = now.day / daysInMonth * 100;

    // Category budgets map
    final catBudget = <String, double>{};
    final catSpent = <String, double>{};
    for (final b in _budgets) {
      catBudget[b.category] = (catBudget[b.category] ?? 0) + b.amount;
      catSpent[b.category] = (catSpent[b.category] ?? 0) + b.spent;
    }

    // Historical data for month-over-month comparison
    final prevMonthKey = _monthKeyFor(DateTime(now.year, now.month - 1));
    final prevBudgets = _historicalBudgets[prevMonthKey] ?? [];
    final prevCatBudget = <String, double>{};
    for (final b in prevBudgets) {
      prevCatBudget[b.category] = (prevCatBudget[b.category] ?? 0) + b.amount;
    }

    // Over-budget count
    final overBudgetCount = _budgets.where((b) => b.amount > 0 && b.spent > b.amount).length;
    final usagePct = totalBudget > 0 ? (totalSpent / totalBudget * 100).clamp(0, 999) : 0.0;
    final withinBudget = totalSpent <= totalBudget;

    // Budget Leakage: categories with budget but no spending
    final leakyBudgets = _budgets.where((b) => b.amount > 0 && b.spent == 0).toList();
    final leakyTotal = leakyBudgets.fold<double>(0, (s, b) => s + b.amount);

    // Impulse-risk categories
    final impulseRiskCats = {'convenience food', 'entertainment', 'shopping', 'party'};
    final impulseRiskBudgets = _budgets.where(
        (b) => impulseRiskCats.contains(b.category.toLowerCase()) && b.amount > 0).toList();
    final hasImpulseRisk = impulseRiskBudgets.isNotEmpty;

    // Recurring / subscription budget
    final recurringCats = {'subscriptions', 'streaming', 'insurance', 'emi'};
    final recurringTotal = _budgets
        .where((b) => recurringCats.contains(b.category.toLowerCase()))
        .fold<double>(0, (s, b) => s + b.amount);

    // Silent Budget Erosion: small allocations under ₹500
    final smallBudgets = _budgets.where((b) => b.amount > 0 && b.amount < 500).toList();
    final smallTotal = smallBudgets.fold<double>(0, (s, b) => s + b.amount);

    // Budget Slippage: categories likely to overshoot at current pace
    String? slippageCat;
    double slippageAmount = 0;
    for (final b in _budgets) {
      if (b.amount > 0 && b.spent > 0) {
        final projected = (b.spent / now.day) * daysInMonth;
        if (projected > b.amount) {
          final excess = projected - b.amount;
          if (excess > slippageAmount) {
            slippageAmount = excess;
            slippageCat = b.category;
          }
        }
      }
    }

    // Budget Instability: compare month to month budget changes
    String? unstableCat;
    double maxFluctuation = 0;
    for (final entry in catBudget.entries) {
      final prev = prevCatBudget[entry.key] ?? 0;
      if (prev > 0) {
        final diff = ((entry.value - prev) / prev * 100).abs();
        if (diff > maxFluctuation) {
          maxFluctuation = diff;
          unstableCat = entry.key;
        }
      }
    }

    // Healthy Budget Mix
    final essentialCats = {'groceries', 'food', 'education', 'healthcare', 'utilities', 'housing', 'senior care', 'transport'};
    final essentialBudget = catBudget.entries
        .where((e) => essentialCats.contains(e.key.toLowerCase()))
        .fold<double>(0, (s, e) => s + e.value);
    final mixRatio = totalBudget > 0 ? (essentialBudget / totalBudget * 100) : 0.0;

    // Budget Discipline Score
    final summaries = _historicalSummaries();
    int withinCount = 0;
    int totalMonths = summaries.length;
    for (final s in summaries) {
      if (s.summary.totalSpent <= s.summary.totalBudget || s.summary.totalBudget == 0) {
        withinCount++;
      }
    }
    final disciplineScore = totalMonths > 0 ? (withinCount / totalMonths * 10).clamp(0, 10) : 0.0;

    // Smart Budget Recommendation
    String? smartRecCat;
    double smartRecSaving = 0;
    for (final b in _budgets) {
      if (b.amount > 0 && !essentialCats.contains(b.category.toLowerCase())) {
        final saving = b.amount * 0.1;
        if (saving > smartRecSaving) {
          smartRecSaving = saving;
          smartRecCat = b.category;
        }
      }
    }

    // Safe-to-Spend
    final remaining = totalBudget - totalSpent;
    final daysLeft = daysInMonth - now.day;
    final safeToSpend = daysLeft > 0 ? remaining / daysLeft : 0.0;

    // Fixed vs Flexible
    final fixedCats = {'housing', 'emi', 'insurance', 'subscriptions', 'utilities'};
    final fixedBudget = catBudget.entries
        .where((e) => fixedCats.contains(e.key.toLowerCase()))
        .fold<double>(0, (s, e) => s + e.value);
    final fixedPct = totalBudget > 0 ? (fixedBudget / totalBudget * 100) : 0.0;
    final flexPct = 100 - fixedPct;

    // Emergency Buffer
    final emergencyCats = {'emergency', 'emergency fund', 'buffer'};
    final emergencyBudget = _budgets
        .where((b) => emergencyCats.contains(b.category.toLowerCase()))
        .fold<double>(0, (s, b) => s + b.amount);

    // Goal Impact
    final savingsCats = {'savings', 'investments', 'goals'};
    final savingsBudget = _budgets
        .where((b) => savingsCats.contains(b.category.toLowerCase()))
        .fold<double>(0, (s, b) => s + b.amount);
    final nonSavingsBudget = totalBudget - savingsBudget;

    // ── Build all 14 cards ──
    final allCards = <Widget>[
      _aiCard('💧', 'Spend Leakage',
          leakyBudgets.isNotEmpty
              ? '${_fmtCurrency(leakyTotal)} allocated to ${leakyBudgets.map((b) => b.category).take(2).join(' and ')} but no spending.'
              : 'All budget categories are being utilized. No leaks detected!',
          leakyBudgets.isNotEmpty ? Colors.pink : Colors.green,
          leakyBudgets.isNotEmpty ? 'Reallocate' : 'Healthy'),

      _aiCard('⚡', 'Impulse Risk',
          hasImpulseRisk
              ? '${impulseRiskBudgets.first.category} budget may trigger impulse spending.'
              : 'No impulse-risk budget categories detected!',
          hasImpulseRisk ? Colors.orange : Colors.green,
          hasImpulseRisk ? 'Watch closely' : 'Great control!'),

      _aiCard('🔔', 'Recurring Lock-in',
          recurringTotal > 0
              ? '${_fmtCurrency(recurringTotal)} locked into monthly subscriptions.'
              : 'No recurring budget lock-ins detected.',
          recurringTotal > 0 ? Colors.red : Colors.green,
          recurringTotal > 0 ? 'Review subscriptions' : 'No lock-ins'),

      _aiCard('🔍', 'Silent Erosion',
          smallBudgets.isNotEmpty
              ? '${smallBudgets.length} small allocations add up to ${_fmtCurrency(smallTotal)}.'
              : 'No small budget erosion detected.',
          smallBudgets.isNotEmpty ? Colors.indigo : Colors.green,
          smallBudgets.isNotEmpty ? 'Under ₹500 each' : 'Clean'),

      _aiCard('📉', 'Slippage',
          slippageCat != null
              ? '${slippageCat} likely to exceed by ${_fmtCurrency(slippageAmount)} at current pace.'
              : 'All categories on pace. No slippage detected!',
          slippageCat != null ? Colors.red : Colors.green,
          slippageCat != null ? 'Adjust now' : 'On track'),

      _aiCard('📊', 'Instability',
          unstableCat != null && maxFluctuation > 20
              ? '${unstableCat} budget fluctuates ${maxFluctuation.toStringAsFixed(0)}% month to month.'
              : 'Budget allocations are stable month to month.',
          maxFluctuation > 20 ? Colors.amber : Colors.green,
          maxFluctuation > 20 ? 'Stabilize' : 'Stable'),

      _aiCard('✅', 'Healthy Mix',
          '${mixRatio.toStringAsFixed(0)}% of budget allocated to essentials & long-term needs.',
          mixRatio >= 60 ? Colors.green : Colors.orange,
          mixRatio >= 60 ? 'Great balance!' : 'Could improve'),

      _aiCard('🏆', 'Discipline Score',
          totalMonths > 0
              ? 'Score: ${disciplineScore.toStringAsFixed(1)} / 10\nWithin budget for $withinCount of $totalMonths months.'
              : 'Add budgets to start tracking discipline.',
          disciplineScore >= 7 ? Colors.green : disciplineScore >= 4 ? Colors.amber : Colors.red,
          '${disciplineScore.toStringAsFixed(1)}/10'),

      _aiCard('💡', 'Smart Recommendation',
          smartRecCat != null
              ? 'Reducing ${smartRecCat} by 10% could increase savings by ${_fmtCurrency(smartRecSaving)}.'
              : 'Set non-essential budgets to get recommendations.',
          Colors.blue,
          smartRecCat != null ? 'Quick win' : 'Set budgets'),

      _aiCard('💳', 'Safe-to-Spend',
          remaining > 0
              ? 'You can safely spend ${_fmtCurrency(safeToSpend > 0 ? safeToSpend : 0)} per day and stay within budget.'
              : 'Budget exhausted for this month.',
          remaining > 0 ? Colors.teal : Colors.red,
          remaining > 0 ? 'On track' : 'Exceeded'),

      _aiCard('📐', 'Income Fit',
          totalBudget > 0
              ? 'Total budget: ${_fmtCurrency(totalBudget)}. ${usagePct > 85 ? 'Keeping budgets under 85% of income improves flexibility.' : 'Budget allocation looks sustainable.'}'
              : 'Set budgets to check income fit.',
          usagePct <= 85 ? Colors.green : Colors.orange,
          usagePct <= 85 ? 'Good fit' : 'Tight'),

      _aiCard('⚖️', 'Fixed vs Flexible Split',
          totalBudget > 0
              ? 'Fixed: ${fixedPct.toStringAsFixed(0)}%  |  Flexible: ${flexPct.toStringAsFixed(0)}%\n${fixedPct > 65 ? 'High fixed costs may reduce month-end comfort.' : 'Balanced split between fixed and flexible.'}'
              : 'Add budgets to see the split.',
          fixedPct <= 65 ? Colors.green : Colors.orange,
          fixedPct <= 65 ? 'Balanced' : 'Review fixed'),

      _aiCard('🛡️', 'Emergency Buffer Health',
          emergencyBudget > 0
              ? '${_fmtCurrency(emergencyBudget)} allocated for emergencies this month.'
              : 'No emergency buffer allocated. Consider adding ₹2,000–₹5,000.',
          emergencyBudget > 0 ? Colors.green : Colors.red,
          emergencyBudget > 0 ? 'Protected' : 'Add buffer'),

      _aiCard('🎯', 'Goal Impact',
          savingsBudget > 0
              ? '${_fmtCurrency(savingsBudget)} allocated to savings & goals this month.'
              : 'No savings budget set. Current spend may reduce goal progress.',
          savingsBudget > 0 ? Colors.green : Colors.amber,
          savingsBudget > 0 ? 'Aligned' : 'Set goals'),
    ];

    // Distribute alternately into 2 columns
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
                    Flexible(child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
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

  Widget _buildWebLayout(BuildContext context, BudgetSummary summary) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildWebError()
              : _buildWebContent(summary, isDark, primary),
    );
  }

  Widget _buildWebError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.error, size: 48, color: AppColors.error),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: 10),
              Container(
                width: 560,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _errorDetail!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.grey600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadBudgets,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebContent(BudgetSummary summary, bool isDark, Color primary) {
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
                const Text(
                  'Budget',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 10),
                _buildControlsRow(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // ── Everything below controls: Stack so calendar can float ──
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main content underneath
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Budget Category Chips
                    _buildBudgetCategoryGrid(isDark),
                    // Clear filter chip
                    if (_selectedCategoryFilter != null) ...[                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => setState(() => _selectedCategoryFilter = null),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close, size: 14, color: primary),
                              const SizedBox(width: 4),
                              Text('Clear filter: $_selectedCategoryFilter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // ── Main 3-column layout ──
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Col 1: Budget list (always visible)
                          Expanded(
                            flex: _anyPanelOpen ? 4 : 5,
                            child: _buildWebBudgetList(summary, isDark, primary),
                          ),
                          const SizedBox(width: 12),
                          // When a panel is open: Col2=InfoCards, Col3=Panel
                          if (_anyPanelOpen) ...[
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
                                  if (_showAIInsightsPanel)
                                    Expanded(child: _BudgetAIInsightsPanel(
                                      onClose: () => setState(() => _showAIInsightsPanel = false),
                                    ))
                                  else
                                    Expanded(child: _BudgetAIInsightsPanel(
                                      onClose: () {},
                                    )),
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
                                  Expanded(child: _BudgetAIInsightsPanel(
                                    onClose: () {},
                                  )),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Calendar dropdown overlay (future)
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<({DateTime month, BudgetSummary summary})> _historicalSummaries() {
    final summaries = _historicalBudgets.entries
        .map((entry) {
          final parts = entry.key.split('-');
          final month = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
          return (month: month, summary: BudgetSummary(month: entry.key, budgets: entry.value));
        })
        .toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return summaries;
  }

  Color _usageColor(double ratio, Color primary) {
    if (ratio > 1) return AppColors.error;
    if (ratio >= 0.8) return AppColors.warningDark;
    return primary;
  }

  Widget _buildCurrentMonthSection(BudgetSummary summary, bool isDark, Color primary) {
    return _buildWebBudgetList(summary, isDark, primary);
  }

  List<Budget> get _filteredBudgets {
    if (_selectedCategoryFilter == null) return _budgets;
    final lbl = _selectedCategoryFilter!.toLowerCase();
    return _budgets.where((b) => _budgetMatchesCategory(b, lbl)).toList();
  }

  bool _budgetMatchesCategory(Budget budget, String label) {
    final cat = budget.category.toLowerCase();
    if (cat == label) return true;
    if (cat.contains(label) || label.contains(cat)) return true;
    switch (label) {
      case 'entertainment': return cat == 'entertainment';
      case 'groceries': return cat == 'groceries' || cat == 'grocery';
      case 'mental wellness': return cat.contains('mental') || cat.contains('therapy') || cat.contains('counseling');
      case 'physical wellness': return cat.contains('gym') || cat.contains('fitness') || cat.contains('yoga');
      case 'party': return cat.contains('party') || cat.contains('celebration');
      case 'personal care': return cat.contains('personal') || cat.contains('salon') || cat.contains('grooming');
      case 'pet care': return cat.contains('pet') || cat.contains('vet');
      case 'senior care': return cat.contains('senior') || cat.contains('elderly') || cat.contains('parent');
      case 'education': return cat == 'education';
      case 'vacation': return cat.contains('travel') || cat.contains('vacation') || cat.contains('trip');
      case 'convenience food': return cat.contains('food delivery') || cat.contains('takeaway') || cat.contains('convenience');
      default: return false;
    }
  }

  Widget _buildWebBudgetList(BudgetSummary summary, bool isDark, Color primary) {
    final filtered = _filteredBudgets;
    if (filtered.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _selectedCategoryFilter != null
                  ? 'No $_selectedCategoryFilter budgets this month'
                  : 'No budgets this month',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[500]),
            ),
            const SizedBox(height: 4),
            Text('Add your first budget to get started', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ]),
        ),
      );
    }

    final totalBudget = filtered.fold<double>(0, (s, b) => s + b.amount);
    final totalSpent = filtered.fold<double>(0, (s, b) => s + b.spent);
    final overallRatio = totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.0) : 0.0;
    final overallColor = overallRatio > 0.9 ? AppColors.error : overallRatio > 0.7 ? AppColors.warningDark : AppColors.successDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with summary
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Budget vs Expense',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text('${filtered.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: overallColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            overallRatio > 0.9 ? Icons.warning_amber_rounded : overallRatio > 0.7 ? Icons.trending_up : Icons.check_circle_outline,
                            size: 14, color: overallColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(overallRatio * 100).toStringAsFixed(0)}% used',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: overallColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Overall progress bar
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Spent: ${_fmtCurrency(totalSpent)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    Text('Budget: ${_fmtCurrency(totalBudget)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Budget rows (scrollable)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: filtered.map((budget) => _buildWebBudgetRow(budget, isDark, primary)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebBudgetRow(Budget budget, bool isDark, Color primary) {
    final ratio = budget.amount > 0 ? (budget.spent / budget.amount).clamp(0.0, 1.5) : 0.0;
    final clampedRatio = ratio.clamp(0.0, 1.0);
    final isOver = budget.spent > budget.amount;
    final isNearLimit = ratio >= 0.8 && !isOver;

    final barColor = isOver
        ? AppColors.error
        : isNearLimit
            ? AppColors.warningDark
            : AppColors.successDark;

    final statusIcon = isOver
        ? Icons.error_outline_rounded
        : isNearLimit
            ? Icons.trending_up_rounded
            : Icons.check_circle_outline_rounded;

    final statusText = isOver
        ? 'Over by ${_fmtCurrency(budget.spent - budget.amount)}'
        : isNearLimit
            ? '${(ratio * 100).toStringAsFixed(0)}% used'
            : '${_fmtCurrency(budget.remaining)} left';

    final catIcon = _budgetCategoryIcon(budget.category);
    final catColor = _budgetCategoryColor(budget.category);

    return InkWell(
      onTap: () => _addOrEditBudget(existing: budget),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: isDark ? AppColors.grey800 : const Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            // Category icon bubble
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(catIcon, size: 22, color: catColor),
            ),
            const SizedBox(width: 14),
            // Category + progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _titleCase(budget.category),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 10, color: barColor),
                            const SizedBox(width: 3),
                            Text(statusText, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: barColor)),
                          ],
                        ),
                      ),
                      if (budget.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            budget.tags.take(2).join(', '),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.purple[400]),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: clampedRatio,
                          minHeight: 8,
                          backgroundColor: isDark ? AppColors.grey800 : const Color(0xFFEEF2F6),
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                      // Pace marker (where you should be based on day of month)
                      Positioned(
                        left: _monthPaceRatio() * (MediaQuery.of(context).size.width * 0.25),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: Colors.grey.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Spent vs Budget amounts
                  Row(
                    children: [
                      Text(
                        '${_fmtCurrency(budget.spent)} spent',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: barColor),
                      ),
                      const Spacer(),
                      Text(
                        'of ${_fmtCurrency(budget.amount)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Circular gauge
            SizedBox(
              width: 48, height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 48, height: 48,
                    child: CircularProgressIndicator(
                      value: clampedRatio,
                      strokeWidth: 4,
                      backgroundColor: isDark ? AppColors.grey800 : const Color(0xFFEEF2F6),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                  Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: barColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _monthPaceRatio() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return (now.day / daysInMonth).clamp(0.0, 1.0);
  }

  Color _budgetCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food': return const Color(0xFFFF5722);
      case 'groceries': case 'grocery': return const Color(0xFF4CAF50);
      case 'shopping': return const Color(0xFFE91E63);
      case 'utilities': return const Color(0xFF2196F3);
      case 'transport': return const Color(0xFF9C27B0);
      case 'entertainment': return const Color(0xFFE91E63);
      case 'healthcare': return const Color(0xFF00BCD4);
      case 'education': return const Color(0xFF1565C0);
      case 'party': return const Color(0xFFFF9800);
      case 'vacation': case 'travel': return const Color(0xFF00ACC1);
      default: return const Color(0xFF607D8B);
    }
  }

  Widget _buildBudgetCategoryGrid(bool isDark) {
    const categories = [
      _BudgetCategoryItem(
        label: 'Entertainment',
        icon: Icons.movie_outlined,
        color: Color(0xFFE91E63),
        bgColor: Color(0xFFFCE4EC),
      ),
      _BudgetCategoryItem(
        label: 'Groceries',
        icon: Icons.shopping_cart_outlined,
        color: Color(0xFF4CAF50),
        bgColor: Color(0xFFE8F5E9),
      ),
      _BudgetCategoryItem(
        label: 'Mental Wellness',
        icon: Icons.self_improvement,
        color: Color(0xFF7C4DFF),
        bgColor: Color(0xFFEDE7F6),
      ),
      _BudgetCategoryItem(
        label: 'Physical Wellness',
        icon: Icons.fitness_center,
        color: Color(0xFFFF5722),
        bgColor: Color(0xFFFBE9E7),
      ),
      _BudgetCategoryItem(
        label: 'Party',
        icon: Icons.celebration_outlined,
        color: Color(0xFFFF9800),
        bgColor: Color(0xFFFFF3E0),
      ),
      _BudgetCategoryItem(
        label: 'Personal Care',
        icon: Icons.spa_outlined,
        color: Color(0xFFEC407A),
        bgColor: Color(0xFFFCE4EC),
      ),
      _BudgetCategoryItem(
        label: 'Pet Care',
        icon: Icons.pets_outlined,
        color: Color(0xFF8D6E63),
        bgColor: Color(0xFFEFEBE9),
      ),
      _BudgetCategoryItem(
        label: 'Senior Care',
        icon: Icons.elderly_outlined,
        color: Color(0xFF00897B),
        bgColor: Color(0xFFE0F2F1),
      ),
      _BudgetCategoryItem(
        label: 'Education',
        icon: Icons.school_outlined,
        color: Color(0xFF1565C0),
        bgColor: Color(0xFFE3F2FD),
      ),
      _BudgetCategoryItem(
        label: 'Vacation',
        icon: Icons.flight_outlined,
        color: Color(0xFF00ACC1),
        bgColor: Color(0xFFE0F7FA),
      ),
      _BudgetCategoryItem(
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
          final matchingBudget = _findBudgetForCategory(cat.label);
          return _buildBudgetCategoryChip(cat, matchingBudget);
        },
      ),
    );
  }

  Budget? _findBudgetForCategory(String label) {
    final lbl = label.toLowerCase();
    for (final budget in _budgets) {
      final cat = budget.category.toLowerCase();
      if (cat == lbl) return budget;
      if (cat.contains(lbl)) return budget;
      // Match specific keywords
      switch (lbl) {
        case 'entertainment':
          if (cat == 'entertainment') return budget;
        case 'groceries':
          if (cat == 'groceries' || cat == 'grocery') return budget;
        case 'mental wellness':
          if (cat.contains('mental') || cat.contains('therapy') || cat.contains('counseling')) return budget;
        case 'physical wellness':
          if (cat.contains('gym') || cat.contains('fitness') || cat.contains('yoga')) return budget;
        case 'party':
          if (cat.contains('party') || cat.contains('celebration')) return budget;
        case 'personal care':
          if (cat.contains('personal') || cat.contains('salon') || cat.contains('grooming')) return budget;
        case 'pet care':
          if (cat.contains('pet') || cat.contains('vet')) return budget;
        case 'senior care':
          if (cat.contains('senior') || cat.contains('elderly') || cat.contains('parent')) return budget;
        case 'education':
          if (cat == 'education') return budget;
        case 'vacation':
          if (cat.contains('travel') || cat.contains('vacation') || cat.contains('trip')) return budget;
        case 'convenience food':
          if (cat.contains('food delivery') || cat.contains('takeaway') || cat.contains('convenience')) return budget;
      }
    }
    return null;
  }

  Widget _buildBudgetCategoryChip(_BudgetCategoryItem cat, Budget? budget) {
    final hasBudget = budget != null;
    final spent = hasBudget ? budget.spent : 0.0;
    final total = hasBudget ? budget.amount : 0.0;
    final ratio = total > 0 ? (spent / total).clamp(0.0, 1.0) : 0.0;
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
              if (hasBudget) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: ratio > 0.9 ? AppColors.error : cat.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
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

  Widget _buildBudgetComplianceCard({
    required bool isDark,
    required Color primary,
  }) {
    final summaries = _historicalSummaries();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Budget Compliance (6 Months)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (summaries.isEmpty)
            Text(
              'No historical budget data available yet.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summaries.map((item) {
                final ratio = item.summary.totalBudget > 0
                    ? (item.summary.totalSpent / item.summary.totalBudget)
                        .clamp(0.0, 1.0)
                    : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniBar(
                          ratio == 0 ? 0.08 : ratio,
                          _usageColor(
                            item.summary.totalBudget > 0
                                ? item.summary.totalSpent /
                                    item.summary.totalBudget
                                : 0.0,
                            primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _monthLabel(item.month).split(' ').first,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(
              '${summaries.where((item) => item.summary.totalBudget > 0 && item.summary.totalSpent <= item.summary.totalBudget).length} of ${summaries.length} months stayed within budget.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmartBudgetInsightCard({
    required bool isDark,
    required Color primary,
  }) {
    final sortedBudgets = [..._budgets]
      ..sort((a, b) => b.usagePercent.compareTo(a.usagePercent));
    final focusBudget = sortedBudgets.isNotEmpty ? sortedBudgets.first : null;

    String title;
    String message;
    Color accent;
    IconData icon;

    if (focusBudget == null) {
      title = 'Smart Budget Insight';
      message = 'Add budgets to start receiving usage-based insights.';
      accent = primary;
      icon = Icons.auto_awesome;
    } else if (focusBudget.isOverBudget) {
      title = 'Overspend Alert';
      message = '${_titleCase(focusBudget.category)} is over budget by ₹${focusBudget.remaining.abs().toStringAsFixed(0)} this month. Review and adjust the category limit.';
      accent = AppColors.error;
      icon = Icons.warning_amber_rounded;
    } else if (focusBudget.usagePercent >= 85) {
      title = 'Tightest Budget';
      message = '${_titleCase(focusBudget.category)} has already used ${focusBudget.usagePercent.toStringAsFixed(0)}% of its budget, leaving ₹${focusBudget.remaining.toStringAsFixed(0)}.';
      accent = AppColors.warningDark;
      icon = Icons.trending_up_rounded;
    } else {
      final bestBudget = [..._budgets]
        ..sort((a, b) => a.usagePercent.compareTo(b.usagePercent));
      final winner = bestBudget.first;
      title = 'Best Controlled Category';
      message = '${_titleCase(winner.category)} is tracking well at ${winner.usagePercent.toStringAsFixed(0)}% used, leaving ₹${winner.remaining.toStringAsFixed(0)} for the month.';
      accent = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalPerformanceSection(bool isDark, Color primary) {
    final summaries = _historicalSummaries();
    final compliantMonths = summaries
        .where((item) => item.summary.totalBudget > 0 && item.summary.totalSpent <= item.summary.totalBudget)
        .length;
    final averageUsage = summaries.isEmpty
        ? 0.0
        : summaries
                .map((item) => item.summary.totalBudget > 0
                    ? item.summary.totalSpent / item.summary.totalBudget
                    : 0.0)
                .reduce((a, b) => a + b) /
            summaries.length;
    final latest = summaries.isNotEmpty ? summaries.last.summary : const BudgetSummary(month: '', budgets: []);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _budgetSummaryCard(
                title: 'Months On Track',
                value: '$compliantMonths/${summaries.length}',
                subtitle: 'Stayed within budget',
                valueColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Average Utilization',
                value: '${(averageUsage * 100).toStringAsFixed(0)}%',
                subtitle: 'Across the last 6 months',
                valueColor: _usageColor(averageUsage, primary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Latest Month Spend',
                value: '₹${latest.totalSpent.toStringAsFixed(0)}',
                subtitle: latest.month.isEmpty ? 'No history yet' : _monthLabel(_selectedMonth),
                valueColor: primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _buildBudgetComplianceCard(isDark: isDark, primary: primary),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Month-by-Month Breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              ...summaries.reversed.map((item) {
                final ratio = item.summary.totalBudget > 0
                    ? item.summary.totalSpent / item.summary.totalBudget
                    : 0.0;
                final color = _usageColor(ratio, primary);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          _monthLabel(item.month),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: ratio.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '₹${item.summary.totalSpent.toStringAsFixed(0)} / ₹${item.summary.totalBudget.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpendingAnalyticsSection(bool isDark, Color primary) {
    final categoryStats = <String, _BudgetCategoryAnalytics>{};
    for (final budgets in _historicalBudgets.values) {
      for (final budget in budgets) {
        final existing = categoryStats[budget.category] ??
            _BudgetCategoryAnalytics(category: budget.category);
        existing.totalBudget += budget.amount;
        existing.totalSpent += budget.spent;
        existing.monthsTracked += 1;
        if (budget.isOverBudget) existing.overBudgetMonths += 1;
        categoryStats[budget.category] = existing;
      }
    }

    final categories = categoryStats.values.toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    final topCategory = categories.isNotEmpty ? categories.first : null;
    final averageMonthlySpend = categories.isEmpty
        ? 0.0
        : categories.fold<double>(0.0, (sum, item) => sum + item.totalSpent) /
            _historicalBudgets.length.clamp(1, 1000);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _budgetSummaryCard(
                title: 'Top Spend Category',
                value: topCategory == null ? '—' : _titleCase(topCategory.category),
                subtitle: topCategory == null
                    ? 'No analytics yet'
                    : '₹${topCategory.totalSpent.toStringAsFixed(0)} over ${topCategory.monthsTracked} months',
                valueColor: primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Average Monthly Spend',
                value: '₹${averageMonthlySpend.toStringAsFixed(0)}',
                subtitle: 'Across tracked categories',
                valueColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _budgetSummaryCard(
                title: 'Most Volatile Category',
                value: topCategory == null ? '—' : '${topCategory.overBudgetMonths}',
                subtitle: topCategory == null
                    ? 'No over-budget months'
                    : '${_titleCase(topCategory.category)} months over budget',
                valueColor: AppColors.warningDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppColors.grey800 : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Category Analytics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (categories.isEmpty)
                const Text('No analytics available yet for the selected history window.')
              else
                ...categories.map((item) {
                  final ratio = item.totalBudget > 0 ? item.totalSpent / item.totalBudget : 0.0;
                  final color = _usageColor(ratio, primary);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            _titleCase(item.category),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: ratio.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Spent ₹${item.totalSpent.toStringAsFixed(0)} of ₹${item.totalBudget.toStringAsFixed(0)} across ${item.monthsTracked} months',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(ratio * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _webTabChip({
    required String label,
    required IconData icon,
    required bool active,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFF0D7FF2) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? const Color(0xFF0D7FF2) : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF0D7FF2) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIInsightsCard(bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 22),
              const SizedBox(width: 8),
              const Text(
                'AI Budget Insights',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_isLoadingInsights)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.icon(
                  onPressed: _fetchAIInsights,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_aiAnalysis != null ? 'Refresh' : 'Analyze'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
          if (_aiInsightsError != null) ...[
            const SizedBox(height: 12),
            Text(
              _aiInsightsError!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          if (_aiAnalysis != null) ...[
            const SizedBox(height: 16),
            Text(_aiAnalysis!, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          if (_aiSuggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Suggestions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._aiSuggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
          if (_aiAnalysis == null && !_isLoadingInsights && _aiInsightsError == null) ...[
            const SizedBox(height: 8),
            Text(
              'Tap Analyze to get AI-powered insights on your budget performance.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _budgetSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    Color? valueColor,
    double? progress,
    Color? color,
    bool comingSoon = false,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
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
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
              if (comingSoon)
                const Icon(Icons.close_rounded, size: 12, color: Colors.red),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              if (subtitle.startsWith('/')) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ),
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: const Color(0xFFF1F5F9),
                color: color ?? primary,
              ),
            ),
          ],
          if (!subtitle.startsWith('/')) ...[
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  IconData _budgetCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'utilities':
        return Icons.bolt;
      case 'transport':
        return Icons.directions_car;
      case 'entertainment':
        return Icons.movie;
      case 'healthcare':
        return Icons.local_hospital;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Widget _miniBar(double heightFactor, Color color) {
    return Expanded(
      child: SizedBox(
        height: 96,
        child: Align(
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
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                _monthLabel(_selectedMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: (_selectedMonth.year == DateTime.now().year &&
                    _selectedMonth.month == DateTime.now().month)
                ? null
                : () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_backendAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.pieChart, size: 64, color: AppColors.grey400),
              SizedBox(height: 16),
              Text(
                'Budget Feature Coming Soon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Budget management is under development and will be available in an upcoming release.',
                style: TextStyle(color: AppColors.grey400),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.error, size: 48, color: AppColors.error),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_errorDetail != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _errorDetail!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.grey600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadBudgets,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_budgets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.pieChart, size: 64, color: AppColors.grey400),
            SizedBox(height: 12),
            Text(
              'No budgets set for this month',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Tap + to create your first budget'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBudgets,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        itemCount: _budgets.length,
        itemBuilder: (context, index) {
          final budget = _budgets[index];
          return _BudgetCard(
            budget: budget,
            onEdit: () => _addOrEditBudget(existing: budget),
            onDelete: () => _deleteBudget(budget),
          );
        },
      ),
    );
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  String _monthLabel(DateTime date) {
    const months = [
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
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _BudgetFormResult {
  final String category;
  final double amount;
  final List<String> tags;

  const _BudgetFormResult({
    required this.category,
    required this.amount,
    required this.tags,
  });
}

class _BudgetCategoryAnalytics {
  final String category;
  double totalBudget;
  double totalSpent;
  int monthsTracked;
  int overBudgetMonths;

  _BudgetCategoryAnalytics({
    required this.category,
    this.totalBudget = 0,
    this.totalSpent = 0,
    this.monthsTracked = 0,
    this.overBudgetMonths = 0,
  });
}

class _BudgetCategoryItem {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _BudgetCategoryItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class _SummaryCard extends StatelessWidget {
  final BudgetSummary summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final remaining = summary.totalRemaining;
    final color = remaining < 0 ? AppColors.errorDark : AppColors.successDark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                label: 'Budget',
                value: 'Rs ${summary.totalBudget.toStringAsFixed(0)}',
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                label: 'Spent',
                value: 'Rs ${summary.totalSpent.toStringAsFixed(0)}',
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                label: 'Remaining',
                value: 'Rs ${remaining.toStringAsFixed(0)}',
                valueColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.grey600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BudgetCard({
    required this.budget,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final percent = budget.usagePercent.clamp(0, 100).toDouble();
    final isOver = budget.isOverBudget;
    final progressColor = isOver
        ? AppColors.errorDark
        : (percent >= 80 ? AppColors.warningDark : AppColors.successDark);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.category.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.edit, size: 18),
                  tooltip: 'Edit budget',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(AppIcons.delete,
                      size: 18, color: AppColors.error),
                  tooltip: 'Delete budget',
                ),
              ],
            ),
            Text('Budget: Rs ${budget.amount.toStringAsFixed(2)}'),
            Text('Spent: Rs ${budget.spent.toStringAsFixed(2)}'),
            if (budget.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              TagWrap(tags: budget.tags),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 10,
                backgroundColor: AppColors.grey200,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isOver
                  ? 'Over budget by Rs ${budget.remaining.abs().toStringAsFixed(2)}'
                  : 'Remaining Rs ${budget.remaining.toStringAsFixed(2)}',
              style: TextStyle(
                color: progressColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to aggregate amounts per category during Excel import
class _AggregatedBudget {
  double amount = 0;
  final List<String> tags = [];
}

/// Mutable row for the preview dialog — lets users edit the category
class _EditableRow {
  String category;
  final String subcategory;
  final double amount;
  final bool isValid;
  final String? validationError;

  _EditableRow({
    required this.category,
    this.subcategory = '',
    required this.amount,
    this.isValid = true,
    this.validationError,
  });

  factory _EditableRow.fromBudgetRow(BudgetRow row, String mappedCategory) {
    return _EditableRow(
      category: mappedCategory,
      subcategory: row.subcategory,
      amount: row.amount,
      isValid: row.isValid,
      validationError: row.validationError,
    );
  }
}

/// Dialog that shows a preview of parsed Excel budget rows before importing.
class _ExcelPreviewDialog extends StatefulWidget {
  final List<BudgetRow> rows;
  final String initialMonth;

  const _ExcelPreviewDialog({
    required this.rows,
    required this.initialMonth,
  });

  @override
  State<_ExcelPreviewDialog> createState() => _ExcelPreviewDialogState();
}

class _ExcelPreviewDialogState extends State<_ExcelPreviewDialog> {
  late int _selectedYear;
  late int _selectedMonth;
  late List<_EditableRow> _editableRows;

  static const _validCategories = [
    'food',
    'transport',
    'utilities',
    'shopping',
    'healthcare',
    'entertainment',
    'other',
  ];

  /// Map raw Excel category to the closest valid backend category
  static String _mapToValidCategory(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return 'other';
    if (_validCategories.contains(lower)) return lower;

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
    final parts = widget.initialMonth.split('-');
    _selectedYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    _selectedMonth = int.tryParse(parts[1]) ?? DateTime.now().month;

    // Convert BudgetRows to editable rows with mapped categories
    _editableRows = widget.rows.map((row) {
      return _EditableRow.fromBudgetRow(row, _mapToValidCategory(row.category));
    }).toList();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final validRows = _editableRows.where((r) => r.isValid).toList();
    final invalidRows = _editableRows.where((r) => !r.isValid).toList();
    final totalAmount =
        validRows.fold<double>(0, (sum, r) => sum + r.amount);
    final hasSubcategories =
        _editableRows.any((r) => r.subcategory.isNotEmpty);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Excel Import Preview')),
        ],
      ),
      content: SizedBox(
        width: 750,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month/Year picker row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Import to:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _selectedMonth,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: List.generate(12, (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(_monthNames[i], style: const TextStyle(fontSize: 13)),
                    )),
                    onChanged: (v) => setState(() => _selectedMonth = v!),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _selectedYear,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: List.generate(5, (i) {
                      final year = DateTime.now().year - 2 + i;
                      return DropdownMenuItem(
                        value: year,
                        child: Text('$year', style: const TextStyle(fontSize: 13)),
                      );
                    }),
                    onChanged: (v) => setState(() => _selectedYear = v!),
                  ),
                  const Spacer(),
                  Text(
                    _monthKey,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
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
              'Items are grouped by category during import. You can change categories below.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            // Table
            Expanded(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: {
                    0: const FixedColumnWidth(32),
                    1: const FlexColumnWidth(1.6),
                    if (hasSubcategories) 2: const FlexColumnWidth(1.8),
                    (hasSubcategories ? 3 : 2): const FlexColumnWidth(1),
                    (hasSubcategories ? 4 : 3): const FixedColumnWidth(40),
                  },
                  border: TableBorder.all(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                      ),
                      children: [
                        const _TableHeader('#'),
                        const _TableHeader('Category'),
                        if (hasSubcategories) const _TableHeader('Item'),
                        const _TableHeader('Amount'),
                        const _TableHeader(''),
                      ],
                    ),
                    ..._editableRows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: row.isValid
                              ? null
                              : AppColors.error.withValues(alpha: 0.06),
                        ),
                        children: [
                          _TableCell(
                            Text('${idx + 1}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                          _TableCell(
                            _CategoryEditor(
                              value: row.category,
                              enabled: row.isValid,
                              onChanged: (v) {
                                setState(() => row.category = v);
                              },
                            ),
                          ),
                          if (hasSubcategories)
                            _TableCell(
                              Text(row.subcategory,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          _TableCell(
                            Text(
                              row.isValid
                                  ? '₹${row.amount.toStringAsFixed(0)}'
                                  : row.validationError ?? 'Invalid',
                              style: TextStyle(
                                fontSize: 12,
                                color: row.isValid ? null : AppColors.error,
                              ),
                            ),
                          ),
                          _TableCell(
                            Icon(
                              row.isValid
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: row.isValid
                                  ? AppColors.success
                                  : AppColors.error,
                              size: 15,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            if (invalidRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Invalid rows will be skipped during import.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
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
                    'month': _monthKey,
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final Widget child;
  const _TableCell(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    );
  }
}

/// Editable category field with autocomplete suggestions + custom input.
class _CategoryEditor extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CategoryEditor({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _suggestions = [
    'food', 'transport', 'utilities', 'shopping',
    'healthcare', 'entertainment', 'other',
  ];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _titleCase(value)),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase().trim();
        if (query.isEmpty) return _suggestions;
        return _suggestions
            .where((s) => s.contains(query))
            .toList();
      },
      displayStringForOption: (s) => _titleCase(s),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return SizedBox(
          height: 30,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
            ),
            onSubmitted: (_) {
              final text = controller.text.toLowerCase().trim();
              if (text.isNotEmpty) onChanged(text);
            },
          ),
        );
      },
      onSelected: (selection) {
        onChanged(selection.toLowerCase().trim());
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(_titleCase(option), style: const TextStyle(fontSize: 13)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Budget AI Insights Panel
// ══════════════════════════════════════════════════════════════════════════════

class _BudgetAIInsightsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _BudgetAIInsightsPanel({required this.onClose});

  @override
  State<_BudgetAIInsightsPanel> createState() => _BudgetAIInsightsPanelState();
}

class _BudgetAIInsightsPanelState extends State<_BudgetAIInsightsPanel> {
  bool _loading = false;
  String? _analysis;
  String? _error;

  final _chatController = TextEditingController();
  final List<_BudgetChatMessage> _chatMessages = [];
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
      _chatMessages.add(_BudgetChatMessage(text: msg, isUser: true));
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
          _chatMessages.add(_BudgetChatMessage(text: result['response'] as String? ?? 'No response', isUser: false));
          _chatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(_BudgetChatMessage(text: 'Error: $e', isUser: false));
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
              const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF9C27B0)),
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

class _BudgetChatMessage {
  final String text;
  final bool isUser;
  const _BudgetChatMessage({required this.text, required this.isUser});
}

class _BudgetRewardIcon {
  final IconData icon;
  final Color color;
  final String label;
  const _BudgetRewardIcon(this.icon, this.color, this.label);
}
