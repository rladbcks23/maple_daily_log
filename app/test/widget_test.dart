import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts from Nexon login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('넥슨 계정으로 로그인하면\n캐릭터 정보를 자동으로 불러와요.'), findsOneWidget);
    expect(find.text('넥슨 계정으로 로그인'), findsOneWidget);
  });
}
