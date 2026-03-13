import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../widgets/app_header.dart';
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectEmailAccount(String provider) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to your email account...'),
            ],
          ),
        ),
      );

      final authService = Provider.of<AuthService>(context, listen: false);
      final authUrl = await _emailService.getEmailConnectUrl(
        provider: provider,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show instructions dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Connect ${provider.toUpperCase()} Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To connect your ${provider.toUpperCase()} account:'),
                const SizedBox(height: 8),
                const Text('1. Tap "Open Browser" below'),
                const Text('2. Sign in to your email account'),
                const Text('3. Grant permission to read your emails'),
                const Text('4. Return to the app when done'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.warningLight),
                  ),
                  child: const Row(
                    children: [
                      Icon(AppIcons.info, color: AppColors.warning, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We only read emails to detect transactions. Your emails remain private.',
                          style: TextStyle(fontSize: 12, color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openEmailAuthUrl(authUrl);
                },
                child: const Text('Open Browser'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting email: $e')),
        );
      }
    }
  }

  Future<void> _openEmailAuthUrl(String authUrl) async {
    // Note: In a real app, you'd use url_launcher package to open the URL
    // For MVP, we'll show a dialog with the URL
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open in Browser'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please open this URL in your browser:'),
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
                _loadEmailAccounts(); // Refresh the list
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
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

  Future<void> _syncEmails() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await _emailService.syncEmails(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email sync completed! Processed ${result['total_emails_processed']} emails, '
              'found ${result['total_transactions_found']} potential transactions.'
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing emails: $e')),
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
            const AppHeader(
              title: 'Email Settings',
              avatarIcon: AppIcons.email,
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.error, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error loading email accounts', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEmailAccounts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
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
          Text(
            'Connected Accounts',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ..._emailAccounts.map((account) => _buildEmailAccountItem(account)),
          const SizedBox(height: 24),
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
      ],
    );
  }

  Widget _buildEmailAccountItem(EmailAccount account) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: account.provider == 'gmail' 
                ? AppColors.errorLight
                : AppColors.infoLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            AppIcons.email,
            color: account.provider == 'gmail' 
                ? AppColors.errorDark
                : AppColors.infoDark,
          ),
        ),
        title: Text(account.emailAddress),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.provider.toUpperCase()),
            Text(
              'Connected ${_formatDate(account.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
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