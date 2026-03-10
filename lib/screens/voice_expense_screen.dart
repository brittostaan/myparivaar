import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_service.dart';
import '../services/auth_service.dart';
import '../services/expense_service.dart';

class VoiceExpenseScreen extends StatefulWidget {
  const VoiceExpenseScreen({super.key});

  @override
  State<VoiceExpenseScreen> createState() => _VoiceExpenseScreenState();
}

class _VoiceExpenseScreenState extends State<VoiceExpenseScreen>
    with TickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final ExpenseService _expenseService = ExpenseService();

  ExpenseFromVoice? _parsedExpense;
  String? _error;
  bool _isConfirming = false;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _voiceService.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startVoiceRecognition() async {
    setState(() {
      _error = null;
      _parsedExpense = null;
    });

    _animationController.repeat(reverse: true);

    await _voiceService.startListening(
      onResult: (result) {
        _animationController.stop();
        _animationController.reset();

        final parsed = _voiceService.parseExpenseFromVoice(result);
        setState(() {
          _parsedExpense = parsed;
          if (parsed == null) {
            _error = 'Could not understand the expense details. Please try again.';
          }
        });
      },
      onError: (error) {
        _animationController.stop();
        _animationController.reset();
        setState(() {
          _error = error;
        });
      },
    );
  }

  void _stopVoiceRecognition() {
    _voiceService.stopListening();
    _animationController.stop();
    _animationController.reset();
  }

  Future<void> _confirmExpense() async {
    if (_parsedExpense == null) return;

    setState(() {
      _isConfirming = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _expenseService.createExpense(
        amount: _parsedExpense!.amount,
        description: _parsedExpense!.description,
        category: _parsedExpense!.category,
        date: DateTime.now(),
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Expense added: ${_parsedExpense!.description} - ₹${_parsedExpense!.amount}'),
            backgroundColor: Colors.green,
          ),
        );

        // Reset for next entry
        setState(() {
          _parsedExpense = null;
          _isConfirming = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save expense: $e';
          _isConfirming = false;
        });
      }
    }
  }

  void _editExpense() {
    if (_parsedExpense == null) return;

    showDialog(
      context: context,
      builder: (context) => _ExpenseEditDialog(
        expense: _parsedExpense!,
        onSave: (updatedExpense) {
          setState(() {
            _parsedExpense = updatedExpense;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Expense Entry'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mic, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Voice Expense Entry',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the microphone and say something like:\n\n'
                      '• "Spent 150 rupees on groceries"\n'
                      '• "Paid 500 for electricity bill"\n'
                      '• "Auto rickshaw fare 80 rupees"\n\n'
                      'The app will extract the amount, description, and category automatically.',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Voice recording button
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _voiceService.isListening ? _pulseAnimation.value : 1.0,
                          child: GestureDetector(
                            onTap: _voiceService.isListening
                                ? _stopVoiceRecognition
                                : _startVoiceRecognition,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _voiceService.isListening
                                    ? Colors.red.shade100
                                    : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: _voiceService.isListening
                                      ? Colors.red
                                      : Theme.of(context).primaryColor,
                                  width: 3,
                                ),
                              ),
                              child: Icon(
                                _voiceService.isListening ? Icons.stop : Icons.mic,
                                size: 64,
                                color: _voiceService.isListening
                                    ? Colors.red
                                    : Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    Text(
                      _voiceService.isListening
                          ? 'Listening... Tap to stop'
                          : 'Tap the microphone to start',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
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

                    if (_parsedExpense != null) ...[
                      const SizedBox(height: 32),
                      _buildExpensePreview(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensePreview() {
    if (_parsedExpense == null) return const SizedBox.shrink();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Text(
                  'Expense Detected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Amount
            Row(
              children: [
                const Text('Amount: '),
                Text(
                  '₹${_parsedExpense!.amount}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Description
            Row(
              children: [
                const Text('Description: '),
                Expanded(
                  child: Text(
                    _parsedExpense!.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Category
            Row(
              children: [
                const Text('Category: '),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _parsedExpense!.category,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Original text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You said:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '"${_parsedExpense!.originalText}"',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editExpense,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isConfirming ? null : _confirmExpense,
                    icon: _isConfirming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isConfirming ? 'Saving...' : 'Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseEditDialog extends StatefulWidget {
  final ExpenseFromVoice expense;
  final Function(ExpenseFromVoice) onSave;

  const _ExpenseEditDialog({
    required this.expense,
    required this.onSave,
  });

  @override
  State<_ExpenseEditDialog> createState() => _ExpenseEditDialogState();
}

class _ExpenseEditDialogState extends State<_ExpenseEditDialog> {
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  late String _selectedCategory;

  final List<String> _categories = [
    'Food',
    'Transport',
    'Bills',
    'Shopping',
    'Healthcare',
    'Entertainment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.expense.amount.toString());
    _descriptionController = TextEditingController(text: widget.expense.description);
    _selectedCategory = widget.expense.category;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Expense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
            ),
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
            final updatedExpense = ExpenseFromVoice(
              amount: double.tryParse(_amountController.text) ?? widget.expense.amount,
              description: _descriptionController.text.trim().isNotEmpty
                  ? _descriptionController.text.trim()
                  : widget.expense.description,
              category: _selectedCategory,
              originalText: widget.expense.originalText,
            );
            widget.onSave(updatedExpense);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}