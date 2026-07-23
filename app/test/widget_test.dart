import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('shows the startup loading screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
