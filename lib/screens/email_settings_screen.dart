import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../services/ai_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final EmailService _emailService = EmailService();
  List<EmailAccount> _emailAccounts = [];
  bool _isLoading = true;
  String? _error;

  // Email parsing
  final _emailBodyController = TextEditingController();
  final _emailSubjectController = TextEditingController();
  bool _isParsing = false;
  List<Map<String, dynamic>>? _parsedTransactions;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _loadEmailAccounts();
  }

  Future<void> _loadEmailAccounts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final accounts = await _emailService.getEmailAccounts(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        setState(() {
          _emailAccounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _emailAccounts = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectEmailAccount(String provider) async {
    // Capture context-dependent objects before any async gap.
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      // Show loading indicator
      setState(() => _isLoading = true);

      final authUrl = await _emailService.getEmailConnectUrl(
        provider: provider,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Open OAuth URL directly in a new browser tab
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
        // Show a snackbar telling user to complete the flow and refresh
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Complete the sign-in in the new tab, then tap Refresh below.'),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'Refresh',
                onPressed: _loadEmailAccounts,
              ),
            ),
          );
        }
      } else {
        // Fallback: show URL in a dialog if launch fails
        if (mounted) {
          _showFallbackUrlDialog(authUrl);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting email: $e')),
        );
      }
    }
  }

  void _showFallbackUrlDialog(String authUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open in Browser'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not open browser automatically. Please copy and open this URL:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                authUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Text('After completing the flow, return to refresh this page.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadEmailAccounts();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _parseEmailContent() async {
    final body = _emailBodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste an email body to parse')),
      );
      return;
    }
    setState(() {
      _isParsing = true;
      _parseError = null;
      _parsedTransactions = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().parseEmail(
        emailBody: body,
        emailSubject: _emailSubjectController.text.trim().isNotEmpty
            ? _emailSubjectController.text.trim()
            : null,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );
      if (!mounted) return;
      setState(() {
        _parsedTransactions = (result['transactions'] as List<dynamic>?)
                ?.map((t) => Map<String, dynamic>.from(t as Map))
                .toList() ??
            [];
        _isParsing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _parseError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _emailBodyController.dispose();
    _emailSubjectController.dispose();
    super.dispose();
  }

  Future<void> _disconnectEmailAccount(EmailAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Email Account'),
        content: Text(
          'Are you sure you want to disconnect ${account.emailAddress}?\n\n'
          'This will stop automatic transaction detection from this email account.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await _emailService.disconnectEmailAccount(
        accountId: account.id,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      _loadEmailAccounts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email account disconnected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error disconnecting account: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: const [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(AppIcons.email, size: 16, color: Color(0xFF0284C7)),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Email Settings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadEmailAccounts,
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

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (_error != null) ...[
          Card(
            color: AppColors.warningLight,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.warning, color: AppColors.warningDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Could not load connected email accounts.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You can still connect a new email account below and retry account sync later.',
                          style: TextStyle(color: AppColors.grey700),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loadEmailAccounts,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Information card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.email, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Automatic Transaction Detection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect your email accounts to automatically detect transactions from:\n'
                  '• Bank debit/credit alerts\n'
                  '• UPI payment receipts\n'
                  '• E-commerce purchase confirmations\n'
                  '• Bill payment confirmations\n\n'
                  'All detected transactions require your approval before being added.',
                  style: TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Connected accounts section
        if (_emailAccounts.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Connected Accounts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadEmailAccounts,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._emailAccounts.map((account) => _buildEmailAccountItem(account)),
          const SizedBox(height: 24),
        ],

        if (_emailAccounts.isEmpty && _error == null) ...[
          Card(
            color: AppColors.grey100,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No email accounts connected yet. Connect one below to start detecting transactions automatically.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Add account section
        Text(
          'Connect Email Account',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(AppIcons.email, color: AppColors.errorDark),
                ),
                title: const Text('Gmail'),
                subtitle: const Text('Connect your Google account'),
                trailing: const Icon(AppIcons.add),
                onTap: () => _connectEmailAccount('gmail'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(AppIcons.email, color: AppColors.infoDark),
                ),
                title: const Text('Outlook'),
                subtitle: const Text('Connect your Microsoft account'),
                trailing: const Icon(AppIcons.add),
                onTap: () => _connectEmailAccount('outlook'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // AI Email Parsing section
        Text(
          'Parse Bank Email',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    const Text(
                      'AI-Powered Email Parser',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste a bank notification email to extract transaction details automatically.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailSubjectController,
                  decoration: const InputDecoration(
                    labelText: 'Email Subject (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailBodyController,
                  decoration: const InputDecoration(
                    labelText: 'Email Body',
                    hintText: 'Paste your bank notification email here...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isParsing ? null : _parseEmailContent,
                    icon: _isParsing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_isParsing ? 'Parsing...' : 'Parse Email'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                if (_parseError != null) ...[
                  const SizedBox(height: 12),
                  Text(_parseError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                if (_parsedTransactions != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Extracted Transactions (${_parsedTransactions!.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (_parsedTransactions!.isEmpty)
                    const Text('No transactions found in this email.', style: TextStyle(color: Colors.grey))
                  else
                    ..._parsedTransactions!.map((t) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.grey100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t['description']?.toString() ?? 'Transaction',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${t['type'] ?? 'debit'} • ${t['category'] ?? 'Other'} • ${t['date'] ?? ''}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${t['amount'] ?? 0}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: (t['type'] ?? 'debit') == 'credit'
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        )),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailAccountItem(EmailAccount account) {
    final isGmail = account.provider == 'gmail';
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isGmail ? AppColors.errorLight : AppColors.infoLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            AppIcons.email,
            color: isGmail ? AppColors.errorDark : AppColors.infoDark,
          ),
        ),
        title: Text(
          account.emailAddress,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGmail ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isGmail ? 'Gmail' : 'Outlook',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isGmail ? AppColors.errorDark : AppColors.infoDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: account.isActive
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        account.isActive ? Icons.check_circle : Icons.warning_amber,
                        size: 12,
                        color: account.isActive
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        account.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: account.isActive
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Connected ${_formatDate(account.createdAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'disconnect') {
              _disconnectEmailAccount(account);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'disconnect',
              child: Row(
                children: [
                  Icon(Icons.link_off, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Disconnect'),
                ],
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}