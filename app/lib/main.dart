import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'api_client.dart';
import 'character_cache.dart';
import 'local_notification_service.dart';
import 'notification_history.dart';
import 'scheduler_cache.dart';
import 'sunday_event_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
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
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

class _StartupData {
  const _StartupData({
    required this.noticeItems,
    this.sundayEvent,
    required this.hasLoadedNotices,
  });

  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool hasLoadedNotices;
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<_StartupData> _startupData = _loadStartupData();

  Future<_StartupData> _loadStartupData() async {
    final apiClient = ApiClient();
    final sundayCache = SundayEventCache();
    final cachedSundayEvent = await sundayCache.load();

    try {
      final noticeItems = await apiClient.fetchCurrentNotices();
      var sundayEvent = _findSpecialSundayEvent(noticeItems);
      sundayEvent ??= await apiClient.fetchLatestSundayEvent();
      if (sundayEvent != null) {
        await sundayCache.save(sundayEvent);
      }
      return _StartupData(
        noticeItems: noticeItems,
        sundayEvent: sundayEvent ?? cachedSundayEvent,
        hasLoadedNotices: true,
      );
    } catch (_) {
      return _StartupData(
        noticeItems: const [],
        sundayEvent: cachedSundayEvent,
        hasLoadedNotices: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupData>(
      future: _startupData,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _MapleAppShell(startupData: snapshot.requireData);
        }
        return const _StartupLoadingScreen();
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '메이플 숙제알리미',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFFEFBF2);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE8E2D4);
  static const softBorder = Color(0xFFE8EAF0);
  static const text = Color(0xFF3D4048);
  static const muted = Color(0xFF7B8291);
  static const primary = Color(0xFF5E76B7);
  static const selected = Color(0xFFEAF0FF);
  static const selectedBorder = Color(0xFFB8C8F8);
  static const navAccent = Color(0xFFE98946);
  static const navBorder = Color(0xFFF1B98C);
  static const completionTag = Color(0xFFFFFAF8);
  static const completionTagBorder = Color(0xFFE6B9AC);
  static const completionTagText = Color(0xFFA76150);
  static const button = Color(0xFF3D4048);
  static const disabled = Color(0xFFB8BEC9);
}

enum AppSection {
  dashboard('대시보드', Icons.dashboard_outlined),
  character('캐릭터 선택', Icons.person_add_alt_1_rounded),
  scheduler('스케쥴러', Icons.event_note_rounded),
  events('진행중인 이벤트', Icons.celebration_rounded),
  notices('공지사항', Icons.campaign_rounded),
  sunday('이번주 썬데이', Icons.wb_sunny_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _MapleAppShell extends StatefulWidget {
  const _MapleAppShell({required this.startupData});

  final _StartupData startupData;

  @override
  State<_MapleAppShell> createState() => _MapleAppShellState();
}

class _MapleAppShellState extends State<_MapleAppShell>
    with WindowListener, TrayListener {
  final ApiClient apiClient = ApiClient();
  final CharacterCache characterCache = CharacterCache();
  final SchedulerCache schedulerCache = SchedulerCache();
  final SundayEventCache sundayEventCache = SundayEventCache();
  final NotificationHistory notificationHistory = NotificationHistory();

  Timer? notificationTimer;
  var isCheckingScheduledNotifications = false;
  var currentSection = AppSection.character;
  var isLoading = false;
  var isSchedulerLoading = false;
  var isSchedulerRefreshing = false;
  var isNoticeLoading = false;
  var isNoticeRefreshing = false;
  String? errorMessage;
  String? schedulerErrorMessage;
  String? noticeErrorMessage;
  NexonCharacterSummary? selectedCharacter;
  List<NexonCharacterSummary> selectedCharacters = const [];
  SchedulerSnapshot? schedulerSnapshot;
  Map<String, SchedulerSnapshot> dashboardSnapshots = const {};
  List<NoticeItemSummary> noticeItems = const [];
  NoticeItemSummary? sundayEvent;

  @override
  void initState() {
    super.initState();
    noticeItems = widget.startupData.noticeItems;
    sundayEvent = widget.startupData.sundayEvent;
    LocalNotificationService.instance.setOnNotificationTap(
      handleNotificationTap,
    );
    unawaited(initializeDesktopControls());
    unawaited(initializeNotifications());
    unawaited(loadCachedCharacters());
    if (!widget.startupData.hasLoadedNotices) {
      unawaited(loadInitialNoticeData());
    }
    notificationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(checkScheduledNotifications()),
    );
    unawaited(checkScheduledNotifications());
  }

  Future<void> initializeNotifications() async {
    final payload = await LocalNotificationService.instance.initialize();
    if (payload != null) {
      handleNotificationTap(payload);
    }
  }

  Future<void> initializeDesktopControls() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/images/app_icon.ico');
    await trayManager.setToolTip('메이플 숙제알리미');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '열기'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: '종료'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    notificationTimer?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(hideWindowToTray());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindowFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(showWindowFromTray());
      case 'exit_app':
        unawaited(exitApplication());
    }
  }

  Future<void> hideWindowToTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> showWindowFromTray() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> exitApplication() async {
    await trayManager.destroy();
    await windowManager.destroy();
  }

  Future<void> loadCachedCharacters() async {
    final cachedData = await characterCache.load();
    if (!mounted || cachedData == null || cachedData.characters.isEmpty) {
      return;
    }

    final selected = cachedData.characters.firstWhere(
      (character) => character.ocid == cachedData.selectedOcid,
      orElse: () => cachedData.characters.first,
    );
    setState(() {
      selectedCharacters = cachedData.characters;
      selectedCharacter = selected;
    });
    unawaited(loadDashboardSnapshots());
    unawaited(loadScheduler(selected));
    unawaited(checkScheduledNotifications());
  }

  void persistCharacters() {
    unawaited(characterCache.save(selectedCharacters, selectedCharacter));
  }

