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
        fontFamily: 'Malgun Gothic',
        scaffoldBackgroundColor: AppColors.canvas,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum AppPage { scheduler, events, notices, sunday, characters }

class CharacterInfo {
  const CharacterInfo({
    required this.name,
    required this.world,
    required this.job,
    required this.level,
    required this.image,
    required this.selected,
  });

  final String name;
  final String world;
  final String job;
  final int level;
  final String image;
  final bool selected;
}

class TaskItem {
  const TaskItem({
    required this.title,
    required this.meta,
    required this.done,
  });

  final String title;
  final String meta;
  final bool done;
}

class BossItem {
  const BossItem({
    required this.name,
    required this.difficulty,
    required this.initial,
    required this.done,
  });

  final String name;
  final String difficulty;
  final String initial;
  final bool done;
}

class NoticeInfo {
  const NoticeInfo({
    required this.tag,
    required this.title,
    required this.date,
    required this.color,
  });

  final String tag;
  final String title;
  final String date;
  final Color color;
}

enum NoticeFilter { all, notice, event, cashshop, update }

class EventInfo {
  const EventInfo({
    required this.title,
    required this.period,
    required this.newItem,
  });

  final String title;
  final String period;
  final bool newItem;
}

class AppColors {
  static const canvas = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFFEFBF2);
  static const border = Color(0xFFE8E2D4);
  static const softBorder = Color(0xFFE8EAF0);
  static const text = Color(0xFF3D4048);
  static const muted = Color(0xFF7B8291);
  static const blue = Color(0xFF5E76B7);
  static const selected = Color(0xFFEAF0FF);
  static const selectedBorder = Color(0xFFB8C8F8);
  static const section = Color(0xFFAAB2B8);
  static const doneBg = Color(0xFFFFFFFF);
  static const doneText = Color(0xFF3D4048);
  static const missingBg = Color(0xFFFFF5F0);
  static const missingText = Color(0xFFB85F47);
}

const characters = [
  CharacterInfo(
    name: '루미너스알림',
    world: '스카니아',
    job: '아델',
    level: 281,
    image: 'assets/images/character_adele.png',
    selected: true,
  ),
  CharacterInfo(
    name: '오늘도숙제',
    world: '크로아',
    job: '라라',
    level: 266,
    image: 'assets/images/character_lara.png',
    selected: true,
  ),
  CharacterInfo(
    name: '보스가기싫다',
    world: '엘리시움',
    job: '비숍',
    level: 260,
    image: 'assets/images/character_lara.png',
    selected: false,
  ),
];

const dailyQuests = [
  TaskItem(title: '일일 퀘스트', meta: '0 / 1', done: false),
];

const dailyContents = [
  TaskItem(title: '몬스터 파크', meta: '5 / 7', done: false),
  TaskItem(title: '일일 보스', meta: '완료', done: true),
  TaskItem(title: '오늘 로그인', meta: '미확인', done: false),
];

const weeklyQuests = [
  TaskItem(title: '주간 퀘스트', meta: '2 / 3', done: false),
  TaskItem(title: '심볼 퀘스트', meta: '완료', done: true),
];

const weeklyContents = [
  TaskItem(title: '익스트림 몬스터 파크', meta: '0 / 1', done: false),
  TaskItem(title: '에픽 던전', meta: '완료', done: true),
  TaskItem(title: '수로', meta: '미완료', done: false),
  TaskItem(title: '플래그', meta: '완료', done: true),
];

const dailyBosses = [
  BossItem(name: '자쿰', difficulty: 'NORMAL', initial: '자', done: true),
  BossItem(name: '매그너스', difficulty: 'EASY', initial: '매', done: false),
];

const weeklyBosses = [
  BossItem(name: '스우', difficulty: 'HARD', initial: '스', done: false),
  BossItem(name: '데미안', difficulty: 'HARD', initial: '데', done: true),
  BossItem(name: '루시드', difficulty: 'NORMAL', initial: '루', done: false),
  BossItem(name: '윌', difficulty: 'NORMAL', initial: '윌', done: false),
  BossItem(name: '더스크', difficulty: 'CHAOS', initial: '더', done: true),
  BossItem(name: '듄켈', difficulty: 'HARD', initial: '듄', done: false),
];

const monthlyBosses = [
  BossItem(name: '검은 마법사', difficulty: 'MONTHLY', initial: '검', done: false),
];

const notices = [
  NoticeInfo(tag: '공지', title: '메이플스토리 신규 공지사항이 등록되었습니다.', date: '오늘', color: Color(0xFF5E76B7)),
  NoticeInfo(tag: '이벤트', title: '진행 중인 출석 이벤트가 새로 추가되었습니다.', date: '오늘', color: Color(0xFF54A56D)),
  NoticeInfo(tag: '캐시샵', title: '캐시샵 판매 안내가 갱신되었습니다.', date: '어제', color: Color(0xFFD1913C)),
  NoticeInfo(tag: '업데이트', title: '클라이언트 업데이트 안내', date: '어제', color: Color(0xFF8A6CCF)),
];

