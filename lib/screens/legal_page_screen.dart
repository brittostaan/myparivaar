import 'package:flutter/material.dart';

/// Reusable legal page shell for Privacy Policy and Terms of Service.
class LegalPageScreen extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<_Section> sections;

  const LegalPageScreen({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  factory LegalPageScreen.privacy() {
    return LegalPageScreen(
      title: 'Privacy Policy',
      lastUpdated: 'March 24, 2026',
      sections: _privacySections,
    );
  }

  factory LegalPageScreen.terms() {
    return LegalPageScreen(
      title: 'Terms of Service',
      lastUpdated: 'March 24, 2026',
      sections: _termsSections,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1923) : const Color(0xFFF8FAFC),
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            Navigator.pushReplacementNamed(context, '/login');
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'myParivaar',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A2332),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A2332),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last updated: $lastUpdated',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Sections
                  ...sections.map((section) => _buildSection(section, isDark)),

                  const SizedBox(height: 48),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    '© 2026 myParivaar. All rights reserved.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_Section section, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A2332),
            ),
          ),
          const SizedBox(height: 10),
          ...section.paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                p,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  final String heading;
  final List<String> paragraphs;
  const _Section(this.heading, this.paragraphs);
}

// ─────────────────────────────────────────────────────────────────────────────
// Privacy Policy Content
// ─────────────────────────────────────────────────────────────────────────────

const _privacySections = <_Section>[
  _Section('Introduction', [
    'myParivaar ("we", "our", "us") is an AI-first family finance management application designed for Indian households. This Privacy Policy explains how we collect, use, store, and protect your personal information when you use our web and mobile application.',
    'By using myParivaar, you agree to the collection and use of information in accordance with this policy.',
  ]),
  _Section('Information We Collect', [
    'Account Information: When you sign up, we collect your name, email address, and authentication credentials through Google Sign-In or email/password registration via Firebase Authentication.',
    'Financial Data: You may manually enter expense transactions, budget targets, savings goals, investment records, and upcoming bills. This data is stored securely in your household account.',
    'Email Integration Data: If you connect your Gmail or Outlook account, we access your email inbox in read-only mode to scan for bank transaction notifications. We extract transaction amounts, merchant names, dates, and payment method details. We do not read, store, or process any non-financial emails.',
    'AI Processing Data: When you use AI features (smart categorisation, budget analysis, voice expense entry), the relevant financial text is sent to our AI provider for processing. No personally identifiable information is included in AI requests beyond the transaction description.',
    'Usage Data: We collect basic usage analytics to improve the app, including pages visited and features used. We do not track or sell your browsing behaviour to third parties.',
  ]),
  _Section('How We Use Your Information', [
    'To provide and maintain the myParivaar service, including expense tracking, budgeting, and financial reporting for your household.',
    'To scan connected email accounts for bank transaction notifications and automatically import them as pending transactions for your review and approval.',
    'To power AI features such as automatic expense categorisation, smart budget analysis, and financial anomaly detection.',
    'To send you important service notifications such as bill reminders and budget alerts (with your consent).',
    'To improve and develop new features based on aggregated, anonymised usage patterns.',
  ]),
  _Section('Data Storage and Security', [
    'All data is stored in Supabase-hosted PostgreSQL databases with encryption at rest and in transit (TLS 1.2+). Your financial data is isolated per household using row-level security policies.',
    'OAuth tokens for email integrations (Gmail, Outlook) are stored encrypted and are used solely to access your email inbox for transaction scanning. Refresh tokens are stored securely and access tokens are refreshed automatically.',
    'We do not store your Google or Microsoft passwords. Authentication is handled entirely through OAuth 2.0 with industry-standard security.',
    'Firebase Authentication manages your login sessions with secure, short-lived tokens.',
  ]),
  _Section('Email Integration', [
    'When you connect a Gmail or Outlook account, we request read-only access to your email inbox. We use this access exclusively to scan for bank transaction notification emails from known Indian banks (HDFC, SBI, ICICI, Axis, Kotak, and others).',
    'We process email subjects and body previews to extract financial transaction details. Non-financial emails are skipped and not stored.',
    'Each scanned email is recorded by its message ID to prevent duplicate processing. You can disconnect your email account at any time, which revokes our access.',
  ]),
  _Section('AI Processing', [
    'myParivaar uses third-party AI services (OpenAI, Google Gemini, or Anthropic Claude) for features like expense categorisation and email transaction parsing.',
    'Only the minimum necessary text (transaction descriptions, amounts, merchant names) is sent to AI providers. We do not send your name, email, account numbers, or other personal identifiers.',
    'AI providers process data according to their own privacy policies and do not use your data for model training.',
  ]),
  _Section('Data Sharing', [
    'We do not sell, trade, or rent your personal information to third parties.',
    'We do not share your financial data with advertisers or marketing companies.',
    'We may share data with service providers who assist in operating our application (Supabase for hosting, Firebase for authentication, Vercel for web hosting), subject to their privacy policies and data processing agreements.',
    'We may disclose information if required by law or to protect the rights and safety of our users.',
  ]),
  _Section('Your Rights', [
    'Access: You can view all your data within the app at any time.',
    'Correction: You can edit or update your financial records, profile information, and household details.',
    'Deletion: You can delete individual transactions, disconnect email accounts, or request complete account deletion by contacting us.',
    'Data Portability: Your transaction data can be exported from the app.',
    'Revocation: You can revoke email access at any time by disconnecting your email account from the Email Settings page.',
  ]),
  _Section('Children\'s Privacy', [
    'myParivaar includes a Kids Dashboard feature designed for financial education. Children\'s accounts are managed by parent users within the household and do not collect any additional personal information beyond what parents provide.',
    'We do not knowingly collect personal information from children under 13 without parental consent.',
  ]),
  _Section('Changes to This Policy', [
    'We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date.',
    'Your continued use of myParivaar after any changes constitutes acceptance of the updated policy.',
  ]),
  _Section('Contact Us', [
    'If you have any questions about this Privacy Policy, please contact us at support@myparivaar.ai.',
  ]),
];

