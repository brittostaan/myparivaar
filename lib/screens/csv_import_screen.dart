import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/import_result.dart';
import '../services/import_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_icons.dart';
// ── Stage machine ─────────────────────────────────────────────────────────────
enum _Stage { setup, previewing, previewReady, committing, done }

// ── Column specs ──────────────────────────────────────────────────────────────
const _expenseColumns = <String>['date', 'amount', 'category', 'description', 'notes'];
const _budgetColumns  = <String>['category', 'amount', 'month'];

const _expenseHint =
    'date,amount,category,description,notes\n2026-03-01,450.00,Groceries,Weekly vegetables,';
const _budgetHint =
    'category,amount,month\nGroceries,5000,2026-03';

/// Full-screen CSV import flow:
///   1. Select type + pick file
///   2. Server-side preview with row validation
///   3. Confirm import
///   4. Success summary
class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({super.key, required this.importService});

  final ImportService importService;

  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  _Stage _stage = _Stage.setup;

  String  _importType  = 'expenses'; // 'expenses' | 'budgets'
  String? _csvText;
  String? _fileName;

  ImportPreviewResult? _preview;
  ImportCommitResult?  _commitResult;
  String?              _errorMessage;

  // ── Getters ──────────────────────────────────────────────────────────────────
  bool get _fileSelected => _csvText != null;
  bool get _canValidate  => _fileSelected && _stage == _Stage.setup;

  // ── File picker ───────────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);

    final result = await FilePicker.platform.pickFiles(
      type:              FileType.custom,
      allowedExtensions: ['csv'],
      withData:          true,   // populates bytes on all platforms including web
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    if (file.bytes == null) {
      setState(() => _errorMessage = 'Could not read file. Please try again.');
      return;
    }

    // Guard against very large files before decoding
    const maxBytes = 5 * 1024 * 1024; // 5 MB
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
      _csvText  = text;
      _fileName = file.name;
    });
  }

  // ── Preview (validate) ────────────────────────────────────────────────────────
  Future<void> _runPreview() async {
    setState(() {
      _stage        = _Stage.previewing;
      _errorMessage = null;
      _preview      = null;
    });

    try {
      final result = await widget.importService.preview(
        type:    _importType,
        csvText: _csvText!,
      );
      setState(() {
        _preview = result;
        _stage   = _Stage.previewReady;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _stage        = _Stage.setup;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during validation.';
        _stage        = _Stage.setup;
      });
    }
  }

  // ── Commit ────────────────────────────────────────────────────────────────────
  Future<void> _runCommit() async {
    setState(() {
      _stage        = _Stage.committing;
      _errorMessage = null;
    });

    try {
      final result = await widget.importService.commit(
        type:    _importType,
        csvText: _csvText!,
      );
      setState(() {
        _commitResult = result;
        _stage        = _Stage.done;
      });
    } on ImportException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _stage        = _Stage.previewReady;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unexpected error during import.';
        _stage        = _Stage.previewReady;
      });
    }
  }

  void _reset() {
    setState(() {
      _stage        = _Stage.setup;
      _csvText      = null;
      _fileName     = null;
      _preview      = null;
      _commitResult = null;
      _errorMessage = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Import CSV',
              avatarIcon: AppIcons.upload,
            ),
            Expanded(
              child: switch (_stage) {
                _Stage.setup        => _buildSetup(context),
                _Stage.previewing   => _buildLoading('Validating rows…'),
                _Stage.previewReady => _buildPreview(context),
                _Stage.committing   => _buildLoading('Importing data…'),
                _Stage.done         => _buildDone(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Setup stage ───────────────────────────────────────────────────────────────
  Widget _buildSetup(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Type selector
        Text('Import type', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            _TypeChip(
              label:      'Expenses',
              selected:   _importType == 'expenses',
              onSelected: (_) => setState(() {
                _importType = 'expenses';
                _csvText    = null;
                _fileName   = null;
              }),
            ),
            const SizedBox(width: 8),
            _TypeChip(
              label:      'Budgets',
              selected:   _importType == 'budgets',
              onSelected: (_) => setState(() {
                _importType = 'budgets';
                _csvText    = null;
                _fileName   = null;
              }),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // CSV format hint
        _FormatHintCard(
          columns: _importType == 'expenses' ? _expenseColumns : _budgetColumns,
          example: _importType == 'expenses' ? _expenseHint    : _budgetHint,
        ),

        const SizedBox(height: 20),

        // File picker
        Text('Select file', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon:  const Icon(AppIcons.upload),
          label: Text(_fileName ?? 'Choose CSV file'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            alignment: Alignment.centerLeft,
          ),
        ),

        if (_fileName != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(AppIcons.checkCircle, color: cs.primary, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _fileName!,
                  style: TextStyle(color: cs.primary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _csvText  = null;
                  _fileName = null;
                }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],

        // Error banner
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],

        const SizedBox(height: 32),

        // Validate button
        FilledButton.icon(
          onPressed: _canValidate ? _runPreview : null,
          icon:  const Icon(AppIcons.factCheck),
          label: const Text('Validate'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  // ── Loading stage ─────────────────────────────────────────────────────────────
  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  // ── Preview stage ─────────────────────────────────────────────────────────────
  Widget _buildPreview(BuildContext context) {
    final preview = _preview!;
    final cs      = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary banner
              _PreviewSummaryBanner(preview: preview),
              const SizedBox(height: 16),

              // Error list (if any)
              if (preview.hasErrors) ...[
                Text(
                  'Fix the following errors and re-upload:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 8),
                ...preview.errors.map((e) => _ErrorRow(error: e)),
                const SizedBox(height: 16),
              ],

              // Valid rows list
              if (preview.validCount > 0) ...[
                Row(
                  children: [
                    Text(
                      '${preview.validCount} valid row${preview.validCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (preview.validCount > 50) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(showing first 50)',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ...preview.validRows
                    .take(50)
                    .map((row) => _PreviewRowCard(
                          row:        row,
                          importType: _importType,
                        )),
              ],

              // Server error banner (after commit attempt fails)
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _errorMessage!),
              ],
            ],
          ),
        ),

        // Bottom action bar — only shown when CSV is clean
        if (preview.isClean)
          _ImportActionBar(
            rowCount:  preview.validCount,
            importType: _importType,
            onImport:  _runCommit,
          ),

        // Re-upload prompt when there are errors
        if (preview.hasErrors)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon:  const Icon(AppIcons.upload),
              label: const Text('Upload corrected file'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
      ],
    );
  }

  // ── Done stage ────────────────────────────────────────────────────────────────
  Widget _buildDone(BuildContext context) {
    final result = _commitResult!;
    final cs     = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.checkCircle, color: cs.primary, size: 72),
            const SizedBox(height: 16),
            Text(
              'Import complete',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${result.imported} ${result.type} imported successfully.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Batch ID: ${result.batchId}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              child: const Text('Done'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _reset,
              child: const Text('Import another file'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String   label;
  final bool     selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label:      Text(label),
      selected:   selected,
      onSelected: onSelected,
    );
  }
}

class _FormatHintCard extends StatefulWidget {
  const _FormatHintCard({required this.columns, required this.example});
  final List<String> columns;
  final String       example;

  @override
  State<_FormatHintCard> createState() => _FormatHintCardState();
}

class _FormatHintCardState extends State<_FormatHintCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.info, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Required columns: ${widget.columns.join(', ')}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(
                    _expanded ? AppIcons.expandLess : AppIcons.expandMore,
                    size: 18,
                    color: cs.outline,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    widget.example,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize:   11,
                      color:      cs.onSurfaceVariant,
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
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color:        cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.error, color: cs.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSummaryBanner extends StatelessWidget {
  const _PreviewSummaryBanner({required this.preview});
  final ImportPreviewResult preview;

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isClean = preview.isClean;

    return Container(
      decoration: BoxDecoration(
        color:        isClean ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            isClean ? AppIcons.checkCircle : AppIcons.warningAmber,
            color: isClean ? cs.onPrimaryContainer : cs.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isClean
                ? Text(
                    '${preview.validCount} row${preview.validCount == 1 ? '' : 's'} ready to import.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:      cs.onPrimaryContainer,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${preview.errorCount} error${preview.errorCount == 1 ? '' : 's'} found',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:      cs.onErrorContainer,
                        ),
                      ),
                      if (preview.validCount > 0)
                        Text(
                          '${preview.validCount} valid row${preview.validCount == 1 ? '' : 's'} (will not import until all errors are fixed)',
                          style: TextStyle(
                            fontSize: 12,
                            color:    cs.onErrorContainer,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.error});
  final RowError error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin:  const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color:        cs.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Row ${error.row}',
              style: TextStyle(
                fontSize:    11,
                fontWeight:  FontWeight.w600,
                color:       cs.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${error.field}: ${error.message}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRowCard extends StatelessWidget {
  const _PreviewRowCard({required this.row, required this.importType});

  final Map<String, dynamic> row;
  final String               importType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build a compact, single-line summary per row type
    final (String title, String subtitle) = importType == 'expenses'
        ? (
            '${row['date']}  ·  ${row['category']}  ·  ₹${row['amount']}',
            row['description']?.toString() ?? '',
          )
        : (
            '${row['month']}  ·  ${row['category']}',
            '₹${row['amount']}',
          );

    return Card(
      margin:   const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color:    cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          importType == 'expenses' ? AppIcons.receiptOutlined : AppIcons.wallet,
          color: cs.primary,
          size:  20,
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
      ),
    );
  }
}

class _ImportActionBar extends StatelessWidget {
  const _ImportActionBar({
    required this.rowCount,
    required this.importType,
    required this.onImport,
  });

  final int      rowCount;
  final String   importType;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          onPressed: onImport,
          icon:  const Icon(AppIcons.cloudUpload),
          label: Text('Import $rowCount ${importType == 'expenses' ? 'expense' : 'budget'} row${rowCount == 1 ? '' : 's'}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ),
    );
  }
}
