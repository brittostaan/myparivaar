import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:myparivaar/models/admin_permissions.dart';
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
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  testWidgets('super admin sees privileged navigation items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authService = FakeAuthService(currentUser: _superAdminUser());
    final adminService = FakeAdminService(
      authService: authService,
      fakeStats: const AdminStats(
        totalHouseholds: 10,
        activeSubscriptions: 5,
        totalUsers: 20,
        aiUsageThisMonth: 11,
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

    expect(find.text('Households'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Features'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Audit Logs'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
  });

  testWidgets('support staff default permissions hide staff and features nav', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authService = FakeAuthService(currentUser: _supportStaffUser());
    final adminService = FakeAdminService(
      authService: authService,
      fakeStats: const AdminStats(
        totalHouseholds: 4,
        activeSubscriptions: 3,
        totalUsers: 9,
        aiUsageThisMonth: 2,
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

    expect(find.text('Households'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Audit Logs'), findsOneWidget);

    expect(find.text('Features'), findsNothing);
    expect(find.text('Staff'), findsNothing);
  });

  testWidgets('support staff explicit permission set controls nav visibility', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authService = FakeAuthService(
      currentUser: _supportStaffUser(adminPermissions: {
        AdminPermissions.viewDashboard: true,
        AdminPermissions.viewAuditLogs: true,
        AdminPermissions.viewHouseholds: false,
        AdminPermissions.viewUsers: false,
        AdminPermissions.viewAnalytics: false,
      }),
    );
    final adminService = FakeAdminService(
      authService: authService,
      fakeStats: const AdminStats(
        totalHouseholds: 1,
        activeSubscriptions: 1,
        totalUsers: 2,
        aiUsageThisMonth: 0,
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

    expect(find.text('Audit Logs'), findsOneWidget);
    expect(find.text('Households'), findsNothing);
    expect(find.text('Users'), findsNothing);
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Features'), findsNothing);
    expect(find.text('Staff'), findsNothing);
  });

  testWidgets('support staff without manageHouseholds cannot see household action buttons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final household = AdminHouseholdSummary(
      id: 'hh-1',
      name: 'Devi Family',
      plan: 'free',
      suspended: false,
      memberCount: 3,
      activeMemberCount: 3,
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 10),
    );

    final householdDetail = AdminHouseholdDetail(
      id: 'hh-1',
      name: 'Devi Family',
      plan: 'free',
      suspended: false,
      suspensionReason: null,
      adminNotes: 'Read-only notes',
      memberCount: 3,
      activeMemberCount: 3,
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 10),
      members: [
        AdminHouseholdMember(
          id: 'u1',
          displayName: 'Devi',
          email: 'devi@example.com',
          role: 'admin',
          isActive: true,
          createdAt: DateTime(2026, 3, 1),
        ),
      ],
    );

    final authService = FakeAuthService(currentUser: _supportStaffUser());
    final adminService = FakeAdminService(
      authService: authService,
      fakeStats: const AdminStats(
        totalHouseholds: 1,
        activeSubscriptions: 1,
        totalUsers: 3,
        aiUsageThisMonth: 0,
        lastAuditAction: null,
      ),
      fakeHouseholds: [household],
      fakeHouseholdDetails: {'hh-1': householdDetail},
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
    await tester.tap(find.text('Households'));
    await tester.pumpAndSettle();

    expect(find.text('Devi Family'), findsWidgets);
    expect(find.text('Save Notes'), findsNothing);
    expect(find.text('Suspend'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);

    final notesField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(notesField.enabled, isFalse);
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
    this.fakeHouseholds = const [],
    this.fakeHouseholdDetails = const {},
  }) : super(
          supabaseUrl: 'https://example.supabase.co',
          supabaseAnonKey: 'test-anon-key',
          authService: authService,
        );

  final AdminStats? fakeStats;
  final List<AuditLog> fakeAuditLogs;
  final List<AdminHouseholdSummary> fakeHouseholds;
  final Map<String, AdminHouseholdDetail> fakeHouseholdDetails;

  @override
  AdminStats? get stats => fakeStats;

  @override
  List<AuditLog> get auditLogs => fakeAuditLogs;

  @override
  List<AdminStaff> get staff => const [];

  @override
  List<AdminUser> get users => const [];

  @override
  List<AdminApprovalRequest> get approvalRequests => const [];

  @override
  List<AdminSubscription> get subscriptions => const [];

  @override
  List<AdminPlan> get plans => const [];

  @override
  bool get isLoading => false;

  @override
  Future<AdminStats?> fetchStats() async => fakeStats;

  @override
  Future<List<AuditLog>> fetchAuditLogs({String? resourceType, String? resourceId, int limit = 50}) async {
    return fakeAuditLogs;
  }

  @override
  Future<List<AdminHouseholdSummary>> fetchHouseholds({
    String? query,
    bool? suspendedOnly,
    int limit = 100,
  }) async {
    return fakeHouseholds;
  }

  @override
  Future<AdminHouseholdDetail> fetchHouseholdDetail(String householdId) async {
    final detail = fakeHouseholdDetails[householdId];
    if (detail == null) {
      throw const AdminException('Household detail not found in test fake');
    }
    return detail;
  }

  @override
  Future<List<AdminStaff>> fetchStaff() async => [];

  @override
  Future<List<AdminUser>> fetchUsers({String? query, String? role, int limit = 100}) async => [];

  @override
  Future<List<AdminApprovalRequest>> fetchApprovalRequests({
    String? status,
    String? actionType,
    int limit = 100,
  }) async => [];

  @override
  Future<List<AdminSubscription>> fetchSubscriptions({String? status, int limit = 100}) async => [];

  @override
  Future<List<AdminPlan>> fetchPlans() async => [];
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

AppUser _supportStaffUser({Map<String, dynamic>? adminPermissions}) {
  return AppUser(
    id: 'staff-1',
    supabaseUserId: 'auth-staff-1',
    email: 'support@example.com',
    role: 'member',
    staffRole: 'support_staff',
    staffScope: 'global',
    adminPermissions: adminPermissions,
    notificationsEnabled: true,
    voiceEnabled: true,
    createdAt: DateTime(2026, 3, 19),
  );
}