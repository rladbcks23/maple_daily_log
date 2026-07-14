import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('shows reminder dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsWidgets);
    expect(find.text('오늘 확인할 알림'), findsOneWidget);
    expect(find.text('오늘 아직 접속하지 않았어요'), findsOneWidget);
  });

  testWidgets('opens character page from navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    await tester.tap(find.text('캐릭터'));
    await tester.pump();

    expect(find.text('캐릭터 선택'), findsOneWidget);
    expect(find.text('넥슨 계정에서 불러오기'), findsOneWidget);
  });
}
