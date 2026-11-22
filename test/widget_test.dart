import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:message_board/main.dart';

void main() {
  testWidgets('Splash screen shows the title and a loading indicator', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('Message Board'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Error screen shows a working Retry button', (
    WidgetTester tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorScreen(
          error: 'test failure',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not connect to Firebase'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
