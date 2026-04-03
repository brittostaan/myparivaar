import 'package:flutter/material.dart';

class LandingPageScreen extends StatelessWidget {
  const LandingPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildNavBar(context, isMobile),
            _buildHero(context, isMobile),
            _buildFeatures(context, isMobile),
            _buildHowItWorks(context, isMobile),
            _buildEmailIntegration(context, isMobile),
            _buildAISection(context, isMobile),
            _buildCTA(context, isMobile),
            _buildFooter(context, isMobile),
          ],
        ),
      ),
    );
  }

  // ── Navigation Bar ──────────────────────────────────────────────────────

  Widget _buildNavBar(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 60,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo – clickable → home
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'myParivaar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2332),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (!isMobile) ...[
            _navLink(context, 'Features', '#features'),
            const SizedBox(width: 28),
            _navLink(context, 'How it Works', '#how'),
            const SizedBox(width: 28),
            _navLink(context, 'Privacy', '/privacy'),
            const SizedBox(width: 28),
          ],
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Sign In'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _navLink(BuildContext context, String label, String route) {
    return InkWell(
      onTap: () {
        if (route.startsWith('/')) {
          Navigator.pushNamed(context, route);
        }
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Hero Section ────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: isMobile ? 48 : 80,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC), Color(0xFFF0F9FF)],
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'AI-Powered Family Finance for India',
              style: TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your Family\'s\nFinancial Command Centre',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isMobile ? 32 : 52,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              height: 1.15,
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              'Track expenses, manage budgets, monitor investments, and get AI-powered insights — all in one place for your entire household.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                color: Colors.grey[600],
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 36),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Start Free'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // Trust badges
          Wrap(
            spacing: 24,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _trustBadge(Icons.shield_outlined, 'Bank-level Security'),
              _trustBadge(Icons.lock_outline, '256-bit Encryption'),
              _trustBadge(Icons.family_restroom, 'Multi-member Households'),
              _trustBadge(Icons.auto_awesome, 'AI-Powered Insights'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trustBadge(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      ],
    );
  }

  // ── Features ────────────────────────────────────────────────────────────

  Widget _buildFeatures(BuildContext context, bool isMobile) {
    const features = [
      _Feature(
        icon: Icons.account_balance_wallet_outlined,
        color: Color(0xFF2563EB),
        title: 'Expense Tracking',
        desc: 'Log and categorise daily expenses manually, via CSV import, or automatically from bank emails. Every rupee accounted for.',
      ),
      _Feature(
        icon: Icons.pie_chart_outline,
        color: Color(0xFF059669),
        title: 'Smart Budgets',
        desc: 'Set monthly budgets per category and track progress in real-time. Get alerts before you overspend.',
      ),
      _Feature(
        icon: Icons.trending_up,
        color: Color(0xFFD97706),
        title: 'Investment Portfolio',
        desc: 'Track mutual funds, stocks, fixed deposits, gold, and crypto in one unified view with current valuations.',
      ),
      _Feature(
        icon: Icons.receipt_long_outlined,
        color: Color(0xFF7C3AED),
        title: 'Bill Reminders',
        desc: 'Never miss a payment. Track upcoming bills with due dates, amounts, and automatic reminders.',
      ),
      _Feature(
        icon: Icons.bar_chart_outlined,
        color: Color(0xFFDC2626),
        title: 'Financial Reports',
        desc: 'Monthly spending breakdowns, category analysis, income vs expense trends, and exportable reports.',
      ),
      _Feature(
        icon: Icons.savings_outlined,
        color: Color(0xFF0891B2),
        title: 'Savings Goals',
        desc: 'Set targets for family goals — education, travel, emergency fund — and track contributions from all members.',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 64,
      ),
      color: Colors.white,
      child: Column(
        children: [
          const Text(
            'Everything Your Family Needs',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A complete financial toolkit designed for Indian households',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: features
                .map((f) => _featureCard(f, isMobile))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _featureCard(_Feature f, bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 350,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: f.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(f.icon, color: f.color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            f.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            f.desc,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── How it Works ────────────────────────────────────────────────────────

  Widget _buildHowItWorks(BuildContext context, bool isMobile) {
    final steps = [
      _Step('1', 'Create Your Household',
          'Sign up and create a household. Invite family members — spouse, parents, children — to join.'),
      _Step('2', 'Connect & Track',
          'Add expenses manually, import from CSV, or connect your Gmail/Outlook to auto-detect bank transactions.'),
      _Step('3', 'Set Budgets & Goals',
          'Define monthly category budgets and savings goals. The whole family contributes and stays aligned.'),
      _Step('4', 'Get AI Insights',
          'AI analyses your spending patterns, detects anomalies, forecasts next month, and suggests optimisations.'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 64,
      ),
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Get started in minutes, not hours',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: steps.map((s) => _stepCard(s, isMobile)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(_Step s, bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 260,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                s.number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            s.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.desc,
            style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── Email Integration ───────────────────────────────────────────────────

  Widget _buildEmailIntegration(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 64,
      ),
      color: Colors.white,
      child: Column(
        children: [
          const Text(
            'Auto-Import from Bank Emails',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              'Connect your Gmail or Outlook and we\'ll automatically scan for HDFC, SBI, ICICI, Axis, Kotak and other Indian bank transaction notifications.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[500], height: 1.6),
            ),
          ),
          const SizedBox(height: 36),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _emailChip(Icons.email_outlined, 'Gmail', const Color(0xFFEA4335)),
              _emailChip(Icons.email_outlined, 'Outlook', const Color(0xFF0078D4)),
            ],
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2563EB).withOpacity(0.05),
                    const Color(0xFF7C3AED).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Read-only access. We never send emails or modify your inbox.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Transactions are imported as "Pending" — you approve before they count.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI extracts merchant names, amounts, card details, and UPI references.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── AI Section ──────────────────────────────────────────────────────────

  Widget _buildAISection(BuildContext context, bool isMobile) {
    final capabilities = [
      _AICapability(Icons.category_outlined, 'Smart Categorisation',
          'AI auto-categorises expenses into food, transport, utilities, shopping, and more.'),
      _AICapability(Icons.analytics_outlined, 'Budget Analysis',
          'Get AI-written insights about your spending habits and actionable suggestions.'),
      _AICapability(Icons.warning_amber_outlined, 'Anomaly Detection',
          'AI flags unusual spending patterns — duplicate charges, sudden spikes, outlier transactions.'),
      _AICapability(Icons.mic_outlined, 'Voice Entry',
          'Say "Spent 500 on groceries at BigBazaar" and AI creates the expense for you.'),
      _AICapability(Icons.email_outlined, 'Email Parsing',
          'AI reads bank emails and extracts merchant, amount, date, card, UPI — automatically.'),
      _AICapability(Icons.show_chart, 'Forecasting',
          'AI predicts next month\'s expenses based on your spending trends and budget patterns.'),
    ];

    return Container(
      width: double.infinity,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.2),
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
          Text(
            'Built with OpenAI, Gemini, and Claude — choose your provider',
            style: TextStyle(fontSize: 15, color: Colors.grey[400]),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: capabilities
                .map((c) => _aiCard(c, isMobile))
                .toList(),
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
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.15),
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

  // ── CTA ─────────────────────────────────────────────────────────────────

  Widget _buildCTA(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 64,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text(
                'Start Managing Your\nFamily\'s Finances Today',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Free to use. No credit card required. Set up in under 2 minutes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Create Free Account'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 32,
      ),
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'myParivaar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI-first family finance management\nfor Indian households.',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                // Links
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 12),
                      _footerLink(context, 'Features', '#'),
                      _footerLink(context, 'Pricing', '#'),
                      _footerLink(context, 'Sign In', '/login'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Legal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 12),
                      _footerLink(context, 'Privacy Policy', '/privacy'),
                      _footerLink(context, 'Terms of Service', '/terms'),
                    ],
                  ),
                ),
              ],
            ),
          if (isMobile) ...[
            const Text(
              'myParivaar',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _footerLink(context, 'Privacy', '/privacy'),
                _footerLink(context, 'Terms', '/terms'),
                _footerLink(context, 'Sign In', '/login'),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Divider(color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            '© 2026 myParivaar. All rights reserved.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _footerLink(BuildContext context, String label, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          if (route.startsWith('/')) {
            Navigator.pushNamed(context, route);
          }
        },
        child: Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
      ),
    );
  }
}

// ── Data Models ───────────────────────────────────────────────────────────────

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
  });
}

class _Step {
  final String number;
  final String title;
  final String desc;
  const _Step(this.number, this.title, this.desc);
}

class _AICapability {
  final IconData icon;
  final String title;
  final String desc;
  const _AICapability(this.icon, this.title, this.desc);
}
