// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:myparivaar/main.dart';
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

  testWidgets('App initializes correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService(supabaseUrl: 'test')),
          ChangeNotifierProvider(
            create: (context) => AdminService(
              supabaseUrl: 'test',
              authService: context.read<AuthService>(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => ViewModeProvider()),
        ],
        child: const MyParivaaarApp(),
      ),
    );

    // Verify that the app starts (basic smoke test)
    await tester.pump();
    // The app should load without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
