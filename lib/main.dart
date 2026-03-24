import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/csv_import_screen.dart';
import 'screens/savings_goals_screen.dart';
import 'screens/family_management_screen.dart';
import 'screens/expense_management_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/investments_screen.dart';
import 'screens/upcoming_bills_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/family_planner_screen.dart';
import 'screens/kids_dashboard_screen.dart';
import 'screens/parents_dashboard_screen.dart';
import 'screens/ai_features_screen.dart';
import 'screens/email_settings_screen.dart';
import 'screens/user_settings_screen.dart';
import 'screens/admin_settings_screen.dart';
import 'screens/admin_center_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/more_screen.dart';
import 'screens/voice_expense_screen.dart';
import 'screens/anomaly_detection_screen.dart';
import 'screens/financial_simulator_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/legal_page_screen.dart';
import 'services/admin_service.dart';
import 'services/auth_service.dart';
import 'services/family_service.dart';
import 'services/import_service.dart';
import 'widgets/navigation_shell.dart';
import 'widgets/global_header_actions.dart';
import 'theme/app_theme.dart';
import 'theme/app_icons.dart';

const _kDefaultSupabaseUrl = 'https://qimqakfjryptyhxmrjsj.supabase.co';
const _kDefaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpbXFha2ZqcnlwdHloeG1yanNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4NDQ3NzQsImV4cCI6MjA4ODQyMDc3NH0.SIySX0aILaLTp08K-TurhhS4dMWl0VqKzgKp3PPFlM0';

const _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: _kDefaultSupabaseUrl,
);
const _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: _kDefaultSupabaseAnonKey,
);
const _kAppEnv = String.fromEnvironment('APP_ENV', defaultValue: '');

bool get _isDevEnvironment =>
    kDebugMode || _kAppEnv.toLowerCase().trim() == 'dev';

const Set<String> _authenticatedRoutes = {
  '/home',
  '/expenses',
  '/budget',
  '/investments',
  '/bills',
  '/reports',
  '/family-planner',
  '/kids-dashboard',
  '/parents-dashboard',
  '/ai',
  '/email-settings',
  '/user-settings',
  '/admin-settings',
  '/admin-center',
  '/more',
  '/notifications',
  '/savings',
  '/voice-expense',
  '/profile',
  '/family',
  '/csv-import',
};

const Set<String> _publicRoutes = {
  '/privacy',
  '/terms',
  '/login',
};

String _routeFromEndpoint() {
  final uri = Uri.base;
  final path = uri.path.isEmpty ? '/' : uri.path;
  String candidate = path;

  if ((candidate == '/' || candidate.isEmpty) && uri.fragment.startsWith('/')) {
    candidate = '/${uri.fragment.substring(1).split('?').first}';
  }

  if (candidate.length > 1 && candidate.endsWith('/')) {
    candidate = candidate.substring(0, candidate.length - 1);
  }

  if (_authenticatedRoutes.contains(candidate) || _publicRoutes.contains(candidate)) {
    return candidate;
  }
  return '/home';
}

// ── View Mode (Responsive Design) ────────────────────────────────────────────

enum ViewMode {
  desktop(label: 'Browser Mode', icon: AppIcons.laptop, width: null),
  tablet(label: 'Tablet', icon: AppIcons.tablet, width: 768),
  mobile(label: 'Mobile', icon: AppIcons.phone, width: 375);

  const ViewMode({
    required this.label,
    required this.icon,
    required this.width,
  });

  final String label;
  final IconData icon;
  final double? width;
}

ViewMode viewModeFromWidth(double width) {
  if (width >= 1024) {
    return ViewMode.desktop;
  }
  if (width >= 700) {
    return ViewMode.tablet;
  }
  return ViewMode.mobile;
}

class ViewModeProvider extends ChangeNotifier {
  ViewMode _mode = ViewMode.mobile;
  bool _isManualOverride = false;

  ViewMode get mode => _mode;
  bool get isManualOverride => _isManualOverride;

  void setMode(ViewMode mode) {
    _isManualOverride = true;
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void syncAutoMode(ViewMode mode) {
    if (_isManualOverride || _mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void clearManualOverride() {
    if (!_isManualOverride) return;
    _isManualOverride = false;
    notifyListeners();
  }
}

// ── Entry point ──────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate config before initialising Supabase. On failure, show a
  // human-readable error screen instead of crashing before runApp().
  String? configError;
  try {
    _validateSupabaseConfig();
  } catch (e) {
    configError = e.toString();
  }

  if (configError != null) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              configError,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          ),
        ),
      ),
    ));
    return;
  }

  await Supabase.initialize(
    url: _kSupabaseUrl,
    anonKey: _kSupabaseAnonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthService(supabaseUrl: _kSupabaseUrl)),
        ChangeNotifierProvider(
          create: (context) => AdminService(
            supabaseUrl: _kSupabaseUrl,
            supabaseAnonKey: _kSupabaseAnonKey,
            authService: context.read<AuthService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ViewModeProvider()),
      ],
      child: const MyParivaaarApp(),
    ),
  );
}

