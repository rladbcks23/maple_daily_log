import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts from character select app shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('캐릭터 선택'), findsOneWidget);
    expect(find.text('알림을 받을 캐릭터를 선택해주세요.'), findsOneWidget);
    expect(find.text('스케쥴러'), findsOneWidget);
  });
}
