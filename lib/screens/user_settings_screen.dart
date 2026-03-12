import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    // In a real app, these would be loaded from SharedPreferences or user profile
    // For MVP, using default values
  }

  Future<void> _saveSettings() async {
    // In a real app, these would be saved to SharedPreferences and/or backend
    // For MVP, showing a confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: Colors.green,
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // In a real app, would call delete account API
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deletion feature coming soon!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: ListView(
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
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: const Text('Household'),
                    subtitle: Text(authService.currentHousehold?.name ?? 'Not in household'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.of(context).pushNamed('/family');
                    },
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
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email Settings'),
                    subtitle: const Text('Connect email accounts for expense tracking'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    leading: const Icon(Icons.download),
                    title: const Text('Export Data'),
                    subtitle: const Text('Download your family data'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _exportData,
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.open_in_new, size: 16),
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
                    leading: const Icon(Icons.description),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.open_in_new, size: 16),
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

          // Danger Zone Section
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danger Zone',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
                    title: Text(
                      'Delete Account',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    subtitle: const Text('Permanently delete your account and data'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
    );
  }
}