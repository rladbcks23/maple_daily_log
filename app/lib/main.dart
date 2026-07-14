import 'package:flutter/material.dart';

void main() {
  runApp(const MapleTaskReminderApp());
}

class MapleTaskReminderApp extends StatelessWidget {
  const MapleTaskReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '메이플 숙제알리미',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F80ED),
          brightness: Brightness.light,
        ),
        fontFamily: 'Malgun Gothic',
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum ReminderPriority { urgent, warning, info, done }

class CharacterSummary {
  const CharacterSummary({
    required this.name,
    required this.world,
    required this.job,
    required this.level,
    required this.imagePath,
    required this.isSelected,
  });

  final String name;
  final String world;
  final String job;
  final int level;
  final String imagePath;
  final bool isSelected;
}

class ReminderItem {
  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.priority,
  });

  final String title;
  final String subtitle;
  final String category;
  final ReminderPriority priority;
}

class NoticeItem {
  const NoticeItem({
    required this.title,
    required this.type,
    required this.dateLabel,
  });

  final String title;
  final String type;
  final String dateLabel;
}

const characters = [
  CharacterSummary(
    name: '루미너스알림',
    world: '스카니아',
    job: '아델',
    level: 281,
    imagePath: 'assets/images/character_adele.png',
    isSelected: true,
  ),
  CharacterSummary(
    name: '오늘도숙제',
    world: '크로아',
    job: '라라',
    level: 266,
    imagePath: 'assets/images/character_lara.png',
    isSelected: true,
  ),
  CharacterSummary(
    name: '보스가기싫다',
    world: '엘리시움',
    job: '비숍',
    level: 260,
    imagePath: 'assets/images/character_lara.png',
    isSelected: false,
  ),
];

const reminders = [
  ReminderItem(
    title: '오늘 아직 접속하지 않았어요',
    subtitle: 'daily_contents가 비어 있어요. 접속 후 일일 숙제를 확인해야 합니다.',
    category: '일일 접속 알림',
    priority: ReminderPriority.urgent,
  ),
  ReminderItem(
    title: '몬스터 파크 2회 남음',
    subtitle: '런처 종료 후 확인된 미완료 일간 콘텐츠입니다.',
    category: '런처 종료 후 알림',
    priority: ReminderPriority.warning,
  ),
  ReminderItem(
    title: '주간 보스 확인 필요',
    subtitle: '화/수 밤 9시에만 주간 콘텐츠와 보스 상태를 갱신합니다.',
    category: '주간 알림',
    priority: ReminderPriority.info,
  ),
  ReminderItem(
    title: '오늘 로그인 보상 완료',
    subtitle: '오늘 로그인 정보가 확인되었습니다.',
    category: '완료',
    priority: ReminderPriority.done,
  ),
];

