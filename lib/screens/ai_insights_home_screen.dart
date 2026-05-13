import 'package:flutter/material.dart';

/// Minimal home screen showing only AI Insights section.
/// Wrapped in NavigationShell by main.dart for global nav.
class AIInsightsHomeScreen extends StatelessWidget {
  const AIInsightsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildAISection(context, isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildAISection(BuildContext context, bool isMobile) {
    final capabilities = [
      _AICapability(
        Icons.category_outlined,
        'Smart Categorisation',
        'AI auto-categorises expenses into food, transport, utilities, shopping, and more.',
      ),
      _AICapability(
        Icons.analytics_outlined,
        'Budget Analysis',
        'Get AI-written insights about your spending habits and actionable suggestions.',
      ),
      _AICapability(
        Icons.warning_amber_outlined,
        'Anomaly Detection',
        'AI flags unusual spending patterns — duplicate charges, sudden spikes, outlier transactions.',
      ),
      _AICapability(
        Icons.mic_outlined,
        'Voice Entry',
        'Say "Spent 500 on groceries at BigBazaar" and AI creates the expense for you.',
      ),
      _AICapability(
        Icons.email_outlined,
        'Email Parsing',
        'AI reads bank emails and extracts merchant, amount, date, card, UPI — automatically.',
      ),
      _AICapability(
        Icons.show_chart,
        'Forecasting',
        'AI predicts next month\'s expenses based on your spending trends and budget patterns.',
      ),
    ];

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 600),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 64,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Column(
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Color(0xFFA78BFA)),
                SizedBox(width: 6),
                Text(
                  'Powered by AI',
                  style: TextStyle(
                    color: Color(0xFFA78BFA),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Title
          const Text(
            'AI That Understands\nIndian Family Finance',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          // Subtitle
          Text(
            'Built with OpenAI, Gemini, and Claude — choose your provider',
            style: TextStyle(fontSize: 15, color: Colors.grey[400]),
          ),
          const SizedBox(height: 40),
          // Capability cards
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: capabilities.map((c) => _aiCard(c, isMobile)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _aiCard(_AICapability c, bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 340,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(c.icon, color: const Color(0xFFA78BFA), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.desc,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    height: 1.5,
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

class _AICapability {
  final IconData icon;
  final String title;
  final String desc;
  const _AICapability(this.icon, this.title, this.desc);
}
