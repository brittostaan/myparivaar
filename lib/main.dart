import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/csv_import_screen.dart';
import 'screens/family_management_screen.dart';
import 'screens/expense_management_screen.dart';
import 'screens/ai_features_screen.dart';
import 'screens/email_settings_screen.dart';
import 'screens/voice_expense_screen.dart';
import 'screens/user_settings_screen.dart';
import 'screens/admin_settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/auth_service.dart';
import 'services/family_service.dart';
import 'services/import_service.dart';

const _kSupabaseUrl = 'https://qimqakfjryptyhxmrjsj.supabase.co';
const _kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpbXFha2ZqcnlwdHloeG1yanNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NDQ3NzQsImV4cCI6MjA4ODQyMDc3NH0.SIySX0aILaLTp08K-TurhhS4dMWl0VqKzgKp3PPFlM0';

// ── View Mode (Responsive Design) ────────────────────────────────────────────

enum ViewMode {
  desktop(label: 'Browser Mode', icon: Icons.laptop, width: null),
  tablet(label: 'Tablet', icon: Icons.tablet_mac, width: 768),
  mobile(label: 'Mobile', icon: Icons.phone_iphone, width: 375);

  const ViewMode({
    required this.label,
    required this.icon,
    required this.width,
  });

  final String label;
  final IconData icon;
  final double? width;
}

class ViewModeProvider extends ChangeNotifier {
  ViewMode _mode = ViewMode.desktop;

  ViewMode get mode => _mode;

  void setMode(ViewMode mode) {
    _mode = mode;
    notifyListeners();
  }
}

// ── Entry point ──────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: _kSupabaseUrl,
    anonKey: _kSupabaseAnonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService(supabaseUrl: _kSupabaseUrl)),
        ChangeNotifierProvider(create: (_) => ViewModeProvider()),
      ],
      child: const MyParivaaarApp(),
    ),
  );
}

// ── Root widget ──────────────────────────────────────────────────────────────

class MyParivaaarApp extends StatelessWidget {
  const MyParivaaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ViewModeProvider>(
      builder: (context, viewModeProvider, child) {
        return MaterialApp(
          title: 'myParivaar',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.deepOrange,
            useMaterial3: true,
          ),
          builder: (context, child) {
            return _ResponsiveWrapper(
              viewMode: viewModeProvider.mode,
              child: child!,
            );
          },
          home: const _AppRouter(),
          onGenerateRoute: _onGenerateRoute,
        );
      },
    );
  }

  /// Named-route factory. Services are instantiated here so screens stay
  /// free of hardcoded dependencies, and the Provider/AuthService context
  /// is available for guarded screens (e.g. FamilyManagementScreen).
  static Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/login':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _LoginScreen(),
        );

      case '/home':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _HomeShell(),
        );

      case '/household-setup':
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            final auth = Provider.of<AuthService>(ctx, listen: false);
            return _NeedsHouseholdScreen(
              familyService: FamilyService(
                supabaseUrl: _kSupabaseUrl,
                authService: auth,
              ),
            );
          },
        );

      case '/csv-import':
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            final auth = Provider.of<AuthService>(ctx, listen: false);
            return CsvImportScreen(
              importService: ImportService(
                supabaseUrl: _kSupabaseUrl,
                authService: auth,
              ),
            );
          },
        );

      case '/family':
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            final auth = Provider.of<AuthService>(ctx, listen: false);
            final currentUser = auth.currentUser;
            if (currentUser == null) {
              // Redirect to login if not authenticated
              Future.microtask(() => Navigator.of(ctx).pushReplacementNamed('/login'));
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return FamilyManagementScreen(
              familyService: FamilyService(
                supabaseUrl: _kSupabaseUrl,
                authService: auth,
              ),
              currentUser: currentUser,
              householdName: auth.currentHousehold?.name ?? 'Unknown Household',
            );
          },
        );

      case '/expenses':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ExpenseManagementScreen(),
        );

      case '/ai':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AIFeaturesScreen(),
        );

      case '/email-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const EmailSettingsScreen(),
        );

      case '/voice-expense':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const VoiceExpenseScreen(),
        );

      case '/user-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const UserSettingsScreen(),
        );

      case '/admin-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminSettingsScreen(),
        );

      case '/notifications':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const NotificationsScreen(),
        );

      default:
        return MaterialPageRoute(builder: (_) => const _AppRouter());
    }
  }
}

