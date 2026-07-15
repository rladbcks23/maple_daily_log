import 'package:flutter_test/flutter_test.dart';

import 'package:maple_task_reminder/main.dart';

void main() {
  testWidgets('starts from Nexon login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MapleTaskReminderApp());

    expect(find.text('메이플 숙제알리미'), findsOneWidget);
    expect(find.text('넥슨 계정의 캐릭터 목록을\n서버 API로 불러옵니다.'), findsOneWidget);
    expect(find.text('넥슨 계정 캐릭터 불러오기'), findsOneWidget);
  });
}