  Future<void> loadDashboardSnapshots() async {
    final entries = await Future.wait(
      selectedCharacters.map((character) async {
        final snapshot = await schedulerCache.load(character.ocid);
        return MapEntry(character.ocid, snapshot);
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      dashboardSnapshots = {
        for (final entry in entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    });
  }

  Future<void> loadInitialNoticeData() async {
    final cachedSundayEvent = await sundayEventCache.load();
    if (mounted && cachedSundayEvent != null) {
      setState(() {
        sundayEvent = cachedSundayEvent;
      });
    }
    await loadCurrentNotices();
  }

  Future<void> openCharacterPicker() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final characters = await apiClient.fetchNexonCharacters();
      if (!mounted) {
        return;
      }

      final sortedCharacters = [...characters]..sort((a, b) {
          final levelComparison =
              (b.characterLevel ?? -1).compareTo(a.characterLevel ?? -1);
          if (levelComparison != 0) {
            return levelComparison;
          }
          return a.characterName.compareTo(b.characterName);
        });

      final selected = await showDialog<NexonCharacterSummary>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return _CharacterPickerDialog(
            characters: sortedCharacters,
            selectedCharacter: selectedCharacter,
            selectedCharacters: selectedCharacters,
            loadCharacterBasic: apiClient.fetchCharacterBasic,
          );
        },
      );

      if (selected != null && mounted) {
        final detailed = selected.characterImage.isEmpty
            ? await apiClient.fetchCharacterBasic(selected)
            : selected;
        if (!mounted) {
          return;
        }

        setState(() {
          final nextCharacters = [...selectedCharacters];
          final existingIndex = nextCharacters.indexWhere(
            (character) => _isSameCharacter(character, detailed),
          );
          if (existingIndex == -1) {
            nextCharacters.add(detailed);
          } else {
            nextCharacters[existingIndex] = detailed;
          }
          selectedCharacters = nextCharacters;
          selectedCharacter = detailed;
          schedulerSnapshot = null;
          schedulerErrorMessage = null;
        });
        persistCharacters();
        unawaited(loadDashboardSnapshots());
        await loadScheduler(detailed);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> selectCharacter(NexonCharacterSummary character) async {
    if (_isSameCharacter(character, selectedCharacter)) {
      return;
    }

    setState(() {
      selectedCharacter = character;
      schedulerSnapshot = null;
      schedulerErrorMessage = null;
    });
    persistCharacters();
    await loadScheduler(character);
  }

  void deleteCharacter(NexonCharacterSummary character) {
    final deletesSelected = _isSameCharacter(character, selectedCharacter);
    NexonCharacterSummary? nextSelectedCharacter;

    setState(() {
      selectedCharacters = selectedCharacters
          .where((selected) => !_isSameCharacter(selected, character))
          .toList();
      dashboardSnapshots = Map<String, SchedulerSnapshot>.from(
        dashboardSnapshots,
      )..remove(character.ocid);
      if (deletesSelected) {
        nextSelectedCharacter =
            selectedCharacters.isEmpty ? null : selectedCharacters.first;
        selectedCharacter = nextSelectedCharacter;
        schedulerSnapshot = null;
        schedulerErrorMessage = null;
        if (nextSelectedCharacter == null) {
          currentSection = AppSection.character;
        }
      }
    });
    persistCharacters();

    if (nextSelectedCharacter != null) {
      unawaited(loadScheduler(nextSelectedCharacter!));
    }
  }

  void moveCharacter(NexonCharacterSummary character, int offset) {
    final currentIndex = selectedCharacters.indexWhere(
      (selected) => _isSameCharacter(selected, character),
    );
    if (currentIndex < 0) {
      return;
    }

    final targetIndex = currentIndex + offset;
    if (targetIndex < 0 || targetIndex >= selectedCharacters.length) {
      return;
    }

    final nextCharacters = [...selectedCharacters];
    final movedCharacter = nextCharacters.removeAt(currentIndex);
    nextCharacters.insert(targetIndex, movedCharacter);

    setState(() {
      selectedCharacters = nextCharacters;
    });
    persistCharacters();
  }

  Future<void> loadScheduler(
    NexonCharacterSummary character, {
    bool refresh = false,
  }) async {
    final cachedSnapshot = await schedulerCache.load(character.ocid);
    if (!mounted || !_isSameCharacter(character, selectedCharacter)) {
      return;
    }

    final hasCachedSnapshot = cachedSnapshot != null;
    setState(() {
      if (refresh || hasCachedSnapshot) {
        isSchedulerRefreshing = true;
      } else {
        isSchedulerLoading = true;
      }
      schedulerErrorMessage = null;
      if (hasCachedSnapshot) {
        schedulerSnapshot = cachedSnapshot;
      }
    });

    try {
      final snapshot = await apiClient.fetchScheduler(
        character.ocid,
        forceRefresh: refresh,
      );
      final displayedSnapshot = cachedSnapshot == null
          ? snapshot
          : snapshot.withCachedEmptySections(cachedSnapshot);

      if (snapshot.hasDailyItems ||
          snapshot.hasWeeklyItems ||
          snapshot.hasBossItems) {
        final snapshotToCache = SchedulerSnapshot(
          dailyItems: snapshot.hasDailyItems
              ? snapshot.dailyItems
              : cachedSnapshot?.dailyItems ?? const [],
          weeklyItems: snapshot.hasWeeklyItems
              ? snapshot.weeklyItems
              : cachedSnapshot?.weeklyItems ?? const [],
          bossItems: snapshot.hasBossItems
              ? snapshot
                  .withCachedEmptySections(cachedSnapshot ?? snapshot)
                  .bossItems
              : cachedSnapshot?.bossItems ?? const [],
          weeklyBossClearCount: snapshot.weeklyBossClearCount ??
              cachedSnapshot?.weeklyBossClearCount,
          weeklyBossClearLimit: snapshot.weeklyBossClearLimit ??
              cachedSnapshot?.weeklyBossClearLimit,
        );
        await schedulerCache.save(character.ocid, snapshotToCache);
      }
      if (!mounted || !_isSameCharacter(character, selectedCharacter)) {
        return;
      }

      setState(() {
        schedulerSnapshot = displayedSnapshot;
        dashboardSnapshots = Map<String, SchedulerSnapshot>.from(
          dashboardSnapshots,
        )..[character.ocid] = displayedSnapshot;
      });
    } catch (error) {
      if (!mounted || !_isSameCharacter(character, selectedCharacter)) {
        return;
      }

      if (!hasCachedSnapshot) {
        setState(() {
          schedulerErrorMessage = error.toString();
        });
      }
    } finally {
      if (mounted && _isSameCharacter(character, selectedCharacter)) {
        setState(() {
          if (refresh || hasCachedSnapshot) {
            isSchedulerRefreshing = false;
          } else {
            isSchedulerLoading = false;
          }
        });
      }
    }
  }

  Future<void> loadCurrentNotices({bool refresh = false}) async {
    setState(() {
      if (refresh) {
        isNoticeRefreshing = true;
      } else {
        isNoticeLoading = true;
      }
      noticeErrorMessage = null;
    });

    try {
      final items = await apiClient.fetchCurrentNotices(
        forceRefresh: refresh,
      );
      final currentSundayEvent = _findSpecialSundayEvent(items);
      NoticeItemSummary? nextSundayEvent = currentSundayEvent;
      if (nextSundayEvent == null) {
        try {
          nextSundayEvent = await apiClient.fetchLatestSundayEvent(
            forceRefresh: refresh,
          );
        } on ApiException {
          nextSundayEvent = null;
        }
      }
      if (nextSundayEvent != null) {
        await sundayEventCache.save(nextSundayEvent);
      }
      if (!mounted) {
        return;
      }

      setState(() {
        noticeItems = items;
        if (nextSundayEvent != null) {
          sundayEvent = nextSundayEvent;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        noticeErrorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          if (refresh) {
            isNoticeRefreshing = false;
          } else {
            isNoticeLoading = false;
          }
        });
      }
    }
  }

  Future<void> refreshCurrentSection() async {
    if (currentSection == AppSection.scheduler) {
      final character = selectedCharacter;
      if (character != null) {
        await loadScheduler(character, refresh: true);
      }
      return;
    }

    if (currentSection == AppSection.events ||
        currentSection == AppSection.notices ||
        currentSection == AppSection.sunday) {
      await loadCurrentNotices(refresh: true);
    }
  }

  Future<void> showTestNotification() async {
    try {
      await LocalNotificationService.instance.showTestNotification();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Windows 알림을 보냈습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알림을 보내지 못했습니다: $error')),
      );
    }
  }

  void handleNotificationTap(String? payload) {
    if (!mounted) {
      return;
    }

    switch (payload) {
      case 'section:character':
        setState(() {
          currentSection = AppSection.character;
        });
      case 'section:scheduler':
        setState(() {
          currentSection = selectedCharacter == null
              ? AppSection.character
              : AppSection.scheduler;
        });
    }
  }

  Future<void> checkScheduledNotifications() async {
    if (isCheckingScheduledNotifications || selectedCharacters.isEmpty) {
      return;
    }

    final now = DateTime.now();
    if (now.hour != 21) {
      return;
    }

    isCheckingScheduledNotifications = true;
    try {
      await _checkDailyLoginNotification(now);
      if (now.weekday == DateTime.tuesday ||
          now.weekday == DateTime.wednesday) {
        await _checkWeeklyReminderNotification(now);
      }
    } finally {
      isCheckingScheduledNotifications = false;
    }
  }

  Future<void> _checkDailyLoginNotification(DateTime now) async {
    final ruleKey = 'daily-login-${_dateKey(now)}';
    if (await notificationHistory.hasSent(ruleKey)) {
      return;
    }

    final missingCharacters = <NexonCharacterSummary>[];
    for (final character in selectedCharacters) {
      try {
        final snapshot = await apiClient.fetchScheduler(character.ocid);
        if (!snapshot.hasDailyItems) {
          missingCharacters.add(character);
        }
      } on ApiException {
        // A failed lookup should not turn into a missed-login notification.
      }
    }

    if (missingCharacters.isEmpty) {
      return;
    }

    await LocalNotificationService.instance.showNotification(
      id: 1001,
      title: '오늘 접속 기록이 없어요',
      body: '${_characterNames(missingCharacters)} 접속 후 일일 숙제를 확인해주세요.',
      payload: 'section:scheduler',
    );
    await notificationHistory.markSent(ruleKey);
  }

  Future<void> _checkWeeklyReminderNotification(DateTime now) async {
    final ruleKey = 'weekly-reminder-${_dateKey(now)}';
    if (await notificationHistory.hasSent(ruleKey)) {
      return;
    }

    final incompleteCharacters = <NexonCharacterSummary>[];
    for (final character in selectedCharacters) {
      try {
        final snapshot = await apiClient.fetchScheduler(character.ocid);
        final cachedSnapshot = await schedulerCache.load(character.ocid);
        final displayedSnapshot = cachedSnapshot == null
            ? snapshot
            : snapshot.withCachedEmptySections(cachedSnapshot);
        final hasIncompleteWeeklyContent =
            displayedSnapshot.weeklyItems.any((item) => !item.done);
        final hasIncompleteWeeklyBoss = displayedSnapshot.bossItems
            .where(_isWeeklyBoss)
            .any((item) => !item.done);
        if (hasIncompleteWeeklyContent || hasIncompleteWeeklyBoss) {
          incompleteCharacters.add(character);
        }
      } on ApiException {
        // A failed lookup should not turn into an unfinished-content notification.
      }
    }

    if (incompleteCharacters.isEmpty) {
      return;
    }

    await LocalNotificationService.instance.showNotification(
      id: 1002,
      title: '이번 주 숙제가 남아 있어요',
      body: '${_characterNames(incompleteCharacters)} 목요일 전에 주간 콘텐츠를 확인해주세요.',
      payload: 'section:scheduler',
    );
    await notificationHistory.markSent(ruleKey);
  }

  bool _isWeeklyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.trim().toLowerCase();
    return cycle == 'weekly' || cycle == 'week' || cycle == '주간';
  }

