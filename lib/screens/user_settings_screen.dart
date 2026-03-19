import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/member.dart';
import '../services/auth_service.dart';
import '../services/family_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  bool _notificationsEnabled = true;
  bool _billRemindersEnabled = true;
  bool _expenseNotificationsEnabled = true;
  bool _weeklyReportsEnabled = true;
  String _selectedLanguage = 'English';
  String _selectedCurrency = 'INR (₹)';
  String _selectedTheme = 'System';

  final List<String> _languages = ['English', 'Hindi', 'Tamil', 'Telugu', 'Bengali', 'Marathi'];
  final List<String> _currencies = ['INR (₹)', 'USD (\$)', 'EUR (€)', 'GBP (£)'];
  final List<String> _themes = ['System', 'Light', 'Dark'];

  // Family members state
  List<Member> _familyMembers = [];
  bool _loadingMembers = true;
  bool _invitingMember = false;
  InviteResult? _currentInvite;
  String? _selectedPhoneNumber;

  late FamilyService _familyService;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initializeFamilyService();
    _loadFamilyMembers();
  }

  void _initializeFamilyService() {
    final authService = context.read<AuthService>();
    _familyService = FamilyService(
      supabaseUrl: authService.supabaseUrl,
      authService: authService,
    );
  }

  void _loadSettings() {
    // In a real app, these would be loaded from SharedPreferences or user profile
    // For MVP, using default values
  }

  Future<void> _loadFamilyMembers() async {
    if (!mounted) return;
    setState(() {
      _loadingMembers = true;
    });
    try {
      final members = await _familyService.fetchMembers();
      if (mounted) {
        setState(() {
          _familyMembers = members;
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load family members'),
          ),
        );
      }
    }
  }

  void _showInviteMemberDialog() {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Family Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the phone number of the family member you want to invite:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '+91 98765 43210',
                labelText: 'Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final phoneNumber = phoneController.text.trim();
              if (phoneNumber.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a phone number'),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              await _inviteMember(phoneNumber);
            },
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }

  Future<void> _inviteMember(String phoneNumber) async {
    setState(() {
      _invitingMember = true;
    });
    try {
      final invite = await _familyService.inviteMember(phoneNumber);
      if (mounted) {
        setState(() {
          _currentInvite = invite;
          _invitingMember = false;
        });
        _showInviteCodeDialog(invite);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _invitingMember = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inviting member: $e'),
          ),
        );
      }
    }
  }

  void _showInviteCodeDialog(InviteResult invite) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Code Generated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this code with ${invite.phoneNumber}:',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      invite.inviteCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Copy to clipboard
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite code copied to clipboard'),
                        ),
                      );
                    },
                    icon: const Icon(AppIcons.copy),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Expires at: ${invite.expiresAt.toLocal().toString().split('.')[0]}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey600,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Family Data'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export all your family\'s financial data as a CSV file.'),
            SizedBox(height: 16),
            Text('This includes:'),
            Text('• All expense records'),
            Text('• Monthly summaries'),
            Text('• Budget information'),
            Text('• Family member details'),
            SizedBox(height: 16),
            Text(
              'Note: Exported data will not include passwords or sensitive authentication information.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // In a real app, would call an export API
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data export feature coming soon!'),
                ),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your account?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('This will:'),
            Text('• Remove you from your current household'),
            Text('• Delete all your personal data'),
            Text('• Cannot be undone'),
            SizedBox(height: 16),
            Text(
              'Note: If you are the household admin, you must transfer admin rights to another member first.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      // In a real app, would call delete account API
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deletion feature coming soon!'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    await context.read<AuthService>().signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: const [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // User Profile Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account Information',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if (user != null) ...[
                            ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (user.displayName?.isNotEmpty == true 
                                    ? user.displayName![0] 
                                    : user.email.substring(0, 1))
                                    .toUpperCase(),
                                ),
                              ),
                              title: Text(user.displayName ?? 'User'),
                              subtitle: Text(user.email),
                              trailing: IconButton(
                                onPressed: () {
                                  // In a real app, would show edit profile dialog
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Profile editing coming soon!'),
                                    ),
                                  );
                                },
                                icon: const Icon(AppIcons.edit),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Family Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Family',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (!_loadingMembers)
                                FilledButton.icon(
                                  onPressed: _showInviteMemberDialog,
                                  icon: const Icon(Icons.person_add, size: 18),
                                  label: const Text('Invite Member'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_loadingMembers)
                            const Center(
                              child: SizedBox(
                                height: 40,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else if (_familyMembers.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0),
                                child: Column(
                                  children: [
                                    Icon(
                                      AppIcons.people,
                                      size: 48,
                                      color: AppColors.grey400,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No family members yet',
                                      style: TextStyle(
                                        color: AppColors.grey600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: _showInviteMemberDialog,
                                      icon: const Icon(Icons.person_add, size: 18),
                                      label: const Text('Invite Your First Member'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Column(
                              children: _familyMembers
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final index = entry.key;
                                final member = entry.value;
                                return Column(
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(
                                        child: Text(
                                          (member.displayName?.isNotEmpty == true
                                              ? member.displayName![0]
                                              : member.phone.substring(0, 1))
                                              .toUpperCase(),
                                        ),
                                      ),
                                      title: Text(member.displayLabel),
                                      subtitle: Text(
                                        member.isAdmin ? 'Admin' : 'Member',
                                        style: TextStyle(
                                          color: member.isAdmin
                                              ? Theme.of(context).primaryColor
                                              : AppColors.grey600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (index < _familyMembers.length - 1)
                                      const Divider(height: 1),
                                  ],
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notifications Section
                  Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Enable Notifications'),
                    subtitle: const Text('Receive app notifications'),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                        if (!value) {
                          _billRemindersEnabled = false;
                          _expenseNotificationsEnabled = false;
                          _weeklyReportsEnabled = false;
                        }
                      });
                    },
                  ),
                  if (_notificationsEnabled) ...[
                    SwitchListTile(
                      title: const Text('Bill Reminders'),
                      subtitle: const Text('Reminder for upcoming bills'),
                      value: _billRemindersEnabled,
                      onChanged: (value) {
                        setState(() {
                          _billRemindersEnabled = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Expense Notifications'),
                      subtitle: const Text('Alert for large expenses'),
                      value: _expenseNotificationsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _expenseNotificationsEnabled = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Weekly Reports'),
                      subtitle: const Text('Weekly spending summary'),
                      value: _weeklyReportsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _weeklyReportsEnabled = value;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // App Preferences Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Preferences',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Language'),
                    subtitle: Text(_selectedLanguage),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('Select Language'),
                          children: _languages.map((language) {
                            return SimpleDialogOption(
                              onPressed: () {
                                setState(() {
                                  _selectedLanguage = language;
                                });
                                Navigator.pop(context);
                              },
                              child: Text(language),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    title: const Text('Currency'),
                    subtitle: Text(_selectedCurrency),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('Select Currency'),
                          children: _currencies.map((currency) {
                            return SimpleDialogOption(
                              onPressed: () {
                                setState(() {
                                  _selectedCurrency = currency;
                                });
                                Navigator.pop(context);
                              },
                              child: Text(currency),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    title: const Text('Theme'),
                    subtitle: Text(_selectedTheme),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('Select Theme'),
                          children: _themes.map((theme) {
                            return SimpleDialogOption(
                              onPressed: () {
                                setState(() {
                                  _selectedTheme = theme;
                                });
                                Navigator.pop(context);
                              },
                              child: Text(theme),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Integrations Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integrations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(AppIcons.email),
                    title: const Text('Email Settings'),
                    subtitle: const Text('Connect email accounts for expense tracking'),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: () => Navigator.of(context).pushNamed('/email-settings'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Data & Privacy Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data & Privacy',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(AppIcons.download),
                    title: const Text('Export Data'),
                    subtitle: const Text('Download your family data'),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: _exportData,
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.privacyTip),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(AppIcons.openInNew, size: 16),
                    onTap: () {
                      // In a real app, would open privacy policy
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Privacy policy coming soon!'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.document),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(AppIcons.openInNew, size: 16),
                    onTap: () {
                      // In a real app, would open terms of service
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Terms of service coming soon!'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                subtitle: const Text('Sign out from your account'),
                trailing: const Icon(AppIcons.arrowForward, size: 16),
                onTap: _logout,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Danger Zone Section
          Card(
            color: AppColors.errorLight,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danger Zone',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.errorDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(AppIcons.deleteForever, color: AppColors.errorDark),
                    title: const Text(
                      'Delete My Account',
                      style: TextStyle(color: AppColors.errorDark),
                    ),
                    subtitle: const Text('Permanently delete your account and data'),
                    trailing: const Icon(AppIcons.arrowForward, size: 16),
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // App Info
          Center(
            child: Column(
              children: [
                Text(
                  'myParivaar v1.0.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Made with ❤️ for Indian families',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
            ),
          ],
        ),
      ),
    );
  }
}