void _validateSupabaseConfig() {
  final hasValidUrl = _kSupabaseUrl.startsWith('https://') &&
      _kSupabaseUrl.contains('.supabase.co');
  final hasAnonKey = _kSupabaseAnonKey.trim().isNotEmpty &&
      _kSupabaseAnonKey.split('.').length == 3;

  if (!hasValidUrl || !hasAnonKey) {
    throw StateError(
      'Invalid Supabase configuration. Provide valid values via --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
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
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: ThemeMode.light, // Force light mode
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
    final routeName = settings.name ?? '';

    switch (settings.name) {
      case '/login':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _LoginScreen(),
        );

      case '/home':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const _HomeShell(),
          ),
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
        if (!kIsWeb) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Import'),
                actions: const [
                  GlobalHeaderActions(showLogout: true),
                  SizedBox(width: 8),
                ],
              ),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Spreadsheet import is available only in web advanced settings.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            final auth = Provider.of<AuthService>(ctx, listen: false);
            return NavigationShell(
              currentRoute: routeName,
              child: CsvImportScreen(
                importService: ImportService(
                  supabaseUrl: _kSupabaseUrl,
                  authService: auth,
                ),
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
              Future.microtask(
                  () { if (ctx.mounted) Navigator.of(ctx).pushReplacementNamed('/login'); });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return NavigationShell(
              currentRoute: routeName,
              child: FamilyManagementScreen(
                familyService: FamilyService(
                  supabaseUrl: _kSupabaseUrl,
                  authService: auth,
                ),
                currentUser: currentUser,
                householdName:
                    auth.currentHousehold?.name ?? 'Unknown Household',
              ),
            );
          },
        );

      case '/expenses':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const ExpenseManagementScreen(),
          ),
        );

      case '/budget':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const BudgetScreen(),
          ),
        );

      case '/investments':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const InvestmentsScreen(),
          ),
        );

      case '/bills':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const UpcomingBillsScreen(),
          ),
        );

      case '/reports':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const ReportsScreen(),
          ),
        );

      case '/family-planner':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const FamilyPlannerScreen(),
          ),
        );

      case '/kids-dashboard':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const KidsDashboardScreen(),
          ),
        );

      case '/parents-dashboard':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const ParentsDashboardScreen(),
          ),
        );

      case '/ai':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const AIFeaturesScreen(),
          ),
        );

      case '/email-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const EmailSettingsScreen(),
          ),
        );

      case '/user-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const UserSettingsScreen(),
          ),
        );

      case '/admin-settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const AdminSettingsScreen(),
          ),
        );

      case '/admin-center':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminCenterScreen(),
        );

      case '/more':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const MoreScreen(),
        );

      case '/notifications':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const NotificationsScreen(),
          ),
        );

      case '/savings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const SavingsGoalsScreen(),
          ),
        );

      case '/voice-expense':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const VoiceExpenseScreen(),
          ),
        );

      case '/anomaly-detection':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const AnomalyDetectionScreen(),
          ),
        );

      case '/financial-simulator':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => NavigationShell(
            currentRoute: routeName,
            child: const FinancialSimulatorScreen(),
          ),
        );

      case '/profile':
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) {
            return NavigationShell(
              currentRoute: routeName,
              child: const ProfileScreen(),
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(-1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );

      case '/privacy':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => LegalPageScreen.privacy(),
        );

      case '/terms':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => LegalPageScreen.terms(),
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
    // Check for public routes first — no auth needed
    final targetRoute = _routeFromEndpoint();
    if (_publicRoutes.contains(targetRoute)) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(targetRoute);
      return;
    }

    final auth = context.read<AuthService>();
    AuthStatus? status;
    try {
      status = await auth.refreshSession();
    } catch (e) {
      debugPrint('_restoreSession error: $e');
      status = null;
    }
    if (!mounted) return;

    switch (status) {
      case AuthStatus.ready:
        Navigator.of(context).pushReplacementNamed(_routeFromEndpoint());
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
/// Uses the new DashboardScreen for a modern UI.
class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    return const DashboardScreen();
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String? _error;
  bool _isBusy = false;
  bool _isSignUp = false; // Toggle between sign in and sign up
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Sign In ────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
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
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Sign Up ────────────────────────────────────────────────────────────────

  Future<void> _signUp() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
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
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _navigateByStatus(AuthStatus status) {
    if (status == AuthStatus.ready) {
      final authService = context.read<AuthService>();
      // Admin-only users (no household) always land on admin center
      if (authService.currentUser?.isPlatformAdmin == true &&
          !authService.hasHousehold) {
        Navigator.of(context).pushReplacementNamed('/admin-center');
        return;
      }
      Navigator.of(context).pushReplacementNamed(_routeFromEndpoint());
    } else {
      Navigator.of(context).pushReplacementNamed('/household-setup');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showDevLabel = _isDevEnvironment;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background decoration blobs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Main content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showDevLabel)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'DEV',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    // ── Logo Section ──────────────────────────────────────
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.pie_chart,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'myparivaar',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your personal finance, simplified.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // ── Login Card ────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Card body
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _isSignUp
                                      ? 'Create Account'
                                      : 'Welcome Back',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isSignUp
                                      ? 'Fill in your details to get started.'
                                      : 'Please enter your details to sign in.',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                                const SizedBox(height: 28),
                                // Email field
                                const Text(
                                  'Email Address',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: !_isBusy,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    hintText: 'name@example.com',
                                    prefixIcon: Icon(Icons.mail_outlined,
                                        color: Colors.grey[400]),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: primary, width: 2),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Password label row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Password',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                    if (!_isSignUp)
                                      Tooltip(
                                        message: 'Feature coming soon',
                                        child: Row(
                                          children: [
                                            Text(
                                              'Forgot Password?',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: primary,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.close,
                                                size: 12, color: Colors.red),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePassword,
                                  enabled: !_isBusy,
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    prefixIcon: Icon(Icons.lock_outlined,
                                        color: Colors.grey[400]),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: Colors.grey[400],
                                      ),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: primary, width: 2),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                  ),
                                  onSubmitted: (_) =>
                                      _isSignUp ? _signUp() : _signIn(),
                                ),
                                const SizedBox(height: 16),
                                // Remember me (UI only)
                                if (!_isSignUp)
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (val) => setState(
                                              () =>
                                                  _rememberMe = val ?? false),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          activeColor: primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Remember me for 30 days',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 24),
                                // Sign In / Sign Up button
                                SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isBusy
                                        ? null
                                        : (_isSignUp ? _signUp : _signIn),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      elevation: 2,
                                      shadowColor: primary.withOpacity(0.3),
                                    ),
                                    child: _isBusy
                                        ? const _SmallSpinner()
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                _isSignUp
                                                    ? 'Sign Up'
                                                    : 'Sign In',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(Icons.arrow_forward,
                                                  size: 20),
                                            ],
                                          ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: SelectableText(
                                      _error!,
                                      style: TextStyle(
                                        color: theme
                                            .colorScheme.onErrorContainer,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Card footer
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              border: Border(
                                top: BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isSignUp
                                      ? 'Already have an account? '
                                      : "Don't have an account? ",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _isBusy
                                      ? null
                                      : () => setState(() {
                                            _isSignUp = !_isSignUp;
                                            _error = null;
                                          }),
                                  child: Text(
                                    _isSignUp ? 'Sign in' : 'Sign up',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Trust indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined,
                            size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 6),
                        Text(
                          'Bank-level Security',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                        const SizedBox(width: 24),
                        Icon(Icons.lock_outlined,
                            size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 6),
                        Text(
                          '256-bit Encryption',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ViewMode selector – floating top-right corner
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: GlobalHeaderActions(
                showLogout: false,
                iconColor: Colors.grey[500],
              ),
            ),
          ),
        ],
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
  bool _isBusy = false;
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
      _error = null;
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
        setState(() => _error =
            'Joined successfully but could not load household. Please restart the app.');
      }
    } on FamilyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Household'),
        automaticallyImplyLeading: false, // Remove back button
        actions: const [
          GlobalHeaderActions(showLogout: true),
          SizedBox(width: 8),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(AppIcons.home, size: 56),
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
              controller: _codeCtrl,
              enabled: !_isBusy,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                labelText: 'Invite code',
                hintText: 'ABCD1234',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _joinHousehold(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
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
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _isBusy
                  ? const _SmallSpinner()
                  : const Text('Join household'),
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
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
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
    final detectedMode = viewModeFromWidth(MediaQuery.of(context).size.width);
    final modeProvider = context.read<ViewModeProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.read<ViewModeProvider>().syncAutoMode(detectedMode);
    });
    final activeMode = modeProvider.isManualOverride ? viewMode : detectedMode;

    // Desktop mode - full width
    if (activeMode == ViewMode.desktop) {
      return child;
    }

    // Mobile/Tablet modes - constrained width with device frame
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      color: bgColor,
      child: Center(
        child: Container(
          width: activeMode.width,
          decoration: BoxDecoration(
            color: bgColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
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
