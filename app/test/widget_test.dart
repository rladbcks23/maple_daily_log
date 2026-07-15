import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts without seeded demo data', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('루미너스알림'), findsNothing);
    expect(find.text('일일 콘텐츠'), findsNothing);
    expect(find.text('캐시샵 판매 안내가 갱신되었습니다.'), findsNothing);
  });
}