const notices = [
  NoticeItem(
    title: '신규 이벤트 공지',
    type: '이벤트',
    dateLabel: '오늘',
  ),
  NoticeItem(
    title: '캐시샵 판매 안내',
    type: '캐시샵',
    dateLabel: '오늘',
  ),
  NoticeItem(
    title: '클라이언트 업데이트',
    type: '업데이트',
    dateLabel: '어제',
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardPage(),
      const CharacterPage(),
      const NoticesPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            minWidth: 88,
            backgroundColor: const Color(0xFF18263B),
            selectedIndex: selectedIndex,
            onDestinationSelected: (value) {
              setState(() => selectedIndex = value);
            },
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.only(top: 24, bottom: 28),
              child: _AppMark(),
            ),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedIconTheme: const IconThemeData(color: Color(0xFFAAB6C8)),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelTextStyle: const TextStyle(
              color: Color(0xFFAAB6C8),
              fontWeight: FontWeight.w600,
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.notifications_active_outlined),
                selectedIcon: Icon(Icons.notifications_active),
                label: Text('알림'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group),
                label: Text('캐릭터'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article),
                label: Text('공지'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('설정'),
              ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: pages[selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '메이플 숙제알리미',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF2F80ED),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.checklist_rtl,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE1E6EF)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '메이플 숙제알리미',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172033),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '접속 전, 종료 후, 주간 마감 전에 놓친 숙제를 알려줍니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B778C),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('런처 감지 중'),
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SummaryStrip(),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    _SectionCard(
                      title: '오늘 확인할 알림',
                      trailing: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('새로고침'),
                      ),
                      child: Column(
                        children: reminders
                            .map((item) => _ReminderTile(item: item))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _LauncherPreviewCard(),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              const Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _SelectedCharacterCard(),
                    SizedBox(height: 20),
                    _SundayCard(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _MetricCard(
            title: '선택 캐릭터',
            value: '2명',
            icon: Icons.person_pin_circle_outlined,
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: _MetricCard(
            title: '미완료 숙제',
            value: '3개',
            icon: Icons.warning_amber_rounded,
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: _MetricCard(
            title: '새 공지',
            value: '2건',
            icon: Icons.campaign_outlined,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2F80ED)),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF6B778C),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172033),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.item});

  final ReminderItem item;

  @override
  Widget build(BuildContext context) {
    final colors = switch (item.priority) {
      ReminderPriority.urgent => (
          const Color(0xFFFFEEF0),
          const Color(0xFFE5484D),
          Icons.error_outline
        ),
      ReminderPriority.warning => (
          const Color(0xFFFFF6E5),
          const Color(0xFFB76E00),
          Icons.schedule
        ),
      ReminderPriority.info => (
          const Color(0xFFEAF3FF),
          const Color(0xFF2F80ED),
          Icons.info_outline
        ),
      ReminderPriority.done => (
          const Color(0xFFEAF8EF),
          const Color(0xFF2F8F46),
          Icons.check_circle_outline
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.$2.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(colors.$3, color: colors.$2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172033),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Chip(label: item.category, color: colors.$2),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5D6A7E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LauncherPreviewCard extends StatelessWidget {
  const _LauncherPreviewCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '런처 종료 후 알림 미리보기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '메이플 런처 종료를 감지하면 서버에서 선택 캐릭터의 당일 스케줄러를 다시 조회합니다.',
            style: TextStyle(color: Color(0xFF5D6A7E), fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF172033),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 남은 숙제가 있어요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '몬스터 파크 2회, 일일 보스 1개를 완료하지 않았어요.',
                  style: TextStyle(color: Color(0xFFD8E1F1), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCharacterCard extends StatelessWidget {
  const _SelectedCharacterCard();

  @override
  Widget build(BuildContext context) {
    final selected = characters.where((item) => item.isSelected).toList();

    return _SectionCard(
      title: '알림 대상 캐릭터',
      child: Column(
        children: selected.map((character) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CharacterRow(character: character),
          );
        }).toList(),
      ),
    );
  }
}

class _SundayCard extends StatelessWidget {
  const _SundayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(
              'assets/images/sunday_maple.png',
              fit: BoxFit.cover,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '선데이 메이플',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172033),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '이벤트 목록 비교 후 새로 올라온 선데이 정보를 알림으로 표시합니다.',
                  style: TextStyle(color: Color(0xFF5D6A7E), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CharacterPage extends StatelessWidget {
  const CharacterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: _SectionCard(
        title: '캐릭터 선택',
        trailing: FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('넥슨 계정에서 불러오기'),
        ),
        child: Column(
          children: characters.map((character) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE1E6EF)),
                ),
                child: Row(
                  children: [
                    _CharacterAvatar(character: character),
                    const SizedBox(width: 14),
                    Expanded(child: _CharacterMeta(character: character)),
                    Switch(
                      value: character.isSelected,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({required this.character});

  final CharacterSummary character;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CharacterAvatar(character: character),
        const SizedBox(width: 12),
        Expanded(child: _CharacterMeta(character: character)),
      ],
    );
  }
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final CharacterSummary character;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Image.asset(character.imagePath, fit: BoxFit.cover),
    );
  }
}

class _CharacterMeta extends StatelessWidget {
  const _CharacterMeta({required this.character});

  final CharacterSummary character;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          character.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF172033),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${character.world} · ${character.job} · Lv.${character.level}',
          style: const TextStyle(
            color: Color(0xFF6B778C),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class NoticesPage extends StatelessWidget {
  const NoticesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: _SectionCard(
        title: '새 공지와 이벤트',
        child: Column(
          children: notices.map((notice) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE1E6EF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: Color(0xFF2F80ED)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notice.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172033),
                      ),
                    ),
                  ),
                  _Chip(label: notice.type, color: const Color(0xFF2F80ED)),
                  const SizedBox(width: 10),
                  Text(
                    notice.dateLabel,
                    style: const TextStyle(
                      color: Color(0xFF6B778C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: _SectionCard(
        title: '앱 설정',
        child: Column(
          children: const [
            _SettingRow(
              icon: Icons.login,
              title: '넥슨 로그인',
              description: '선택 캐릭터 목록을 불러오기 위해 넥슨 계정을 연결합니다.',
            ),
            _SettingRow(
              icon: Icons.notifications_active_outlined,
              title: '밤 9시 알림',
              description: '일일 접속, 주간 마감, 신규 공지 알림을 앱 창으로 표시합니다.',
            ),
            _SettingRow(
              icon: Icons.sensors_outlined,
              title: '런처 종료 감지',
              description: '메이플 런처 종료 시점에 당일 미완료 숙제를 다시 확인합니다.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2F80ED)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5D6A7E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFFE1E6EF)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0F172033),
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );
}
