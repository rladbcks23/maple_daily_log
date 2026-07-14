import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('shows reminder dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsWidgets);
    expect(find.text('스케줄러'), findsWidgets);
    expect(find.text('일일 콘텐츠'), findsOneWidget);
    expect(find.text('보스 콘텐츠'), findsOneWidget);
  });

  testWidgets('opens character page from navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    await tester.tap(find.text('캐릭터'));
    await tester.pump();

    expect(find.text('캐릭터 선택'), findsWidgets);
    expect(find.text('캐릭터 추가'), findsOneWidget);
  });

  testWidgets('filters notices by category', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    await tester.tap(find.text('공지사항'));
    await tester.pump();

    expect(find.text('캐시샵 판매 안내가 갱신되었습니다.'), findsOneWidget);

    await tester.tap(find.text('캐시샵'));
    await tester.pump();

    expect(find.text('캐시샵 판매 안내가 갱신되었습니다.'), findsOneWidget);
    expect(find.text('진행 중인 출석 이벤트가 새로 추가되었습니다.'), findsNothing);
  });
}