const events = [
  EventInfo(title: '출석 체크 이벤트', period: '2026.07.10 - 2026.08.06', newItem: true),
  EventInfo(title: '몬스터 처치 주간 미션', period: '2026.07.11 - 2026.07.24', newItem: true),
  EventInfo(title: '선데이 메이플', period: '이번 주 일요일', newItem: false),
  EventInfo(title: '버닝 월드 사전 안내', period: '상시 확인', newItem: false),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppPage page = AppPage.scheduler;
  bool showAlert = true;

  String get pageTitle {
    return switch (page) {
      AppPage.scheduler => '스케줄러',
      AppPage.events => '이벤트',
      AppPage.notices => '공지사항',
      AppPage.sunday => '이번주 선데이',
      AppPage.characters => '캐릭터 선택',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              _Sidebar(
                currentPage: page,
                onPageChanged: (value) => setState(() => page = value),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: pageTitle,
                      onPreview: () => setState(() => showAlert = true),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(32, 6, 32, 32),
                        child: _PageBody(page: page),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showAlert)
            Positioned(
              right: 28,
              bottom: 28,
              child: _FloatingAlert(onClose: () => setState(() => showAlert = false)),
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentPage,
    required this.onPageChanged,
  });

  final AppPage currentPage;
  final ValueChanged<AppPage> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final selected = characters.firstWhere((character) => character.selected);

    return Container(
      width: 264,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'M',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '메이플 숙제알리미',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '놓친 숙제, 이제 안 놓치게',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SelectedCharacterTile(
            character: selected,
            onTap: () => onPageChanged(AppPage.characters),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Divider(height: 1, color: AppColors.border),
          ),
          _NavButton(
            label: '스케줄러',
            selected: currentPage == AppPage.scheduler,
            onTap: () => onPageChanged(AppPage.scheduler),
          ),
          _NavButton(
            label: '이벤트',
            selected: currentPage == AppPage.events,
            onTap: () => onPageChanged(AppPage.events),
          ),
          _NavButton(
            label: '공지사항',
            selected: currentPage == AppPage.notices,
            onTap: () => onPageChanged(AppPage.notices),
          ),
          _NavButton(
            label: '이번주 선데이',
            selected: currentPage == AppPage.sunday,
            onTap: () => onPageChanged(AppPage.sunday),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('로그아웃'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.muted,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCharacterTile extends StatelessWidget {
  const _SelectedCharacterTile({
    required this.character,
    required this.onTap,
  });

  final CharacterInfo character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _CharacterImage(path: character.image, size: 34, radius: 9),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${character.job} · Lv.${character.level}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? AppColors.selectedBorder : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.blue : AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onPreview,
  });

  final String title;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onPreview,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.softBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text(
              '놓친 알림 미리보기',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});

  final AppPage page;

  @override
  Widget build(BuildContext context) {
    return switch (page) {
      AppPage.scheduler => const _SchedulerPage(),
      AppPage.events => const _EventsPage(),
      AppPage.notices => const _NoticesPage(),
      AppPage.sunday => const _SundayPage(),
      AppPage.characters => const _CharactersPage(),
    };
  }
}

class _SchedulerPage extends StatelessWidget {
  const _SchedulerPage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final left = Column(
          children: const [
            _TaskCard(
              title: '일일 콘텐츠',
              groups: [
                _TaskGroup(title: 'QUEST', items: dailyQuests),
                _TaskGroup(title: 'CONTENTS', items: dailyContents),
              ],
            ),
            SizedBox(height: 20),
            _TaskCard(
              title: '주간 콘텐츠',
              groups: [
                _TaskGroup(title: 'QUEST', items: weeklyQuests),
                _TaskGroup(title: 'CONTENTS', items: weeklyContents),
              ],
            ),
          ],
        );
        const right = _BossCard();

        if (compact) {
          return Column(children: [left, const SizedBox(height: 20), right]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 20),
            const Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.title,
    required this.groups,
  });

  final String title;
  final List<_TaskGroup> groups;

  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      title: title,
      child: Column(
        children: groups
            .map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    _SectionLabel(group.title),
                    ...group.items.map((item) => _TaskRow(item: item)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TaskGroup {
  const _TaskGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<TaskItem> items;
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.item});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: item.done ? AppColors.doneBg : AppColors.missingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                color: item.done ? AppColors.doneText : AppColors.missingText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            item.meta,
            style: TextStyle(
              color: item.done ? AppColors.doneText : AppColors.missingText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BossCard extends StatelessWidget {
  const _BossCard();

  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      title: '보스 콘텐츠',
      child: const Column(
        children: [
          _BossGroup(title: 'DAILY', items: dailyBosses),
          SizedBox(height: 8),
          _BossGroup(title: 'WEEKLY', items: weeklyBosses),
          SizedBox(height: 8),
          _BossGroup(title: 'MONTHLY', items: monthlyBosses),
        ],
      ),
    );
  }
}

class _BossGroup extends StatelessWidget {
  const _BossGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<BossItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SectionLabel(title),
        ...items.map((item) => _BossRow(item: item)),
      ],
    );
  }
}

