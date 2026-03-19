import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:myparivaar/models/admin_models.dart';
import 'package:myparivaar/models/app_user.dart';
import 'package:myparivaar/screens/admin_center_screen.dart';
import 'package:myparivaar/services/admin_service.dart';
import 'package:myparivaar/services/auth_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.signature',
    );
  });

  testWidgets('shows access required state for non-admin user', (tester) async {
    final authService = FakeAuthService(currentUser: _memberUser());
    final adminService = FakeAdminService(authService: authService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<AdminService>.value(value: adminService),
        ],
        child: const MaterialApp(home: AdminCenterScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Admin Access Required'), findsOneWidget);
    expect(find.text('Only super admins and support staff can access this center.'), findsOneWidget);
  });

  testWidgets('shows dashboard for super admin user', (tester) async {
    final authService = FakeAuthService(currentUser: _superAdminUser());
    final adminService = FakeAdminService(
      authService: authService,
      fakeStats: const AdminStats(
        totalHouseholds: 12,
        activeSubscriptions: 8,
        totalUsers: 34,
        aiUsageThisMonth: 144,
        lastAuditAction: null,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<AdminService>.value(value: adminService),
        ],
        child: const MaterialApp(home: AdminCenterScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('Total Households'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}

class FakeAuthService extends AuthService {
  FakeAuthService({required AppUser? currentUser})
      : _currentUser = currentUser,
        super(supabaseUrl: 'https://example.supabase.co');

  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  bool get isLoggedIn => _currentUser != null;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async => 'fake-token';
}

class FakeAdminService extends AdminService {
  FakeAdminService({
    required AuthService authService,
    this.fakeStats,
    this.fakeAuditLogs = const [],
  }) : super(
          supabaseUrl: 'https://example.supabase.co',
          authService: authService,
        );

  final AdminStats? fakeStats;
  final List<AuditLog> fakeAuditLogs;

  @override
  AdminStats? get stats => fakeStats;

  @override
  List<AuditLog> get auditLogs => fakeAuditLogs;

  @override
  bool get isLoading => false;

  @override
  Future<AdminStats?> fetchStats() async => fakeStats;

  @override
  Future<List<AuditLog>> fetchAuditLogs({String? resourceType, String? resourceId, int limit = 50}) async {
    return fakeAuditLogs;
  }
}

AppUser _memberUser() {
  return AppUser(
    id: 'user-1',
    supabaseUserId: 'auth-1',
    email: 'member@example.com',
    role: 'member',
    notificationsEnabled: true,
    voiceEnabled: true,
    createdAt: DateTime(2026, 3, 19),
  );
}

AppUser _superAdminUser() {
  return AppUser(
    id: 'user-2',
    supabaseUserId: 'auth-2',
    email: 'admin@example.com',
    role: 'super_admin',
    staffScope: 'global',
    notificationsEnabled: true,
    voiceEnabled: true,
    createdAt: DateTime(2026, 3, 19),
  );
}