  String _dateKey(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day';
  }

  String _characterNames(List<NexonCharacterSummary> characters) {
    if (characters.length == 1) {
      return '${characters.first.characterName}님의';
    }
    return '${characters.first.characterName}님 외 ${characters.length - 1}명의';
  }

  void selectSection(AppSection section) {
    if (section != AppSection.dashboard &&
        section != AppSection.character &&
        selectedCharacter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캐릭터를 먼저 선택해주세요.')),
      );
      return;
    }

    setState(() {
      currentSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _AppSidebar(
            currentSection: currentSection,
            selectedCharacter: selectedCharacter,
            onAddCharacter: () => selectSection(AppSection.character),
            onSelectSection: selectSection,
          ),
          Expanded(
            child: _MainPanel(
              currentSection: currentSection,
              selectedCharacter: selectedCharacter,
              selectedCharacters: selectedCharacters,
              schedulerSnapshot: schedulerSnapshot,
              dashboardSnapshots: dashboardSnapshots,
              noticeItems: noticeItems,
              sundayEvent: sundayEvent,
              isLoading: isLoading,
              isSchedulerLoading: isSchedulerLoading,
              isSchedulerRefreshing: isSchedulerRefreshing,
              isNoticeLoading: isNoticeLoading,
              isNoticeRefreshing: isNoticeRefreshing,
              errorMessage: errorMessage,
              schedulerErrorMessage: schedulerErrorMessage,
              noticeErrorMessage: noticeErrorMessage,
              onAddCharacter: openCharacterPicker,
              onRefresh: refreshCurrentSection,
              onTestNotification: showTestNotification,
              onSelectSection: selectSection,
              onSelectCharacter: selectCharacter,
              onDeleteCharacter: deleteCharacter,
              onMoveCharacter: moveCharacter,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.currentSection,
    required this.selectedCharacter,
    required this.onAddCharacter,
    required this.onSelectSection,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final VoidCallback onAddCharacter;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final hasCharacter = selectedCharacter != null;

    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SidebarBrand(),
              const SizedBox(height: 18),
              _SidebarNavItem(
                section: AppSection.dashboard,
                selected: currentSection == AppSection.dashboard,
                enabled: true,
                onPressed: () => onSelectSection(AppSection.dashboard),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _SidebarCharacterButton(
                selectedCharacter: selectedCharacter,
                selected: currentSection == AppSection.character,
                onPressed: onAddCharacter,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Divider(height: 1, color: AppColors.border),
              ),
              for (final section in AppSection.values)
                if (section != AppSection.dashboard &&
                    section != AppSection.character)
                  _SidebarNavItem(
                    section: section,
                    selected: currentSection == section,
                    enabled: hasCharacter,
                    onPressed: () => onSelectSection(section),
                  ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Image.asset(
            'assets/images/app_logo.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '메이플 숙제알리미',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '놓친 숙제, 이제 안 놓치게',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarCharacterButton extends StatelessWidget {
  const _SidebarCharacterButton({
    required this.selectedCharacter,
    required this.selected,
    required this.onPressed,
  });

  final NexonCharacterSummary? selectedCharacter;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final character = selectedCharacter;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.navBorder : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: character == null
                    ? const ColoredBox(
                        color: Color(0xFFFFF4EC),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: AppColors.navAccent,
                        ),
                      )
                    : _WorldImage(character: character, radius: 12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character == null
                          ? '캐릭터 추가'
                          : _displayCharacterName(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      character == null
                          ? '먼저 알림 대상을 선택'
                          : _characterDescription(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.section,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final AppSection section;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.disabled
        : selected
            ? Colors.white
            : AppColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color:
                  selected && enabled ? AppColors.navAccent : AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected && enabled
                    ? AppColors.navAccent
                    : AppColors.navBorder,
              ),
            ),
            child: Text(
              section.label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.currentSection,
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.schedulerSnapshot,
    required this.dashboardSnapshots,
    required this.noticeItems,
    required this.sundayEvent,
    required this.isLoading,
    required this.isSchedulerLoading,
    required this.isSchedulerRefreshing,
    required this.isNoticeLoading,
    required this.isNoticeRefreshing,
    required this.errorMessage,
    required this.schedulerErrorMessage,
    required this.noticeErrorMessage,
    required this.onAddCharacter,
    required this.onRefresh,
    required this.onTestNotification,
    required this.onSelectSection,
    required this.onSelectCharacter,
    required this.onDeleteCharacter,
    required this.onMoveCharacter,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final SchedulerSnapshot? schedulerSnapshot;
  final Map<String, SchedulerSnapshot> dashboardSnapshots;
  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool isLoading;
  final bool isSchedulerLoading;
  final bool isSchedulerRefreshing;
  final bool isNoticeLoading;
  final bool isNoticeRefreshing;
  final String? errorMessage;
  final String? schedulerErrorMessage;
  final String? noticeErrorMessage;
  final VoidCallback onAddCharacter;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTestNotification;
  final ValueChanged<AppSection> onSelectSection;
  final ValueChanged<NexonCharacterSummary> onSelectCharacter;
  final ValueChanged<NexonCharacterSummary> onDeleteCharacter;
  final void Function(NexonCharacterSummary character, int offset)
      onMoveCharacter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  currentSection.label,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (currentSection == AppSection.scheduler ||
                    currentSection == AppSection.events ||
                    currentSection == AppSection.notices ||
                    currentSection == AppSection.sunday) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: '강제 새로고침',
                    child: _RefreshButton(
                      refreshing: currentSection == AppSection.scheduler
                          ? isSchedulerRefreshing
                          : isNoticeRefreshing,
                      enabled: !(currentSection == AppSection.scheduler
                          ? isSchedulerLoading || isSchedulerRefreshing
                          : isNoticeLoading || isNoticeRefreshing),
                      onPressed: () => onRefresh(),
                    ),
                  ),
                ],
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => onTestNotification(),
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: const Text('알림 테스트'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: switch (currentSection) {
                AppSection.dashboard => _DashboardPanel(
                    characters: selectedCharacters,
                    snapshots: dashboardSnapshots,
                  ),
                AppSection.character => _CharacterSelectPanel(
                    selectedCharacter: selectedCharacter,
                    selectedCharacters: selectedCharacters,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onAddCharacter: onAddCharacter,
                    onSelectCharacter: onSelectCharacter,
                    onDeleteCharacter: onDeleteCharacter,
                    onMoveCharacter: onMoveCharacter,
                  ),
                _ => _LockedFeaturePanel(
                    section: currentSection,
                    selectedCharacter: selectedCharacter,
                    schedulerSnapshot: schedulerSnapshot,
                    noticeItems: noticeItems,
                    sundayEvent: sundayEvent,
                    schedulerLoading: isSchedulerLoading,
                    noticeLoading: isNoticeLoading,
                    schedulerErrorMessage: schedulerErrorMessage,
                    noticeErrorMessage: noticeErrorMessage,
                    onSelectSection: onSelectSection,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.refreshing,
    required this.enabled,
    required this.onPressed,
  });

  final bool refreshing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.navAccent,
              ),
            )
          : const Icon(Icons.refresh_rounded),
      color: AppColors.navAccent,
      disabledColor: AppColors.disabled,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({required this.characters, required this.snapshots});

  final List<NexonCharacterSummary> characters;
  final Map<String, SchedulerSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return const _DashboardEmptyState(
        message: '등록된 캐릭터가 없습니다.\n캐릭터 선택에서 알림 대상을 추가해주세요.',
      );
    }

    var weeklyBossClearCount = 0;
    var loadedCharacterCount = 0;
    for (final character in characters) {
      final snapshot = snapshots[character.ocid];
      if (snapshot == null) {
        continue;
      }
      loadedCharacterCount++;
      final weeklyBosses =
          snapshot.bossItems.where(_isDashboardWeeklyBoss).toList();
      weeklyBossClearCount += snapshot.weeklyBossClearCount ??
          weeklyBosses.where((item) => item.done).length;
    }

    final weeklyContentCharacters = <String, List<String>>{};
    for (final character in characters) {
      final snapshot = snapshots[character.ocid];
      if (snapshot == null) {
        continue;
      }
      for (final item in snapshot.weeklyItems) {
        weeklyContentCharacters.putIfAbsent(item.title, () => []);
        final isSuro = _isGuildSuroItem(item);
        final isCompleted = isSuro ? (item.currentCount ?? 0) >= 1 : item.done;
        if (isCompleted) {
          final label = isSuro
              ? '${character.characterName} · ${item.currentCount}점'
              : character.characterName;
          weeklyContentCharacters[item.title]!.add(label);
        }
      }
    }

    final monsterParkUsage = _buildMonsterParkUsage(characters, snapshots);
    final sharedContentUsage = _buildSharedWeeklyContentUsage(
      characters,
      snapshots,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 6, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DashboardSectionTitle(
              title: '주간 보스 현황',
              subtitle: '등록된 캐릭터당 주 12개 · 처치 기록 기준입니다.',
            ),
            const SizedBox(height: 12),
            _AccountBossSummary(
              clearCount: weeklyBossClearCount,
              clearLimit: characters.length * 12,
              loadedCharacterCount: loadedCharacterCount,
              totalCharacterCount: characters.length,
            ),
            const SizedBox(height: 30),
            const _DashboardSectionTitle(
              title: '몬스터파크',
              subtitle: '월드당 일 14회, 캐릭터당 일 7회 제한입니다.',
            ),
            const SizedBox(height: 12),
            _MonsterParkSummary(items: monsterParkUsage),
            const SizedBox(height: 30),
            const _DashboardSectionTitle(
              title: '캐릭터별 진행 현황',
              subtitle: '등록한 캐릭터의 주간 보스와 일일 콘텐츠 완료 수',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 18) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    for (final character in characters)
                      SizedBox(
                        width: cardWidth,
                        child: _CharacterProgressCard(
                          character: character,
                          snapshot: snapshots[character.ocid],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 30),
            const _DashboardSectionTitle(
              title: '주간 콘텐츠 완료 캐릭터',
              subtitle: '주간 제한 콘텐츠를 어느 캐릭터로 완료했는지 확인합니다.',
            ),
            const SizedBox(height: 12),
            _SharedWeeklyContentSummary(items: sharedContentUsage),
            const SizedBox(height: 18),
            _WeeklyContentCharacterList(
              items: weeklyContentCharacters,
              hasSchedulerData: snapshots.isNotEmpty,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  const _DashboardSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AccountBossSummary extends StatelessWidget {
  const _AccountBossSummary({
    required this.clearCount,
    required this.clearLimit,
    required this.loadedCharacterCount,
    required this.totalCharacterCount,
  });

  final int clearCount;
  final int clearLimit;
  final int loadedCharacterCount;
  final int totalCharacterCount;

  @override
  Widget build(BuildContext context) {
    if (loadedCharacterCount == 0) {
      return const _DashboardEmptyState(
        message: '주간 보스 데이터를 아직 불러오지 못했습니다.\n캐릭터의 스케쥴러를 조회하면 현황이 표시됩니다.',
      );
    }

    final count = clearCount;
    final limit = clearLimit;
    final progress = limit == 0 ? 0.0 : (count / limit).clamp(0.0, 1.0);
    final percentage = (progress * 100).round();
    final remaining = (limit - count).clamp(0, limit);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            height: 116,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 12,
                    backgroundColor: AppColors.selected,
                    color: AppColors.navAccent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      '처치 완료',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이번주 처치한 주간 보스',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count / $limit',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '조회된 캐릭터 $loadedCharacterCount / $totalCharacterCount명 · 처치 기록 기준 · 남은 주간 보스 $remaining마리',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _CharacterProgressCard extends StatelessWidget {
  const _CharacterProgressCard(
      {required this.character, required this.snapshot});

  final NexonCharacterSummary character;
  final SchedulerSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _dashboardCardDecoration(),
        child: _DashboardCharacterHeader(
            character: character,
            child: const Text(
              '스케쥴러 데이터가 없습니다.',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            )),
      );
    }

    final weeklyBosses = snapshot!.bossItems
        .where((item) => _isDashboardWeeklyBoss(item))
        .toList();
    final completedBosses = snapshot!.weeklyBossClearCount ??
        weeklyBosses.where((item) => item.done).length;
    final weeklyBossLimit = snapshot!.weeklyBossClearLimit ?? 12;
    final completedDaily =
        snapshot!.dailyItems.where((item) => item.done).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _dashboardCardDecoration(),
      child: _DashboardCharacterHeader(
        character: character,
        child: Row(
          children: [
            Expanded(
              child: _CharacterMetric(
                icon: Icons.shield_outlined,
                label: '주간 보스',
                value: '$completedBosses / $weeklyBossLimit',
              ),
            ),
            Container(width: 1, height: 42, color: AppColors.border),
            Expanded(
              child: _CharacterMetric(
                icon: Icons.today_outlined,
                label: '일일 콘텐츠',
                value: '$completedDaily / ${snapshot!.dailyItems.length}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _dashboardCardDecoration() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    );

class _DashboardCharacterHeader extends StatelessWidget {
  const _DashboardCharacterHeader(
      {required this.character, required this.child});

  final NexonCharacterSummary character;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          character.characterName,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${character.worldName} · Lv.${character.characterLevel ?? '-'}',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        child,
      ],
    );
  }
}

class _CharacterMetric extends StatelessWidget {
  const _CharacterMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.navAccent),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MonsterParkWorldUsage {
  const _MonsterParkWorldUsage({
    required this.worldName,
    required this.totalCount,
    required this.characterCounts,
  });

  final String worldName;
  final int totalCount;
  final List<_MonsterParkCharacterUsage> characterCounts;
}

class _MonsterParkCharacterUsage {
  const _MonsterParkCharacterUsage({
    required this.characterName,
    required this.count,
  });

  final String characterName;
  final int count;
}

List<_MonsterParkWorldUsage> _buildMonsterParkUsage(
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  final grouped = <String, List<_MonsterParkCharacterUsage>>{};
  for (final character in characters) {
    final snapshot = snapshots[character.ocid];
    if (snapshot == null) {
      continue;
    }
    final count = snapshot.dailyItems
        .where(_isMonsterParkItem)
        .fold<int>(0, (sum, item) => sum + (item.currentCount ?? 0));
    if (!snapshot.dailyItems.any(_isMonsterParkItem)) {
      continue;
    }
    grouped.putIfAbsent(character.worldName, () => []).add(
          _MonsterParkCharacterUsage(
            characterName: character.characterName,
            count: count,
          ),
        );
  }
  return grouped.entries
      .map(
        (entry) => _MonsterParkWorldUsage(
          worldName: entry.key,
          totalCount: entry.value.fold(0, (sum, item) => sum + item.count),
          characterCounts: entry.value,
        ),
      )
      .toList();
}

bool _isMonsterParkItem(SchedulerItemSummary item) {
  return item.title.replaceAll(' ', '').contains('몬스터파크');
}

class _MonsterParkSummary extends StatelessWidget {
  const _MonsterParkSummary({required this.items});

  final List<_MonsterParkWorldUsage> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _DashboardEmptyState(
        message: '몬스터파크 데이터를 아직 불러오지 못했습니다.',
      );
    }

    return Column(
      children: [
        for (final item in items)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: _dashboardCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.worldName,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${item.totalCount} / 14',
                      style: const TextStyle(
                        color: AppColors.navAccent,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final character in item.characterCounts)
                      _MonsterParkCharacterChip(character: character),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonsterParkCharacterChip extends StatelessWidget {
  const _MonsterParkCharacterChip({required this.character});

  final _MonsterParkCharacterUsage character;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.selected,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${character.characterName} ${character.count} / 7',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SharedWeeklyContentRule {
  const _SharedWeeklyContentRule({
    required this.title,
    required this.scope,
    required this.limit,
    required this.matches,
  });

  final String title;
  final String scope;
  final int limit;
  final bool Function(SchedulerItemSummary item) matches;
}

class _SharedWeeklyContentUsage {
  const _SharedWeeklyContentUsage({
    required this.rule,
    required this.characterNames,
  });

  final _SharedWeeklyContentRule rule;
  final List<String> characterNames;
}

final _sharedWeeklyContentRules = <_SharedWeeklyContentRule>[
  _SharedWeeklyContentRule(
    title: '에픽 던전',
    scope: '넥슨 ID',
    limit: 3,
    matches: (item) => item.title.replaceAll(' ', '').contains('에픽던전'),
  ),
  _SharedWeeklyContentRule(
    title: '익스트림 몬스터파커',
    scope: '월드',
    limit: 2,
    matches: (item) => item.title.replaceAll(' ', '').contains('익스트림몬스터파커'),
  ),
];

List<_SharedWeeklyContentUsage> _buildSharedWeeklyContentUsage(
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  return [
    for (final rule in _sharedWeeklyContentRules)
      _SharedWeeklyContentUsage(
        rule: rule,
        characterNames: [
          for (final character in characters)
            if ((snapshots[character.ocid]?.weeklyItems ?? const [])
                .any((item) => rule.matches(item) && item.done))
              character.characterName,
        ],
      ),
  ];
}

class _SharedWeeklyContentSummary extends StatelessWidget {
  const _SharedWeeklyContentSummary({required this.items});

  final List<_SharedWeeklyContentUsage> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _dashboardCardDecoration(),
      child: Column(
        children: [
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 19,
                    color: AppColors.navAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${item.rule.title} · ${item.rule.scope}당 주 ${item.rule.limit}캐릭터',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    item.characterNames.isEmpty
                        ? '완료 캐릭터 없음'
                        : '${item.characterNames.length} / ${item.rule.limit}',
                    style: TextStyle(
                      color: item.characterNames.isEmpty
                          ? AppColors.muted
                          : AppColors.navAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (item.characterNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(49, 0, 20, 15),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.characterNames.join(', '),
                    style: const TextStyle(
                      color: AppColors.navAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (item != items.last)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _WeeklyContentCharacterList extends StatelessWidget {
  const _WeeklyContentCharacterList({
    required this.items,
    required this.hasSchedulerData,
  });

  final Map<String, List<String>> items;
  final bool hasSchedulerData;

  @override
  Widget build(BuildContext context) {
    if (!hasSchedulerData) {
      return const _DashboardEmptyState(
        message: '스케쥴러를 조회한 캐릭터가 없습니다.',
      );
    }
    if (items.isEmpty) {
      return const _DashboardEmptyState(
        message: '등록된 주간 콘텐츠가 없습니다.',
      );
    }

    return Container(
      decoration: _dashboardCardDecoration(),
      child: Column(
        children: [
          for (final entry in items.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 19,
                    color: AppColors.navAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (entry.value.isEmpty)
                    const Text(
                      '완료 캐릭터 없음',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.completionTag,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.completionTagBorder,
                            ),
                          ),
                          child: Text(
                            entry.value.join(', '),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.completionTagText,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (entry.key != items.entries.last.key)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: _dashboardCardDecoration(),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

bool _isDashboardWeeklyBoss(SchedulerItemSummary item) {
  final cycle = item.cycle.trim().toLowerCase();
  return cycle == 'weekly' || cycle == 'week' || cycle == '주간';
}

bool _isGuildSuroItem(SchedulerItemSummary item) {
  return item.title.replaceAll(' ', '').contains('지하수로');
}

class _CharacterSelectPanel extends StatelessWidget {
  const _CharacterSelectPanel({
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.isLoading,
    required this.errorMessage,
    required this.onAddCharacter,
    required this.onSelectCharacter,
    required this.onDeleteCharacter,
    required this.onMoveCharacter,
  });

  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onAddCharacter;
  final ValueChanged<NexonCharacterSummary> onSelectCharacter;
  final ValueChanged<NexonCharacterSummary> onDeleteCharacter;
  final void Function(NexonCharacterSummary character, int offset)
      onMoveCharacter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1100 ? 5 : 4;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errorMessage != null) ...[
              _InlineError(message: errorMessage!),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: GridView.count(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    children: [
                      for (final character in selectedCharacters)
                        _CharacterCard(
                          character: character,
                          selected: _isSameCharacter(
                            character,
                            selectedCharacter,
                          ),
                          canMoveBefore:
                              selectedCharacters.indexOf(character) > 0,
                          canMoveAfter: selectedCharacters.indexOf(character) <
                              selectedCharacters.length - 1,
                          onTap: () => onSelectCharacter(character),
                          onDelete: () => onDeleteCharacter(character),
                          onMoveBefore: () => onMoveCharacter(character, -1),
                          onMoveAfter: () => onMoveCharacter(character, 1),
                        ),
                      _AddCharacterCard(
                        loading: isLoading,
                        onTap: isLoading ? null : onAddCharacter,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1D6CC)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB85F47),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _LockedFeaturePanel extends StatelessWidget {
  const _LockedFeaturePanel({
    required this.section,
    required this.selectedCharacter,
    required this.schedulerSnapshot,
    required this.noticeItems,
    required this.sundayEvent,
    required this.schedulerLoading,
    required this.noticeLoading,
    required this.schedulerErrorMessage,
    required this.noticeErrorMessage,
    required this.onSelectSection,
  });

  final AppSection section;
  final NexonCharacterSummary? selectedCharacter;
  final SchedulerSnapshot? schedulerSnapshot;
  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool schedulerLoading;
  final bool noticeLoading;
  final String? schedulerErrorMessage;
  final String? noticeErrorMessage;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    if (selectedCharacter == null) {
      return const _BlockedPanel();
    }

    if (section != AppSection.scheduler) {
      return switch (section) {
        AppSection.events => _EventOverviewPanel(
            items: noticeItems
                .where((item) => item.noticeType == 'event')
                .toList(),
            loading: noticeLoading,
            errorMessage: noticeErrorMessage,
            onOpenSunday: () => onSelectSection(AppSection.sunday),
          ),
        AppSection.notices => _NoticeOverviewPanel(
            items: noticeItems
                .where((item) => item.noticeType != 'event')
                .toList(),
            loading: noticeLoading,
            errorMessage: noticeErrorMessage,
          ),
        AppSection.sunday => _SundayOverviewPanel(event: sundayEvent),
        AppSection.dashboard ||
        AppSection.character ||
        AppSection.scheduler =>
          const SizedBox.shrink(),
      };
    }

    return _SchedulerOverviewPanel(
      snapshot: schedulerSnapshot,
      loading: schedulerLoading,
      errorMessage: schedulerErrorMessage,
    );
  }
}

class _SchedulerOverviewPanel extends StatelessWidget {
  const _SchedulerOverviewPanel({
    required this.snapshot,
    required this.loading,
    required this.errorMessage,
  });

  final SchedulerSnapshot? snapshot;
  final bool loading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (errorMessage != null) {
      return _InlineError(message: errorMessage!);
    }

    final data = snapshot;
    if (data == null) {
      return const _BlockedPanel();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final left = Column(
          children: [
            _SchedulerCard(
              title: '일일 콘텐츠',
              items: data.dailyItems,
              emptyMessage: '오늘 접속 기록이 아직 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
            ),
            const SizedBox(height: 20),
            _SchedulerCard(
              title: '주간 콘텐츠',
              items: data.weeklyItems,
              emptyMessage: '이번주에 완료한 주간 콘텐츠가 없습니다.\n게임에 접속하여 주간 퀘스트를 완료 해주세요.',
            ),
          ],
        );
        final right = Column(
          children: [
            _BossSchedulerCard(title: '보스 콘텐츠', items: data.bossItems),
          ],
        );

        if (compact) {
          return SingleChildScrollView(
            child: Column(
              children: [
                _SchedulerCard(
                  title: '일일 콘텐츠',
                  items: data.dailyItems,
                  emptyMessage: '오늘 접속 기록이 아직 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
                ),
                const SizedBox(height: 20),
                _SchedulerCard(
                  title: '주간 콘텐츠',
                  items: data.weeklyItems,
                  emptyMessage:
                      '이번주에 완료한 주간 콘텐츠가 없습니다.\n게임에 접속하여 주간 퀘스트를 완료 해주세요.',
                ),
                const SizedBox(height: 20),
                _BossSchedulerCard(title: '보스 콘텐츠', items: data.bossItems),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 20),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }
}

class _SchedulerCard extends StatelessWidget {
  const _SchedulerCard({
    required this.title,
    required this.items,
    this.emptyMessage = '아직 조회된 숙제 정보가 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
  });

  final String title;
  final List<SchedulerItemSummary> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: items.isEmpty
                ? Text(
                    emptyMessage,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  )
                : Column(
                    children: items
                        .map((item) => _SchedulerItemRow(item: item))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BossSchedulerCard extends StatelessWidget {
  const _BossSchedulerCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<SchedulerItemSummary> items;

  @override
  Widget build(BuildContext context) {
    final groupedItems = {
      'DAILY': items.where(_isDailyBoss).toList(),
      'WEEKLY': items.where(_isWeeklyBoss).toList(),
      'MONTHLY': items.where(_isMonthlyBoss).toList(),
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: items.isEmpty
                ? const Text(
                    '아직 이번주에 처치한 보스가 없습니다.\n게임에 접속하여 보스를 처치해주세요.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  )
                : Column(
                    children: groupedItems.entries
                        .where((entry) => entry.value.isNotEmpty)
                        .map(
                          (entry) => _BossCycleSection(
                            title: entry.key,
                            items: entry.value,
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  static bool _isDailyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('daily') || cycle.contains('day');
  }

  static bool _isWeeklyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('weekly') || cycle.contains('week');
  }

  static bool _isMonthlyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('monthly') || cycle.contains('month');
  }
}

class _BossCycleSection extends StatelessWidget {
  const _BossCycleSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<SchedulerItemSummary> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFA7B0B7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ...items.map((item) => _SchedulerItemRow(item: item)),
        ],
      ),
    );
  }
}

class _SchedulerItemRow extends StatelessWidget {
  const _SchedulerItemRow({required this.item});

  final SchedulerItemSummary item;

  @override
  Widget build(BuildContext context) {
    final color = item.done ? const Color(0xFFFFFFFF) : const Color(0xFF111111);
    final background = item.done ? const Color(0xFF7A818A) : AppColors.surface;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Row(
        children: [
          if (item.difficulty.isNotEmpty) ...[
            _BossDifficultyBadge(difficulty: item.difficulty),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (item.meta.isNotEmpty)
            Text(
              item.meta,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _BossDifficultyBadge extends StatelessWidget {
  const _BossDifficultyBadge({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final label = difficulty.toUpperCase();
    final normalized = difficulty.toLowerCase();
    final isChaos = normalized.contains('chaos');
    final isExtreme = normalized.contains('extreme');
    const chaosGold = Color(0xFFD9B75B);
    const extremeRed = Color(0xFFD84E66);
    final background = isExtreme
        ? const Color(0xFF2D252B)
        : normalized.contains('hard')
            ? const Color(0xFF965271)
            : normalized.contains('normal')
                ? const Color(0xFF436F86)
                : const Color(0xFF3E4147);
    final borderColor = isExtreme
        ? extremeRed
        : isChaos
            ? chaosGold
            : null;
    final textShadowColor = isExtreme
        ? extremeRed
        : isChaos
            ? chaosGold
            : null;

    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            shadows: textShadowColor == null
                ? null
                : [
                    Shadow(
                      color: textShadowColor,
                      offset: const Offset(0, 0),
                      blurRadius: 1,
                    ),
                  ]),
      ),
    );
  }
}

class _EventOverviewPanel extends StatelessWidget {
  const _EventOverviewPanel({
    required this.items,
    required this.loading,
    required this.errorMessage,
    required this.onOpenSunday,
  });

  final List<NoticeItemSummary> items;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onOpenSunday;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (errorMessage != null) {
      return _InlineError(message: errorMessage!);
    }

    if (items.isEmpty) {
      return const _EmptyDataPanel(message: '진행중인 이벤트가 없어요.');
    }

    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 1180 ? 3 : 2,
      childAspectRatio: 1.06,
      crossAxisSpacing: 24,
      mainAxisSpacing: 30,
      children: items
          .map((item) => _InfoCard(
                title: item.title,
                meta: item.eventPeriodText.isEmpty
                    ? item.label
                    : item.eventPeriodText,
                thumbnail: item.thumbnail,
                link: item.link,
                onTap: _isSundayMapleEvent(item) ? onOpenSunday : null,
              ))
          .toList(),
    );
  }
}

class _NoticeOverviewPanel extends StatefulWidget {
  const _NoticeOverviewPanel({
    required this.items,
    required this.loading,
    required this.errorMessage,
  });

  final List<NoticeItemSummary> items;
  final bool loading;
  final String? errorMessage;

  @override
  State<_NoticeOverviewPanel> createState() => _NoticeOverviewPanelState();
}

enum NoticeCategory {
  all('전체', null),
  notice('공지', 'notice'),
  maintenance('점검', 'maintenance'),
  update('업데이트', 'update'),
  cashshop('캐시샵', 'cashshop');

  const NoticeCategory(this.label, this.type);

  final String label;
  final String? type;
}

class _NoticeOverviewPanelState extends State<_NoticeOverviewPanel> {
  var selectedCategory = NoticeCategory.all;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (widget.errorMessage != null) {
      return _InlineError(message: widget.errorMessage!);
    }

    final filteredItems = selectedCategory.type == null
        ? widget.items
        : widget.items
            .where((item) => item.displayType == selectedCategory.type)
            .toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _NoticeTabBar(
            selectedCategory: selectedCategory,
            onChanged: (category) {
              setState(() {
                selectedCategory = category;
              });
            },
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(
                    child: Text(
                      '공지사항이 없어요.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : selectedCategory == NoticeCategory.cashshop
                    ? _CashshopCardGrid(items: filteredItems)
                    : ListView(
                        children: filteredItems
                            .map(
                              (item) => _NoticeListRow(
                                tag: item.label,
                                title: item.title,
                                date: item.dateText,
                                link: item.link,
                              ),
                            )
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CashshopCardGrid extends StatelessWidget {
  const _CashshopCardGrid({required this.items});

  final List<NoticeItemSummary> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;

        return GridView.count(
          padding: const EdgeInsets.all(22),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.55,
          crossAxisSpacing: 24,
          mainAxisSpacing: 26,
          children: items
              .map(
                (item) => _CashshopCard(
                  title: item.title,
                  meta: item.cashshopPeriodText,
                  thumbnail: item.thumbnail,
                  link: item.link,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _CashshopCard extends StatelessWidget {
  const _CashshopCard({
    required this.title,
    required this.meta,
    required this.thumbnail,
    required this.link,
  });

  final String title;
  final String meta;
  final String thumbnail;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: AspectRatio(
              aspectRatio: 10 / 3,
              child: _LinkTapArea(
                link: link,
                child: _EventThumbnail(thumbnail: thumbnail),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _LinkTapArea(
                  link: link,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                meta,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDataPanel extends StatelessWidget {
  const _EmptyDataPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SundayOverviewPanel extends StatelessWidget {
  const _SundayOverviewPanel({required this.event});

  final NoticeItemSummary? event;

  @override
  Widget build(BuildContext context) {
    final sundayEvent = event;

    if (sundayEvent != null) {
      if (sundayEvent.contentImageUrls.isNotEmpty) {
        return _SundayContentPanel(event: sundayEvent);
      }

      if (sundayEvent.thumbnail.isEmpty) {
        return const _EmptyDataPanel(
          message: '이번주 썬데이 메이플 공지가 아직 없습니다',
        );
      }

      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _InfoCard(
            title: sundayEvent.title,
            meta: sundayEvent.eventPeriodText,
            thumbnail: sundayEvent.thumbnail,
            link: sundayEvent.link,
          ),
        ),
      );
    }

    return const _EmptyDataPanel(
      message: '아직 저장된 이번주 썬데이 정보가 없어요.\n썬데이 메이플 이벤트가 등록되면 자동으로 업데이트됩니다.',
    );
  }
}

class _SundayContentPanel extends StatelessWidget {
  const _SundayContentPanel({required this.event});

  final NoticeItemSummary event;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: event.contentImageUrls.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final imageUrl = event.contentImageUrls[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _LinkTapArea(
              link: event.link,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _InfoCard(
                      title: event.title,
                      meta: event.eventPeriodText,
                      thumbnail: event.thumbnail,
                      link: event.link,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

NoticeItemSummary? _findSpecialSundayEvent(List<NoticeItemSummary> items) {
  for (final item in items) {
    if (_isSundayMapleEvent(item)) {
      return item;
    }
  }
  return null;
}

bool _isSundayMapleEvent(NoticeItemSummary item) {
  return item.noticeType == 'event' &&
      (item.title == '스페셜 썬데이 메이플' || item.title == '썬데이 메이플');
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.meta,
    required this.thumbnail,
    required this.link,
    this.onTap,
  });

  final String title;
  final String meta;
  final String thumbnail;
  final String link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 124,
            child: _LinkTapArea(
              link: link,
              onTap: onTap,
              child: _EventThumbnail(thumbnail: thumbnail),
            ),
          ),
          SizedBox(
            height: 96,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _LinkTapArea(
                  link: link,
                  onTap: onTap,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                meta,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventThumbnail extends StatelessWidget {
  const _EventThumbnail({required this.thumbnail});

  final String thumbnail;

  @override
  Widget build(BuildContext context) {
    if (thumbnail.isEmpty) {
      return Container(
        color: const Color(0xFFF0F2F6),
        alignment: Alignment.center,
        child: const Text(
          'EVENT',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.surface,
      child: Image.network(
        thumbnail,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFFF0F2F6),
            alignment: Alignment.center,
            child: const Text(
              'EVENT',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LinkTapArea extends StatelessWidget {
  const _LinkTapArea({
    required this.link,
    required this.child,
    this.onTap,
  });

  final String link;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final handler =
        onTap ?? (link.trim().isEmpty ? null : () => _openExternalUrl(link));
    if (handler == null) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handler,
        child: child,
      ),
    );
  }
}

Future<void> _openExternalUrl(String link) async {
  final url = link.trim();
  if (url.isEmpty) {
    return;
  }

  await Process.start(
    'rundll32.exe',
    ['url.dll,FileProtocolHandler', url],
  );
}

class _NoticeTabBar extends StatelessWidget {
  const _NoticeTabBar({
    required this.selectedCategory,
    required this.onChanged,
  });

  final NoticeCategory selectedCategory;
  final ValueChanged<NoticeCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: NoticeCategory.values
          .map(
            (category) => _NoticeTab(
              label: category.label,
              active: selectedCategory == category,
              onTap: () => onChanged(category),
            ),
          )
          .toList(),
    );
  }
}

class _NoticeTab extends StatelessWidget {
  const _NoticeTab({
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
              bottom: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeListRow extends StatelessWidget {
  const _NoticeListRow({
    required this.tag,
    required this.title,
    required this.date,
    required this.link,
  });

  final String tag;
  final String title;
  final String date;
  final String link;

  @override
  Widget build(BuildContext context) {
    final tagColor = switch (tag) {
      '점검' => const Color(0xFF55B3BF),
      '업데이트' => const Color(0xFFFFEEFF),
      _ => AppColors.primary,
    };
    final tagBorderColor = switch (tag) {
      '업데이트' => const Color(0xFFFF9EF4),
      _ => tagColor,
    };
    final tagTextColor = switch (tag) {
      '업데이트' => const Color(0xFFE24AD7),
      _ => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tagBorderColor),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: tagTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _LinkTapArea(
              link: link,
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Text(
            date,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: AppColors.disabled, size: 28),
          SizedBox(height: 12),
          Text(
            '캐릭터 선택이 필요해요.',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '왼쪽의 캐릭터 추가를 눌러 알림 대상 캐릭터를 먼저 선택해주세요.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.selected,
    required this.canMoveBefore,
    required this.canMoveAfter,
    required this.onTap,
    required this.onDelete,
    required this.onMoveBefore,
    required this.onMoveAfter,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final bool canMoveBefore;
  final bool canMoveAfter;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMoveBefore;
  final VoidCallback onMoveAfter;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF4EC) : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: 2,
            color: selected ? AppColors.navBorder : AppColors.softBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _CharacterImage(character: character, radius: 12),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _CharacterCardMenu(
                      canMoveBefore: canMoveBefore,
                      canMoveAfter: canMoveAfter,
                      onDelete: onDelete,
                      onMoveBefore: onMoveBefore,
                      onMoveAfter: onMoveAfter,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayCharacterName(character),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.navAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '선택됨',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              _characterDescription(character),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterCardMenu extends StatelessWidget {
  const _CharacterCardMenu({
    required this.canMoveBefore,
    required this.canMoveAfter,
    required this.onDelete,
    required this.onMoveBefore,
    required this.onMoveAfter,
  });

  final bool canMoveBefore;
  final bool canMoveAfter;
  final VoidCallback onDelete;
  final VoidCallback onMoveBefore;
  final VoidCallback onMoveAfter;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '캐릭터 관리',
      color: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'moveBefore') {
          onMoveBefore();
        } else if (value == 'moveAfter') {
          onMoveAfter();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'moveBefore',
          enabled: canMoveBefore,
          child: const Text('앞으로 이동'),
        ),
        PopupMenuItem(
          value: 'moveAfter',
          enabled: canMoveAfter,
          child: const Text('뒤로 이동'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('삭제'),
        ),
      ],
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xEBFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: AppColors.text,
          size: 18,
        ),
      ),
    );
  }
}

class _AddCharacterCard extends StatelessWidget {
  const _AddCharacterCard({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.navBorder, width: 2),
        ),
        child: Center(
          child: loading
              ? const CircularProgressIndicator(color: AppColors.navAccent)
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+',
                      style: TextStyle(
                        color: AppColors.navAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '캐릭터 추가',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CharacterPickerDialog extends StatefulWidget {
  const _CharacterPickerDialog({
    required this.characters,
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.loadCharacterBasic,
  });

  final List<NexonCharacterSummary> characters;
  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final Future<NexonCharacterSummary> Function(NexonCharacterSummary character)
      loadCharacterBasic;

  @override
  State<_CharacterPickerDialog> createState() => _CharacterPickerDialogState();
}

class _CharacterPickerDialogState extends State<_CharacterPickerDialog> {
  late List<NexonCharacterSummary> characters;

  @override
  void initState() {
    super.initState();
    characters = [...widget.characters];
    unawaited(_loadCharacterImages());
  }

  Future<void> _loadCharacterImages() async {
    const batchSize = 4;
    for (var start = 0; start < characters.length; start += batchSize) {
      final end = start + batchSize > characters.length
          ? characters.length
          : start + batchSize;
      final batch = characters.sublist(start, end);
      final details = await Future.wait(
        batch.map(widget.loadCharacterBasic),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        for (final detail in details) {
          final index = characters.indexWhere(
            (character) => character.ocid == detail.ocid,
          );
          if (index != -1) {
            characters[index] = characters[index].merge(detail);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: dialogSize.height * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '캐릭터 선택',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    '불러온 캐릭터가 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = constraints.maxWidth >= 740
                          ? 4
                          : constraints.maxWidth >= 520
                              ? 3
                              : 2;
                      return GridView.builder(
                        itemCount: characters.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columnCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemBuilder: (context, index) {
                          final character = characters[index];
                          final selected = _isSameCharacter(
                            character,
                            widget.selectedCharacter,
                          );
                          final added = widget.selectedCharacters.any(
                            (selectedCharacter) =>
                                _isSameCharacter(character, selectedCharacter),
                          );

                          return _CharacterPickerCard(
                            character: character,
                            selected: selected,
                            added: added,
                            onTap: () => Navigator.of(context).pop(character),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterPickerCard extends StatelessWidget {
  const _CharacterPickerCard({
    required this.character,
    required this.selected,
    required this.added,
    required this.onTap,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF4EC) : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? AppColors.navBorder : AppColors.softBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _CharacterImage(character: character, radius: 8),
                      ),
                    ),
                    if (added)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.navAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _displayCharacterName(character),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _characterDescription(character),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterImage extends StatelessWidget {
  const _CharacterImage({
    required this.character,
    required this.radius,
  });

  final NexonCharacterSummary character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = character.characterImage;
    final image = imageUrl.isEmpty
        ? _CharacterImageFallback(character: character)
        : Image.network(
            imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) =>
                _CharacterImageFallback(character: character),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Transform.scale(
              scale: 1.45,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterImageFallback extends StatelessWidget {
  const _CharacterImageFallback({required this.character});

  final NexonCharacterSummary character;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F2F6),
      alignment: Alignment.center,
      child: Text(
        character.characterName.isEmpty
            ? '?'
            : character.characterName.characters.first,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WorldImage extends StatelessWidget {
  const _WorldImage({
    required this.character,
    required this.radius,
  });

  final NexonCharacterSummary character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final assetPath = _worldImageAsset(character.worldName);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: const Color(0xFFFFFBF2),
        child: assetPath.isEmpty
            ? _CharacterImageFallback(character: character)
            : Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _CharacterImageFallback(character: character),
                ),
              ),
      ),
    );
  }
}

String _worldImageAsset(String worldName) {
  final normalized = worldName.replaceAll(' ', '');
  const worlds = [
    '스카니아',
    '베라',
    '루나',
    '제니스',
    '크로아',
    '유니온',
    '엘리시움',
    '이노시스',
    '레드',
    '오로라',
    '아케인',
    '노바',
    '챌린저스',
    '에오스',
    '헬리오스',
  ];

  for (final world in worlds) {
    if (normalized.contains(world)) {
      return 'assets/images/worlds/$world.png';
    }
  }
  return '';
}

String _displayCharacterName(NexonCharacterSummary character) {
  return character.characterName.isEmpty ? '이름 없음' : character.characterName;
}

String _characterDescription(NexonCharacterSummary character) {
  return [
    character.worldName,
    character.characterClass,
    if (character.characterLevel != null) 'Lv.${character.characterLevel}',
  ].where((value) => value.isNotEmpty).join(' · ');
}

bool _isSameCharacter(
  NexonCharacterSummary character,
  NexonCharacterSummary? other,
) {
  if (other == null) {
    return false;
  }

  if (character.ocid.isNotEmpty && other.ocid.isNotEmpty) {
    return character.ocid == other.ocid;
  }

  return character.characterName == other.characterName &&
      character.worldName == other.worldName;
}
