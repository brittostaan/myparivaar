// myParivaar app widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:myparivaar/main.dart';
import 'package:myparivaar/services/auth_service.dart';

void main() {
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