class _BossRow extends StatelessWidget {
  const _BossRow({required this.item});

  final BossItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.done ? AppColors.doneText : AppColors.missingText;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: item.done ? AppColors.doneBg : AppColors.missingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              item.initial,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.difficulty,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.section,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CharactersPage extends StatelessWidget {
  const _CharactersPage();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 1100 ? 4 : 3,
      childAspectRatio: 0.78,
      crossAxisSpacing: 18,
      mainAxisSpacing: 18,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ...characters.map((character) => _CharacterCard(character: character)),
        const _AddCharacterCard(),
      ],
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});

  final CharacterInfo character;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: character.selected ? AppColors.selected : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          width: 2,
          color: character.selected ? AppColors.selectedBorder : AppColors.softBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _CharacterImage(path: character.image, size: double.infinity, radius: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              if (character.selected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '선택됨',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${character.world} · ${character.job} · Lv.${character.level}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddCharacterCard extends StatelessWidget {
  const _AddCharacterCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.softBorder, width: 2),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('+', style: TextStyle(color: AppColors.blue, fontSize: 32, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text('캐릭터 추가', style: TextStyle(color: AppColors.muted, fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _EventsPage extends StatelessWidget {
  const _EventsPage();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 1180 ? 3 : 2,
      childAspectRatio: 1.55,
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: events.map((event) => _EventCard(event: event)).toList(),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final EventInfo event;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFFF0F2F6),
              alignment: Alignment.center,
              child: Text(
                event.newItem ? 'NEW EVENT' : 'EVENT',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(event.period, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticesPage extends StatefulWidget {
  const _NoticesPage();

  @override
  State<_NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<_NoticesPage> {
  NoticeFilter selectedFilter = NoticeFilter.all;

  List<NoticeInfo> get filteredNotices {
    return notices.where((notice) {
      return switch (selectedFilter) {
        NoticeFilter.all => true,
        NoticeFilter.notice => notice.tag == '공지',
        NoticeFilter.event => notice.tag == '이벤트',
        NoticeFilter.cashshop => notice.tag == '캐시샵',
        NoticeFilter.update => notice.tag == '업데이트',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _NoticeFilter(
                label: '전체',
                active: selectedFilter == NoticeFilter.all,
                onTap: () => setState(() => selectedFilter = NoticeFilter.all),
              ),
              _NoticeFilter(
                label: '공지',
                active: selectedFilter == NoticeFilter.notice,
                onTap: () => setState(() => selectedFilter = NoticeFilter.notice),
              ),
              _NoticeFilter(
                label: '이벤트',
                active: selectedFilter == NoticeFilter.event,
                onTap: () => setState(() => selectedFilter = NoticeFilter.event),
              ),
              _NoticeFilter(
                label: '캐시샵',
                active: selectedFilter == NoticeFilter.cashshop,
                onTap: () => setState(() => selectedFilter = NoticeFilter.cashshop),
              ),
              _NoticeFilter(
                label: '업데이트',
                active: selectedFilter == NoticeFilter.update,
                onTap: () => setState(() => selectedFilter = NoticeFilter.update),
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.softBorder),
          ...filteredNotices.map((notice) => _NoticeRow(notice: notice)),
        ],
      ),
    );
  }
}

class _NoticeFilter extends StatelessWidget {
  const _NoticeFilter({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 4, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: active ? AppColors.blue : Colors.transparent, width: 3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.blue : AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice});

  final NoticeInfo notice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.softBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: notice.color, borderRadius: BorderRadius.circular(999)),
            child: Text(
              notice.tag,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              notice.title,
              style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
          Text(notice.date, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SundayPage extends StatelessWidget {
  const _SundayPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/sunday_maple.png',
        fit: BoxFit.contain,
        width: double.infinity,
      ),
    );
  }
}

class _CharacterImage extends StatelessWidget {
  const _CharacterImage({
    required this.path,
    required this.size,
    required this.radius,
  });

  final String path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Image.asset(path, fit: BoxFit.cover),
    );
  }
}

class _FloatingAlert extends StatelessWidget {
  const _FloatingAlert({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF303645),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.missingText,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '아직 남은 숙제가 있어요',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  '몬스터 파크와 주간 보스 상태를 확인해 주세요.',
                  style: TextStyle(color: Color(0xFFD9DEE8), fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Color(0xFFD9DEE8), size: 18),
            tooltip: '닫기',
          ),
        ],
      ),
    );
  }
}
