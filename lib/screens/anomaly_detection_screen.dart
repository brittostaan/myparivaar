import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class AnomalyDetectionScreen extends StatefulWidget {
  const AnomalyDetectionScreen({super.key});

  @override
  State<AnomalyDetectionScreen> createState() => _AnomalyDetectionScreenState();
}

class _AnomalyDetectionScreenState extends State<AnomalyDetectionScreen> {
  bool _isScanning = false;
  String? _summary;
  List<Map<String, dynamic>> _anomalies = [];
  int? _transactionCount;
  int? _usesRemaining;
  String? _error;

  Future<void> _scanForAnomalies() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().detectAnomalies(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      setState(() {
        _summary = result['summary'] as String?;
        _anomalies = (result['anomalies'] as List<dynamic>?)
                ?.map((a) => Map<String, dynamic>.from(a as Map))
                .toList() ??
            [];
        _transactionCount = result['transaction_count'] as int?;
        _usesRemaining = result['uses_remaining'] as int?;
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              title: 'Anomaly Detection',
              avatarIcon: Icons.warning_amber_rounded,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange.shade50, Colors.amber.shade50],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'AI-Powered Spending Scan',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Scans your last 90 days of transactions to detect unusual spending patterns, duplicate charges, and outliers.',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isScanning ? null : _scanForAnomalies,
                              icon: _isScanning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.search, size: 18),
                              label: Text(_isScanning
                                  ? 'Scanning...'
                                  : _summary != null
                                      ? 'Scan Again'
                                      : 'Scan for Anomalies'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          if (_usesRemaining != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '$_usesRemaining scans remaining this month',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                      ),
                    ],

                    if (_summary != null) ...[
                      const SizedBox(height: 20),
                      // Summary card
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
                            Row(
                              children: [
                                const Icon(AppIcons.summarize, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Analysis Summary',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const Spacer(),
                                if (_transactionCount != null)
                                  Text(
                                    '$_transactionCount txns analyzed',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(_summary!, style: const TextStyle(fontSize: 14, height: 1.5)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Anomalies list
                      if (_anomalies.isNotEmpty) ...[
                        Text(
                          'Flagged Transactions (${_anomalies.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        ..._anomalies.map((a) => _buildAnomalyCard(a)),
                      ] else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.check_circle, color: AppColors.success, size: 40),
                              SizedBox(height: 8),
                              Text(
                                'No anomalies detected!',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Your spending patterns look normal.',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildAnomalyCard(Map<String, dynamic> anomaly) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  anomaly['description']?.toString() ?? 'Transaction',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                '₹${anomaly['amount'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (anomaly['date'] != null)
                Text(
                  anomaly['date'].toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              if (anomaly['category'] != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    anomaly['category'].toString(),
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ),
              ],
            ],
          ),
          if (anomaly['reason'] != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                anomaly['reason'].toString(),
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
