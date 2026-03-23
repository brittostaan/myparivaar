import 'package:flutter/material.dart';

import '../models/admin_models.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';

class AdminEmailIntegrationPanel extends StatefulWidget {
  const AdminEmailIntegrationPanel({
    super.key,
    required this.adminService,
    required this.accounts,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

  final AdminService adminService;
  final List<AdminEmailIntegrationAccount> accounts;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  State<AdminEmailIntegrationPanel> createState() => _AdminEmailIntegrationPanelState();
}

class _AdminEmailIntegrationPanelState extends State<AdminEmailIntegrationPanel> {
  AdminEmailIntegrationAccount? _selected;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _scopeValueController = TextEditingController(text: '7');

  List<String> _senderFilters = [];
  List<String> _keywordFilters = [];
  String _scopeUnit = 'days';
  int _scopeValue = 7;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initSelectionFromAccounts(widget.accounts);
  }

  @override
  void didUpdateWidget(covariant AdminEmailIntegrationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts != widget.accounts) {
      _initSelectionFromAccounts(widget.accounts);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _senderController.dispose();
    _keywordController.dispose();
    _scopeValueController.dispose();
    super.dispose();
  }

  void _initSelectionFromAccounts(List<AdminEmailIntegrationAccount> rows) {
    if (rows.isEmpty) {
      setState(() {
        _selected = null;
        _senderFilters = [];
        _keywordFilters = [];
      });
      return;
    }

    final previousId = _selected?.id;
    final selected = previousId != null
        ? rows.firstWhere(
            (row) => row.id == previousId,
            orElse: () => rows.first,
          )
        : rows.first;

    setState(() {
      _selected = selected;
      _senderFilters = List<String>.from(selected.screeningSenderFilters);
      _keywordFilters = List<String>.from(selected.screeningKeywordFilters);
      _scopeUnit = selected.screeningScopeUnit == 'months' ? 'months' : 'days';
      _scopeValue = selected.screeningScopeValue;
      _scopeValueController.text = _scopeValue.toString();
      _isActive = selected.isActive;
    });
  }

  Future<void> _runSearch() async {
    try {
      await widget.adminService.fetchAdminEmailIntegrationAccounts(
        query: _searchController.text.trim(),
        includeInactive: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  void _addSenderFilter() {
    final value = _senderController.text.trim().toLowerCase();
    if (value.isEmpty) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid sender email address')),
      );
      return;
    }

    if (_senderFilters.contains(value)) {
      _senderController.clear();
      return;
    }

    setState(() {
      _senderFilters = [..._senderFilters, value];
      _senderController.clear();
    });
  }

  void _addKeywordFilter() {
    final value = _keywordController.text.trim().toLowerCase();
    if (value.isEmpty) return;
    if (_keywordFilters.contains(value)) {
      _keywordController.clear();
      return;
    }

    setState(() {
      _keywordFilters = [..._keywordFilters, value];
      _keywordController.clear();
    });
  }

  Future<void> _saveCurrentSelection() async {
    final selected = _selected;
    if (selected == null || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.adminService.updateAdminEmailScreening(
        accountId: selected.id,
        screeningSenderFilters: _senderFilters,
        screeningKeywordFilters: _keywordFilters,
        screeningScopeUnit: _scopeUnit,
        screeningScopeValue: _scopeValue,
        isActive: _isActive,
      );

      await widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email screening settings updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Email Integration',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Outlook first, Gmail next: configure sender/keyword screening and sync scope per connected inbox.',
            style: TextStyle(color: AppColors.grey600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Search connected inbox by email address',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _runSearch,
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          if (widget.error != null) const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildAccountsList(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: _buildEditorCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsList() {
    if (widget.isLoading && widget.accounts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.accounts.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey200),
        ),
        child: const Center(
          child: Text('No connected email accounts found'),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: ListView.separated(
        itemCount: widget.accounts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = widget.accounts[index];
          final selected = row.id == _selected?.id;
          return Material(
            color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
            child: ListTile(
              onTap: () {
                setState(() {
                  _selected = row;
                  _senderFilters = List<String>.from(row.screeningSenderFilters);
                  _keywordFilters = List<String>.from(row.screeningKeywordFilters);
                  _scopeUnit = row.screeningScopeUnit == 'months' ? 'months' : 'days';
                  _scopeValue = row.screeningScopeValue;
                  _scopeValueController.text = _scopeValue.toString();
                  _isActive = row.isActive;
                });
              },
              title: Text(row.emailAddress),
              subtitle: Text('${row.provider.toUpperCase()} · Household ${row.householdId.length > 8 ? row.householdId.substring(0, 8) : row.householdId}'),
              trailing: Icon(
                row.isActive ? Icons.check_circle : Icons.pause_circle,
                color: row.isActive ? AppColors.success : AppColors.warning,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditorCard() {
    final selected = _selected;
    if (selected == null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey200),
        ),
        child: const Center(
          child: Text('Select an email account to edit screening settings'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selected.emailAddress,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
            ),
            Text(
              '${selected.provider.toUpperCase()} inbox screening',
              style: const TextStyle(color: AppColors.grey600),
            ),
            const SizedBox(height: 16),
            _buildTokenInput(
              title: 'Sender Email Filters',
              hint: 'Add sender email and press +',
              controller: _senderController,
              values: _senderFilters,
              onAdd: _addSenderFilter,
              onRemove: (value) => setState(() => _senderFilters.remove(value)),
            ),
            const SizedBox(height: 16),
            _buildTokenInput(
              title: 'Keyword Filters',
              hint: 'Add keyword and press +',
              controller: _keywordController,
              values: _keywordFilters,
              onAdd: _addKeywordFilter,
              onRemove: (value) => setState(() => _keywordFilters.remove(value)),
            ),
            const SizedBox(height: 16),
            const Text('Sync Scope', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _scopeUnit,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'days', child: Text('Days')),
                      DropdownMenuItem(value: 'months', child: Text('Months')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _scopeUnit = value;
                        if (_scopeUnit == 'months' && _scopeValue > 24) {
                          _scopeValue = 24;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _scopeValueController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Value',
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed == null) return;
                      final cap = _scopeUnit == 'months' ? 24 : 365;
                      setState(() {
                        _scopeValue = parsed.clamp(1, cap);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveCurrentSelection,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenInput({
    required String title,
    required String hint,
    required TextEditingController controller,
    required List<String> values,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: hint,
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              Chip(
                label: Text(value),
                onDeleted: () => onRemove(value),
              ),
          ],
        ),
      ],
    );
  }
}
