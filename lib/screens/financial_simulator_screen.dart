import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';

class FinancialSimulatorScreen extends StatefulWidget {
  const FinancialSimulatorScreen({super.key});

  @override
  State<FinancialSimulatorScreen> createState() =>
      _FinancialSimulatorScreenState();
}

class _FinancialSimulatorScreenState extends State<FinancialSimulatorScreen> {
  double _monthlyIncome = 50000;
  double _monthlyExpenses = 35000;
  double _monthlySavings = 5000;
  int _scenarioMonths = 6;
  double _expenseChangePct = 0;
  double _incomeChangePct = 0;

  bool _isSimulating = false;
  String? _projection;
  List<Map<String, dynamic>> _monthlyBreakdown = [];
  double? _actualMonthlyAvg;
  int? _usesRemaining;
  String? _error;

  Future<void> _runSimulation() async {
    setState(() {
      _isSimulating = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().runFinancialSimulation(
        monthlyIncome: _monthlyIncome,
        monthlyExpenses: _monthlyExpenses,
        monthlySavings: _monthlySavings,
        scenarioMonths: _scenarioMonths,
        expenseChangePct: _expenseChangePct,
        incomeChangePct: _incomeChangePct,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      setState(() {
        _projection = result['projection'] as String?;
        _monthlyBreakdown = (result['monthly_breakdown'] as List<dynamic>?)
                ?.map((m) => Map<String, dynamic>.from(m as Map))
                .toList() ??
            [];
        _actualMonthlyAvg = (result['actual_monthly_avg'] as num?)?.toDouble();
        _usesRemaining = result['uses_remaining'] as int?;
        _isSimulating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSimulating = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'What-If Scenario',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust the sliders to model different financial scenarios.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 20),
          _buildSlider(
            label: 'Monthly Income',
            value: _monthlyIncome,
            min: 10000,
            max: 500000,
            divisions: 49,
            prefix: '₹',
            onChanged: (v) => setState(() => _monthlyIncome = v),
          ),
          _buildSlider(
            label: 'Monthly Expenses',
            value: _monthlyExpenses,
            min: 5000,
            max: 400000,
            divisions: 79,
            prefix: '₹',
            onChanged: (v) => setState(() => _monthlyExpenses = v),
          ),
          _buildSlider(
            label: 'Monthly Savings Target',
            value: _monthlySavings,
            min: 0,
            max: 200000,
            divisions: 40,
            prefix: '₹',
            onChanged: (v) => setState(() => _monthlySavings = v),
          ),
          _buildSlider(
            label: 'Projection Period',
            value: _scenarioMonths.toDouble(),
            min: 1,
            max: 24,
            divisions: 23,
            suffix: ' months',
            onChanged: (v) => setState(() => _scenarioMonths = v.round()),
          ),
          const Divider(height: 24),
          Text(
            'OPTIONAL CHANGES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _buildSlider(
            label: 'Expense Change',
            value: _expenseChangePct,
            min: -50,
            max: 50,
            divisions: 20,
            suffix: '%',
            activeColor: _expenseChangePct > 0
                ? AppColors.error
                : _expenseChangePct < 0
                    ? AppColors.success
                    : Colors.teal,
            onChanged: (v) => setState(() => _expenseChangePct = v),
          ),
          _buildSlider(
            label: 'Income Change',
            value: _incomeChangePct,
            min: -50,
            max: 50,
            divisions: 20,
            suffix: '%',
            activeColor: _incomeChangePct > 0
                ? AppColors.success
                : _incomeChangePct < 0
                    ? AppColors.error
                    : Colors.teal,
            onChanged: (v) => setState(() => _incomeChangePct = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSimulating ? null : _runSimulation,
              icon: _isSimulating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow, size: 20),
              label: Text(
                  _isSimulating ? 'Simulating...' : 'Run Simulation'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_usesRemaining != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$_usesRemaining simulations remaining this month',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 13)),
          ),

        if (_projection == null && _error == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.trending_up, size: 48, color: Colors.teal.shade200),
                const SizedBox(height: 12),
                Text(
                  'Run a simulation to see results',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

        if (_projection != null) ...[
          // Actual spending baseline
          if (_actualMonthlyAvg != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Your actual monthly average spending: ₹${_actualMonthlyAvg!.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),

          // AI Projection
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      'AI Projection',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_projection!,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ),
          ),

          // Monthly breakdown table
          if (_monthlyBreakdown.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Monthly Breakdown',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                            flex: 2,
                            child: Text('Month',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12))),
                        Expanded(
                            child: Text('Income',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('Expenses',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('Net',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                                textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  ..._monthlyBreakdown.map((m) {
                    final net = ((m['income'] as num?) ?? 0) -
                        ((m['expenses'] as num?) ?? 0);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              m['month']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '₹${((m['income'] as num?) ?? 0).toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '₹${((m['expenses'] as num?) ?? 0).toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${net >= 0 ? '+' : ''}₹${net.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: net >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
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
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Financial Simulator',
              avatarIcon: Icons.trending_up,
              showViewModeSelector: false,
              showSettingsButton: false,
              showNotifications: false,
            ),
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Input panel
                        SizedBox(
                          width: 400,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _buildInputPanel(),
                          ),
                        ),
                        // Right: Results panel
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                            child: _buildResultsPanel(),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInputPanel(),
                          const SizedBox(height: 16),
                          _buildResultsPanel(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String prefix = '',
    String suffix = '',
    Color? activeColor,
  }) {
    String displayValue;
    if (suffix == ' months') {
      displayValue = '${value.round()}$suffix';
    } else if (suffix == '%') {
      displayValue =
          '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)}$suffix';
    } else {
      displayValue = '$prefix${value.toStringAsFixed(0)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(displayValue,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: activeColor ?? Colors.teal.shade700)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activeColor ?? Colors.teal,
              thumbColor: activeColor ?? Colors.teal,
              inactiveTrackColor:
                  (activeColor ?? Colors.teal).withOpacity(0.2),
              overlayColor:
                  (activeColor ?? Colors.teal).withOpacity(0.1),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
