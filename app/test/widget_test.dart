import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts from Nexon login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('넥슨 로그인부터 시작해요'), findsOneWidget);
    expect(find.text('넥슨 로그인'), findsOneWidget);
  });
}
