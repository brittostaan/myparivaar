import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/voice_service.dart';
import '../services/expense_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class VoiceExpenseScreen extends StatefulWidget {
  const VoiceExpenseScreen({super.key});

  @override
  State<VoiceExpenseScreen> createState() => _VoiceExpenseScreenState();
}

class _VoiceExpenseScreenState extends State<VoiceExpenseScreen> {
  late VoiceService _voiceService;
  late ExpenseService _expenseService;

  bool _isListening = false;
  bool _isProcessing = false;
  String? _lastTranscription;
  String? _errorMessage;
  ExpenseFromVoice? _recognizedExpense;

  @override
  void initState() {
    super.initState();
    _voiceService = VoiceService();
    _expenseService = ExpenseService();
  }

  Future<void> _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      _errorMessage = null;
      _lastTranscription = null;
      _recognizedExpense = null;
    });

    try {
      await _voiceService.startListening(
        onResult: (transcription) {
          if (!mounted) return;
          setState(() => _lastTranscription = transcription);
          _processTranscription(transcription);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _errorMessage = error;
            _isListening = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isListening = false;
      });
    }
  }

  Future<void> _processTranscription(String transcription) async {
    setState(() => _isProcessing = true);

    try {
      final authService = context.read<AuthService>();
      final idToken = await authService.getIdToken();
      if (!mounted) return;

      // Parse the voice input to extract expense details
      final expense = await _voiceService.parseExpenseFromVoiceAI(
        transcription,
        supabaseUrl: authService.supabaseUrl,
        idToken: idToken,
      );

      if (!mounted) return;

      if (expense == null) {
        setState(() {
          _errorMessage = 'Could not understand expense details. Please try again.';
          _isListening = false;
          _isProcessing = false;
        });
        return;
      }

      // Save the recognized expense
      setState(() {
        _recognizedExpense = expense;
        _isListening = false;
        _isProcessing = false;
      });

      // Show confirmation dialog
      if (mounted) {
        _showExpenseConfirmationDialog(expense);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Processing error: ${e.toString()}';
        _isListening = false;
        _isProcessing = false;
      });
    }
  }

  void _showExpenseConfirmationDialog(ExpenseFromVoice expense) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Expense Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recognized details:'),
            const SizedBox(height: 12),
            _DetailRow(label: 'Amount:', value: '₹${expense.amount.toStringAsFixed(2)}'),
            _DetailRow(label: 'Category:', value: expense.category),
            _DetailRow(label: 'Description:', value: expense.description),
            const SizedBox(height: 16),
            const Text(
              'Note: Voice recognition is experimental. Please review and edit details as needed.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _recognizedExpense = null);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveExpense(expense);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveExpense(ExpenseFromVoice expense) async {
    try {
      final authService = context.read<AuthService>();
      final idToken = await authService.getIdToken();
      if (!mounted) return;

      await _expenseService.createExpense(
        amount: expense.amount,
        category: expense.category,
        description: expense.description,
        date: DateTime.now(),
        tags: [],
        supabaseUrl: authService.supabaseUrl,
        idToken: idToken,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );

      setState(() => _recognizedExpense = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save expense: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Expense'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Microphone Icon / Status
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _isListening
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.grey100,
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: Icon(
                    _isListening ? AppIcons.mic : Icons.mic_none,
                    size: 60,
                    color: _isListening ? AppColors.primary : AppColors.grey600,
                  ),
                ),
                const SizedBox(height: 32),

                // Status Text
                Text(
                  _isListening
                      ? 'Listening...'
                      : _isProcessing
                          ? 'Processing...'
                          : 'Tap to speak',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                if (_lastTranscription != null)
                  Text(
                    '"$_lastTranscription"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.grey600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 48),

                // Microphone Button
                FloatingActionButton.large(
                  onPressed: _isListening || _isProcessing ? null : _startListening,
                  backgroundColor: AppColors.primary,
                  child: const Icon(
                    AppIcons.mic,
                    size: 32,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 32),

                // Help Text
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How to use:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Tap the microphone button to start recording\n'
                        '2. Speak your expense details (e.g., "Coffee, 50 rupees")\n'
                        '3. Review and confirm the details\n'
                        '4. The expense will be saved automatically',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey600,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.grey700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
