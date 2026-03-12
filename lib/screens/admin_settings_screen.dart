import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _householdNameController = TextEditingController();
  
  bool _isLoading = false;
  String? _error;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _loadHouseholdData();
  }

  @override
  void dispose() {
    _householdNameController.dispose();
    super.dispose();
  }

  Future<void> _loadHouseholdData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final household = authService.currentHousehold;
    
    if (household != null) {
      setState(() {
        _householdNameController.text = household.name;
      });
    }
  }

  Future<void> _updateHouseholdName() async {
    final newName = _householdNameController.text.trim();
    if (newName.isEmpty) {
      setState(() {
        _error = 'Household name cannot be empty';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // In a real app, would call family service to update household name
      await Future.delayed(const Duration(seconds: 1)); // Simulated API call
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Household name updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to update household name: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateInviteCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // In a real app, would call family service to generate new invite code
      await Future.delayed(const Duration(seconds: 1)); // Simulated API call
      
      // Mock invite code for demonstration
      final mockCode = 'FAM${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      
      if (mounted) {
        setState(() {
          _inviteCode = mockCode;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New invite code generated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate invite code: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _copyInviteCode() async {
    if (_inviteCode == null) return;

    // In a real app, would use Clipboard.setData
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite code "$_inviteCode" copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _transferAdmin() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Admin Rights'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select a family member to transfer admin rights to:'),
            SizedBox(height: 16),
            Text(
              'Note: You will lose admin privileges and cannot undo this action.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // In a real app, would show member selection dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transfer admin feature coming soon!'),
                ),
              );
            },
            child: const Text('Select Member'),
          ),
        ],
      ),
    );
  }

  Future<void> _setBudgetLimits() async {
    showDialog(
      context: context,
      builder: (context) => _BudgetLimitsDialog(),
    );
  }

  Future<void> _manageCategories() async {
    showDialog(
      context: context,
      builder: (context) => _ManageCategoriesDialog(),
    );
  }

  Future<void> _deleteHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Household'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this household?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('This will:'),
            Text('• Remove all family members from the household'),
            Text('• Delete all expense records'),
            Text('• Delete all AI summaries and chat history'),
            Text('• Cannot be undone'),
            SizedBox(height: 16),
            Text(
              'All family members will need to create new households or join other households.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Household'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // In a real app, would call delete household API
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Household deletion feature coming soon!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    // Role-based check is resilient across schema variations.
    final isAdmin = user?.isAdmin == true || user?.isSuperAdmin == true;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Settings'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Admin Access Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Only household administrators can access these settings.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Household Management Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Household Management',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _householdNameController,
                    decoration: const InputDecoration(
                      labelText: 'Household Name',
                      border: OutlineInputBorder(),
                      helperText: 'This name is visible to all family members',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _updateHouseholdName,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Member Invitation Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_add, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Invite Family Members',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_inviteCode != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Invite Code:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _inviteCode!,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Share this code with family members to invite them',
                                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _copyInviteCode,
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy Code',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _generateInviteCode,
                          icon: const Icon(Icons.refresh),
                          label: Text(_inviteCode == null ? 'Generate Invite Code' : 'Generate New Code'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Invite codes expire after 7 days and can be used by up to 7 family members.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Financial Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Financial Settings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.trending_up),
                    title: const Text('Budget Limits'),
                    subtitle: const Text('Set monthly spending limits by category'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _setBudgetLimits,
                  ),
                  ListTile(
                    leading: const Icon(Icons.category),
                    title: const Text('Manage Categories'),
                    subtitle: const Text('Add, edit, or remove expense categories'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _manageCategories,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Admin Actions Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Admin Actions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Transfer Admin Rights'),
                    subtitle: const Text('Make another family member the admin'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _transferAdmin,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Danger Zone Section
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Danger Zone',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
                    title: Text(
                      'Delete Household',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    subtitle: const Text('Permanently delete the entire household and all data'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _deleteHousehold,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetLimitsDialog extends StatefulWidget {
  @override
  State<_BudgetLimitsDialog> createState() => _BudgetLimitsDialogState();
}

class _BudgetLimitsDialogState extends State<_BudgetLimitsDialog> {
  final Map<String, double> _budgetLimits = {
    'Food': 10000.0,
    'Transport': 5000.0,
    'Bills': 8000.0,
    'Shopping': 6000.0,
    'Healthcare': 3000.0,
    'Entertainment': 4000.0,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monthly Budget Limits'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set monthly spending limits for each category (in ₹):'),
            const SizedBox(height: 16),
            ..._budgetLimits.keys.map<Widget>((category) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(category),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: '₹',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        controller: TextEditingController(
                          text: _budgetLimits[category]?.toStringAsFixed(0) ?? '0',
                        ),
                        onChanged: (value) {
                          _budgetLimits[category] = double.tryParse(value) ?? 0.0;
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Budget limits updated'),
                backgroundColor: Colors.green,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ManageCategoriesDialog extends StatefulWidget {
  @override
  State<_ManageCategoriesDialog> createState() => _ManageCategoriesDialogState();
}

class _ManageCategoriesDialogState extends State<_ManageCategoriesDialog> {
  final List<String> _categories = [
    'Food',
    'Transport',
    'Bills',
    'Shopping',
    'Healthcare',
    'Entertainment',
    'Other',
  ];

  final _newCategoryController = TextEditingController();

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  void _addCategory() {
    final newCategory = _newCategoryController.text.trim();
    if (newCategory.isNotEmpty && !_categories.contains(newCategory)) {
      setState(() {
        _categories.add(newCategory);
        _newCategoryController.clear();
      });
    }
  }

  void _removeCategory(String category) {
    if (_categories.length > 1) {
      setState(() {
        _categories.remove(category);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Categories'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategoryController,
                    decoration: const InputDecoration(
                      labelText: 'New Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Current Categories:'),
            ),
            const SizedBox(height: 8),
            ..._categories.map<Widget>((category) {
              return Card(
                child: ListTile(
                  title: Text(category),
                  trailing: _categories.length > 1
                      ? IconButton(
                          onPressed: () => _removeCategory(category),
                          icon: const Icon(Icons.delete),
                          color: Colors.red,
                        )
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Categories updated'),
                backgroundColor: Colors.green,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}