// ── App Router (splash + auth guard) ────────────────────────────────────────

/// Shown while the app checks for an existing Supabase session.
/// Redirects to [_HomeShell] if ready, [_LoginScreen] if not authenticated.
class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  @override
  void initState() {
    super.initState();
    // Defer until the widget tree is fully built so Provider is accessible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    final auth = context.read<AuthService>();
    final status = await auth.refreshSession();
    if (!mounted) return;

    switch (status) {
      case AuthStatus.ready:
        Navigator.of(context).pushReplacementNamed('/home');
      case AuthStatus.needsHousehold:
        Navigator.of(context).pushReplacementNamed('/household-setup');
      case null:
        Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Home Shell ───────────────────────────────────────────────────────────────

/// Main screen shown to authenticated users with a household.
/// Provides navigation to all top-level features.
class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final household = auth.currentHousehold;

    return Scaffold(
      appBar: AppBar(
        title: Text(household?.name ?? 'myParivaar (Dev Mode)'),
        actions: [
          const _ViewModeSelector(),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).pushNamed('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                'Welcome, ${user?.displayName ?? user?.phone ?? 'Developer'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('CSV Import'),
              onPressed: () => Navigator.of(context).pushNamed('/csv-import'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Manage Expenses'),
              onPressed: () => Navigator.of(context).pushNamed('/expenses'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.mic),
              label: const Text('Voice Expense Entry'),
              onPressed: () => Navigator.of(context).pushNamed('/voice-expense'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI Insights'),
              onPressed: () => Navigator.of(context).pushNamed('/ai'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.email),
              label: const Text('Email Settings'),
              onPressed: () => Navigator.of(context).pushNamed('/email-settings'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.people),
              label: const Text('Family Management'),
              onPressed: () => Navigator.of(context).pushNamed('/family'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.settings),
              label: const Text('Settings'),
              onPressed: () => Navigator.of(context).pushNamed('/user-settings'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.notifications),
              label: const Text('Notifications'),
              onPressed: () => Navigator.of(context).pushNamed('/notifications'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Admin Settings'),
              onPressed: () => Navigator.of(context).pushNamed('/admin-settings'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Login Screen ─────────────────────────────────────────────────────────────

/// Email/Password login backed by [AuthService].
/// Supports both sign in and sign up flows.
class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  
  String? _error;
  bool    _isBusy = false;
  bool    _isSignUp = false;  // Toggle between sign in and sign up

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Sign In ────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error  = null;
    });

    try {
      final status = await context.read<AuthService>().signInWithEmail(
        email: email,
        password: password,
      );
      if (mounted) _navigateByStatus(status);
    } on AppAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Sign Up ────────────────────────────────────────────────────────────────

  Future<void> _signUp() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error  = null;
    });

    try {
      final status = await context.read<AuthService>().signUpWithEmail(
        email: email,
        password: password,
      );
      if (mounted) _navigateByStatus(status);
    } on AppAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _navigateByStatus(AuthStatus status) {
    final route = status == AuthStatus.ready ? '/home' : '/household-setup';
    Navigator.of(context).pushReplacementNamed(route);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Create Account' : 'Sign in')),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isSignUp
                  ? 'Create a new account to get started'
                  : 'Sign in to your account',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),

            TextField(
              controller:   _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              enabled:      !_isBusy,
              autocorrect:  false,
              decoration: const InputDecoration(
                labelText:   'Email',
                hintText:    'your.email@example.com',
                prefixIcon:  Icon(Icons.email),
                border:      OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller:   _passwordCtrl,
              obscureText:  true,
              enabled:      !_isBusy,
              decoration: const InputDecoration(
                labelText:   'Password',
                hintText:    'Min. 6 characters',
                prefixIcon:  Icon(Icons.lock),
                border:      OutlineInputBorder(),
              ),
              onSubmitted: (_) => _isSignUp ? _signUp() : _signIn(),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isBusy ? null : (_isSignUp ? _signUp : _signIn),
              child: _isBusy
                  ? const _SmallSpinner()
                  : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
            ),
            
            const SizedBox(height: 16),
            
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () => setState(() {
                        _isSignUp = !_isSignUp;
                        _error = null;
                      }),
              child: Text(
                _isSignUp
                    ? 'Already have an account? Sign in'
                    : 'Don\'t have an account? Sign up',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Needs Household Screen ────────────────────────────────────────────────────

/// Shown when the user is authenticated but not yet part of a household.
/// Lets them enter an invite code (shared by the admin out-of-band) to join.
class _NeedsHouseholdScreen extends StatefulWidget {
  const _NeedsHouseholdScreen({required this.familyService});

  final FamilyService familyService;

  @override
  State<_NeedsHouseholdScreen> createState() => _NeedsHouseholdScreenState();
}

class _NeedsHouseholdScreenState extends State<_NeedsHouseholdScreen> {
  final _codeCtrl = TextEditingController();
  bool    _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinHousehold() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter an invite code.');
      return;
    }
    if (code.length != 8) {
      setState(() => _error = 'Invite codes are 8 characters long.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error  = null;
    });

    try {
      await widget.familyService.joinHousehold(code);

      if (!mounted) return;
      // Re-bootstrap to pull the updated household into AuthService state.
      final status = await context.read<AuthService>().refreshSession();
      if (!mounted) return;

      if (status == AuthStatus.ready) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        // Unexpected: bootstrap still shows no household.
        setState(() => _error = 'Joined successfully but could not load household. Please restart the app.');
      }
    } on FamilyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Join Household')),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.home_outlined, size: 56),
            const SizedBox(height: 24),
            Text(
              'Enter your invite code',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask your household admin for the 8-character invite code.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller:      _codeCtrl,
              enabled:         !_isBusy,
              textCapitalization: TextCapitalization.characters,
              maxLength:       8,
              textAlign:       TextAlign.center,
              style:           const TextStyle(
                fontSize:      28,
                fontWeight:    FontWeight.w700,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                labelText:  'Invite code',
                hintText:   'ABCD1234',
                border:     OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _joinHousehold(),
            ),
            if (_error != null) ...[  
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:        cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isBusy ? null : _joinHousehold,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _isBusy
                  ? const _SmallSpinner()
                  : const Text('Join household'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () async {
                      await context.read<AuthService>().signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width:  20,
      child:  CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

// ── Responsive Wrapper ─────────────────────────────────────────────────────────

class _ResponsiveWrapper extends StatelessWidget {
  const _ResponsiveWrapper({
    required this.viewMode,
    required this.child,
  });

  final ViewMode viewMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Desktop mode - full width
    if (viewMode == ViewMode.desktop) {
      return child;
    }

    // Mobile/Tablet modes - constrained width with device frame
    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Container(
          width: viewMode.width,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRect(
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── View Mode Selector ─────────────────────────────────────────────────────────

class _ViewModeSelector extends StatelessWidget {
  const _ViewModeSelector();

  @override
  Widget build(BuildContext context) {
    final viewModeProvider = context.watch<ViewModeProvider>();
    final currentMode = viewModeProvider.mode;

    return PopupMenuButton<ViewMode>(
      tooltip: 'View Mode',
      icon: Icon(currentMode.icon),
      onSelected: (mode) => viewModeProvider.setMode(mode),
      itemBuilder: (context) => ViewMode.values.map((mode) {
        return PopupMenuItem<ViewMode>(
          value: mode,
          child: Row(
            children: [
              Icon(
                mode.icon,
                color: mode == currentMode 
                    ? Theme.of(context).primaryColor 
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                mode.label,
                style: TextStyle(
                  fontWeight: mode == currentMode 
                      ? FontWeight.bold 
                      : FontWeight.normal,
                  color: mode == currentMode 
                      ? Theme.of(context).primaryColor 
                      : null,
                ),
              ),
              if (mode == currentMode) ...[
                const Spacer(),
                Icon(
                  Icons.check,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