// ─────────────────────────────────────────────────────────────────────────────
// Terms of Service Content
// ─────────────────────────────────────────────────────────────────────────────

const _termsSections = <_Section>[
  _Section('Introduction', [
    'Welcome to myParivaar. These Terms of Service ("Terms") govern your use of the myParivaar web and mobile application ("Service"), operated by myParivaar ("we", "our", "us").',
    'By accessing or using myParivaar, you agree to be bound by these Terms. If you do not agree to these Terms, please do not use the Service.',
  ]),
  _Section('Service Description', [
    'myParivaar is an AI-powered family finance management application designed for Indian households. The Service enables household members to track expenses, manage budgets, set savings goals, monitor investments, and receive AI-powered financial insights.',
    'The Service includes email integration features that allow you to connect Gmail or Outlook accounts to automatically import bank transaction notifications.',
  ]),
  _Section('Account Registration', [
    'You must create an account to use myParivaar. You can register using Google Sign-In or email/password authentication.',
    'You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account.',
    'You must provide accurate and complete information during registration. You agree to update your information to keep it current.',
    'You must be at least 18 years old to create an account. Minors may use the Service through a parent-managed household account.',
  ]),
  _Section('Household Accounts', [
    'myParivaar operates on a household model. One user creates a household and can invite other family members to join.',
    'The household creator (admin) has additional privileges including managing members, configuring email integrations, and accessing admin features.',
    'All financial data within a household is shared among its members. You are responsible for managing access to your household appropriately.',
  ]),
  _Section('Email Integration', [
    'By connecting your email account, you grant myParivaar read-only access to your email inbox for the purpose of scanning bank transaction notifications.',
    'You understand that myParivaar will process email subjects and body content to identify and extract financial transactions. Non-financial emails are not stored.',
    'Email-imported transactions are created in "pending" status and require your explicit approval before being included in your financial records.',
    'You can disconnect your email account at any time, which immediately revokes our access to your inbox.',
  ]),
  _Section('AI Features', [
    'myParivaar uses artificial intelligence for features including automatic expense categorisation, budget analysis, financial anomaly detection, and email transaction parsing.',
    'AI-generated results are provided as suggestions and may not always be accurate. You are responsible for reviewing and approving AI-generated categorisations and transaction details.',
    'AI features require sending limited transaction data to third-party AI service providers. By using these features, you consent to this processing.',
  ]),
  _Section('Acceptable Use', [
    'You agree to use myParivaar only for lawful purposes and in accordance with these Terms. You agree not to:',
    '• Use the Service for any illegal or unauthorised purpose.',
    '• Attempt to gain unauthorised access to other users\' accounts or household data.',
    '• Upload malicious content, viruses, or harmful code.',
    '• Use the Service to store or process data unrelated to family finance management.',
    '• Reverse engineer, decompile, or attempt to extract the source code of the Service.',
    '• Use automated tools to scrape, crawl, or collect data from the Service.',
  ]),
  _Section('Financial Disclaimer', [
    'myParivaar is a financial tracking and budgeting tool. It does not provide financial advice, investment recommendations, or tax guidance.',
    'The AI-powered insights and analyses are for informational purposes only and should not be relied upon as professional financial advice.',
    'You are solely responsible for your financial decisions. We recommend consulting qualified financial professionals for personalised advice.',
    'We do not guarantee the accuracy of automatically imported email transactions. You are responsible for reviewing and approving all imported data.',
  ]),
  _Section('Data Ownership', [
    'You retain ownership of all financial data you enter into myParivaar.',
    'By using the Service, you grant us a limited licence to process, store, and display your data solely for the purpose of providing the Service.',
    'You can export your data or request deletion at any time.',
  ]),
  _Section('Service Availability', [
    'We strive to maintain high availability but do not guarantee uninterrupted access to the Service.',
    'We may perform maintenance, updates, or modifications to the Service that may result in temporary unavailability.',
    'We reserve the right to modify, suspend, or discontinue any feature of the Service with reasonable notice.',
  ]),
  _Section('Limitation of Liability', [
    'To the maximum extent permitted by law, myParivaar shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the Service.',
    'Our total liability for any claims arising from your use of the Service shall not exceed the amount you have paid us in the 12 months preceding the claim, or INR 1,000, whichever is greater.',
    'We are not liable for any loss or damage arising from unauthorised access to your account due to your failure to maintain the security of your credentials.',
  ]),
  _Section('Termination', [
    'You may stop using the Service and close your account at any time.',
    'We reserve the right to suspend or terminate your account if you violate these Terms or engage in activity that could harm the Service or other users.',
    'Upon termination, your right to use the Service ceases immediately. We may retain your data for a reasonable period to comply with legal obligations.',
  ]),
  _Section('Changes to Terms', [
    'We may update these Terms from time to time. We will notify you of significant changes by posting the updated Terms and changing the "Last updated" date.',
    'Your continued use of the Service after changes constitutes acceptance of the updated Terms.',
  ]),
  _Section('Governing Law', [
    'These Terms are governed by the laws of India. Any disputes arising from these Terms or your use of the Service shall be subject to the exclusive jurisdiction of the courts in India.',
  ]),
  _Section('Contact Us', [
    'If you have any questions about these Terms, please contact us at support@myparivaar.ai.',
  ]),
];
