import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts from character home page', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('알림을 받을 캐릭터를 먼저 추가해주세요.'), findsOneWidget);
    expect(find.text('캐릭터 추가'), findsOneWidget);
  });
}
