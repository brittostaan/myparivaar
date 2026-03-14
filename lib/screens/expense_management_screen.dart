import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';
import '../models/expense.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  final ExpenseService _expenseService = ExpenseService();
  List<Expense> _expenses = [];
  bool _isLoading = true;
  String? _error;
  String? _errorDiagnostics;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final expenses = await _expenseService.getExpenses(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        setState(() {
          _expenses = expenses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorDiagnostics = e is ExpenseException ? e.diagnostics : 'Exception type: ${e.runtimeType}\n$e';
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

    if (confirmed != true) return;

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
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addExpense,
        child: const Icon(AppIcons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Expenses',
              avatarIcon: AppIcons.wallet,
            ),
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.errorDark)),
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
            const Icon(AppIcons.receiptOutlined, size: 64, color: AppColors.grey400),
            const SizedBox(height: 16),
            Text('No expenses yet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Tap the + button to add your first expense'),
          ],
        ),
      );
    }

    // Group expenses by month
    final groupedExpenses = <String, List<Expense>>{};
    for (final expense in _expenses) {
      final monthKey = '${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}';
      groupedExpenses.putIfAbsent(monthKey, () => []).add(expense);
    }
    final now = DateTime.now();
    final currentMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    return ListView.builder(
      itemCount: groupedExpenses.length,
      itemBuilder: (context, index) {
        final monthKey = groupedExpenses.keys.elementAt(index);
        final monthExpenses = groupedExpenses[monthKey]!;
        final totalAmount = monthExpenses.fold<double>(0, (sum, e) => sum + e.amount);

        final monthName = _getMonthName(monthKey);

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            initiallyExpanded: monthKey == currentMonthKey,
            title: Text(monthName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${monthExpenses.length} transactions • ${_formatCurrency(totalAmount)}'),
            children: monthExpenses.map((expense) => _buildExpenseItem(expense)).toList(),
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
      subtitle: Text('${expense.category} • ${_formatDate(expense.date)}'),
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
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    return '${monthNames[month - 1]} $year';
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
  
  String _selectedCategory = 'food';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.expense != null) {
      _amountController.text = widget.expense!.amount.toStringAsFixed(2);
      _notesController.text = widget.expense!.notes ?? '';
      _selectedCategory = widget.expense!.category;
      _selectedDate = widget.expense!.date;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
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
                          _amountController.text.isEmpty ? '0.00' : _amountController.text,
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
                    
                    const SizedBox(height: 60),
                    
                    // Category Selection
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'SELECT CATEGORY',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[400],
                          letterSpacing: 1.2,
                        ),
                      ),
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
                        _buildCategoryButton('food', 'Food', AppIcons.food, Colors.orange),
                        _buildCategoryButton('transport', 'Transport', AppIcons.transport, Colors.blue),
                        _buildCategoryButton('shopping', 'Shopping', AppIcons.shopping, Colors.pink),
                        _buildCategoryButton('utilities', 'Bills', AppIcons.utilities, Colors.green),
                        _buildCategoryButton('entertainment', 'Entertain', AppIcons.entertainment, Colors.purple),
                        _buildCategoryButton('other', 'Others', Icons.more_horiz, Colors.grey),
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
                              Icon(AppIcons.calendar, color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _selectedDate.day == DateTime.now().day &&
                                _selectedDate.month == DateTime.now().month &&
                                _selectedDate.year == DateTime.now().year
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
                              const SnackBar(content: Text('Receipt upload coming soon!')),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(Icons.camera_alt_outlined, color: Colors.grey[600], size: 20),
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
                  onPressed: _isLoading ? null : () => _showAmountDialog(context),
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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

  Widget _buildCategoryButton(String category, String label, IconData icon, Color color) {
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

      if (widget.expense == null) {
        // Create new expense
        await expenseService.createExpense(
          amount: amount,
          category: _selectedCategory,
          description: description.isEmpty ? _selectedCategory : description,
          date: _selectedDate,
          notes: notes.isEmpty ? null : notes,
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