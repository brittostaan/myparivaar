// myParivaar app widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'package:myparivaar/main.dart';
import 'package:myparivaar/services/auth_service.dart';

// Mock Firebase for testing
void main() {
  // Setup Firebase for testing
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
  });

  testWidgets('myParivaar app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthService(supabaseUrl: 'https://test.supabase.co'),
        child: const MyParivaaarApp(),
      ),
    );
    
    // Wait for the app to finish loading
    await tester.pumpAndSettle();

    // Verify the app loads without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
