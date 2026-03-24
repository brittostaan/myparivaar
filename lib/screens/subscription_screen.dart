import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

class SubscriptionScreen extends StatefulWidget {
  final String supabaseUrl;
  const SubscriptionScreen({super.key, required this.supabaseUrl});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _http = http.Client();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _gateways = [];
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _currentPlan;
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(String action, [Map<String, dynamic>? extra]) async {
    final auth = context.read<AuthService>();
    final token = await auth.getIdToken(true);
    final body = <String, dynamic>{'action': action, ...?extra};

    final response = await _http.post(
      Uri.parse('${widget.supabaseUrl}/functions/v1/subscription'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Request failed');
    }
    return data;
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _call('get_plans'),
        _call('get_active_gateways'),
        _call('get_subscription'),
        _call('get_payment_history'),
      ]);

      if (mounted) {
        setState(() {
          _plans = (results[0]['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _gateways = (results[1]['gateways'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _subscription = results[2]['subscription'] as Map<String, dynamic>?;
          _currentPlan = results[2]['plan'] as Map<String, dynamic>?;
          _payments = (results[3]['payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeader(
          title: 'Subscription',
          subtitle: 'Manage your plan and payments',
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _loadAll, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCurrentSubscription(),
                                const SizedBox(height: 32),
                                _buildPlansSection(),
                                const SizedBox(height: 32),
                                _buildPaymentHistory(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  // ── Current Subscription Card ─────────────────────────────────────────────

  Widget _buildCurrentSubscription() {
    if (_subscription == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[300]!),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.card_membership_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              const Text(
                'No Active Subscription',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a plan below to get started.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final status = _subscription!['status'] ?? 'unknown';
    final gateway = _subscription!['gateway'] ?? '';
    final periodEnd = _subscription!['current_period_end'];
    final planName = _currentPlan?['name'] ?? 'Unknown Plan';
    final priceMonthly = _currentPlan?['price_monthly'];

    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = Colors.green;
      case 'trialing':
        statusColor = Colors.blue;
      case 'past_due':
        statusColor = Colors.orange;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status.toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'via ${_gatewayDisplayName(gateway)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (priceMonthly != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹$priceMonthly',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                      ),
                      Text('/month', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
              ],
            ),
            if (periodEnd != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: AppColors.grey600),
                  const SizedBox(width: 6),
                  Text(
                    'Renews on ${_formatDate(periodEnd)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.grey600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _confirmCancel(),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Plans Section ─────────────────────────────────────────────────────────

  Widget _buildPlansSection() {
    if (_plans.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Plans',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the plan that works for your family.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth > 700 ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _plans.map((plan) {
                final isCurrentPlan = _currentPlan != null && _currentPlan!['id'] == plan['id'];
                return SizedBox(
                  width: cardWidth.clamp(260, 360).toDouble(),
                  child: _buildPlanCard(plan, isCurrentPlan),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, bool isCurrentPlan) {
    final name = plan['name'] ?? '';
    final priceMonthly = plan['price_monthly'] ?? 0;
    final features = plan['features'] as List? ?? [];
    final maxMembers = plan['max_members'];

    return Card(
      elevation: isCurrentPlan ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrentPlan ? const Color(0xFF2563EB) : Colors.grey[300]!,
          width: isCurrentPlan ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCurrentPlan)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CURRENT PLAN',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                ),
              ),
            Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹$priceMonthly',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('/month', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ),
              ],
            ),
            if (maxMembers != null) ...[
              const SizedBox(height: 8),
              Text('Up to $maxMembers family members', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ...features.take(6).map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f.toString(), style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: isCurrentPlan
                  ? OutlinedButton(
                      onPressed: null,
                      child: const Text('Current Plan'),
                    )
                  : FilledButton(
                      onPressed: _gateways.isEmpty
                          ? null
                          : () => _showSubscribeDialog(plan),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      child: Text(
                        _subscription != null ? 'Switch Plan' : 'Subscribe',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment History ───────────────────────────────────────────────────────

  Widget _buildPaymentHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment History',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (_payments.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No payments yet.', style: TextStyle(color: Colors.grey[600])),
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Column(
              children: _payments.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final amount = (p['amount_cents'] as int? ?? 0) / 100;
                final status = p['status'] ?? 'pending';
                final description = p['description'] ?? '';
                final date = p['created_at'] ?? '';

                Color statusColor;
                switch (status) {
                  case 'succeeded':
                    statusColor = Colors.green;
                  case 'failed':
                    statusColor = Colors.red;
                  case 'refunded':
                    statusColor = Colors.orange;
                  default:
                    statusColor = Colors.grey;
                }

                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.1),
                        child: Icon(
                          status == 'succeeded'
                              ? Icons.check
                              : status == 'failed'
                                  ? Icons.close
                                  : Icons.hourglass_empty,
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      title: Text(description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        '${_formatDate(date)} • ${_gatewayDisplayName(p['gateway'] ?? '')}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (i < _payments.length - 1) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showSubscribeDialog(Map<String, dynamic> plan) {
    String? selectedGateway = _gateways.isNotEmpty ? _gateways[0]['gateway'] as String : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Choose Payment Method'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscribing to ${plan['name']} — ₹${plan['price_monthly']}/month',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                const Text('Payment Gateway', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._gateways.map((gw) {
                  final key = gw['gateway'] as String;
                  final name = gw['display_name'] as String? ?? key;
                  final isTest = gw['is_test_mode'] == true;
                  return RadioListTile<String>(
                    value: key,
                    groupValue: selectedGateway,
                    onChanged: (v) => setDialogState(() => selectedGateway = v),
                    title: Text(name),
                    subtitle: isTest ? const Text('Test Mode', style: TextStyle(fontSize: 11, color: Colors.amber)) : null,
                    secondary: Icon(_gatewayIcon(key)),
                    contentPadding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedGateway == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _subscribe(plan['id'] as String, selectedGateway!);
                    },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              child: const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe(String planId, String gateway) async {
    setState(() => _loading = true);
    try {
      await _call('create_subscription', {'plan_id': planId, 'gateway': gateway});
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription activated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel? You will continue to have access until the end of your billing period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Subscription'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              try {
                await _call('cancel_subscription', {
                  'subscription_id': _subscription!['id'],
                });
                await _loadAll();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Subscription cancelled'), backgroundColor: Colors.orange),
                  );
                }
              } catch (e) {
                setState(() => _loading = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _gatewayDisplayName(String key) {
    switch (key) {
      case 'stripe':
        return 'Stripe';
      case 'razorpay':
        return 'Razorpay';
      case 'phonepe':
        return 'PhonePe';
      default:
        return key;
    }
  }

  IconData _gatewayIcon(String key) {
    switch (key) {
      case 'stripe':
        return Icons.credit_card_rounded;
      case 'razorpay':
        return Icons.account_balance_rounded;
      case 'phonepe':
        return Icons.phone_android_rounded;
      default:
        return Icons.payment;
    }
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}
