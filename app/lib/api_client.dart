import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.baseUrl = 'https://maple-daily-log.onrender.com',
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String baseUrl;

  Future<List<NexonCharacterSummary>> fetchNexonCharacters() async {
    final response =
        await _httpClient.get(Uri.parse('$baseUrl/api/nexon/characters'));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('캐릭터 목록을 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final characters = _extractCharacterItems(decoded);

    return characters.map(NexonCharacterSummary.fromJson).toList();
  }

  Future<NexonCharacterSummary> fetchCharacterBasic(
    NexonCharacterSummary character,
  ) async {
    if (character.ocid.isEmpty) {
      return character;
    }

    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/api/nexon/characters/${character.ocid}/basic'),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return character;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return character;
      }

      return character.merge(NexonCharacterSummary.fromJson(decoded));
    } catch (_) {
      return character;
    }
  }

  Future<SchedulerSnapshot> fetchScheduler(
    String ocid, {
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/nexon/scheduler/$ocid').replace(
      queryParameters: forceRefresh ? const {'refresh': '1'} : null,
    );
    final response = await _httpClient.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('스케쥴러 정보를 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('스케쥴러 응답 형식이 올바르지 않습니다.');
    }

    return SchedulerSnapshot.fromJson(decoded);
  }

  Future<List<NoticeItemSummary>> fetchCurrentNotices({
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notices/current').replace(
      queryParameters: forceRefresh ? const {'refresh': '1'} : null,
    );
    final response = await _httpClient.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('공지사항 정보를 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final items = decoded is Map<String, dynamic> ? decoded['items'] : decoded;
    if (items is! List) {
      return const [];
    }

    return items
        .whereType<Map>()
        .map((item) => NoticeItemSummary.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<NoticeItemSummary?> fetchLatestSundayEvent({
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notices/latest-sunday').replace(
      queryParameters: forceRefresh ? const {'refresh': '1'} : null,
    );
    final response = await _httpClient.get(uri);

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('최근 썬데이 메이플 정보를 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      return null;
    }
    return NoticeItemSummary.fromJson(Map<String, dynamic>.from(decoded));
  }

  List<Map<String, dynamic>> _extractCharacterItems(Object? decoded) {
    if (decoded is List) {
      return _flattenCharacterMaps(decoded);
    }

    if (decoded is Map) {
      for (final key in ['characters', 'character_list', 'items', 'data']) {
        final value = decoded[key];
        if (value is List) {
          return _flattenCharacterMaps(value);
        }
      }

      final accountList = decoded['account_list'];
      if (accountList is List) {
        return _flattenAccountCharacters(accountList);
      }
    }

    return [];
  }

  List<Map<String, dynamic>> _flattenCharacterMaps(List<dynamic> items) {
    final characters = <Map<String, dynamic>>[];

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);
      final nestedCharacters = map['character_list'];
      if (nestedCharacters is List) {
        characters.addAll(_flattenCharacterMaps(nestedCharacters));
      } else {
        characters.add(map);
      }
    }

    return characters;
  }

  List<Map<String, dynamic>> _flattenAccountCharacters(List<dynamic> accounts) {
    final characters = <Map<String, dynamic>>[];

    for (final account in accounts) {
      if (account is! Map) {
        continue;
      }

      final characterList = account['character_list'];
      if (characterList is List) {
        for (final character in characterList) {
          if (character is Map) {
            characters.add(Map<String, dynamic>.from(character));
          }
        }
      }
    }

    return characters;
  }
}

class NexonCharacterSummary {
  const NexonCharacterSummary({
    required this.ocid,
    required this.characterName,
    required this.worldName,
    required this.characterClass,
    required this.characterLevel,
    required this.characterImage,
  });

  final String ocid;
  final String characterName;
  final String worldName;
  final String characterClass;
  final int? characterLevel;
  final String characterImage;

  factory NexonCharacterSummary.fromJson(Map<String, dynamic> json) {
    return NexonCharacterSummary(
      ocid: _readString(json, ['ocid']),
      characterName:
          _readString(json, ['character_name', 'characterName', 'name']),
      worldName: _readString(json, ['world_name', 'worldName', 'world']),
      characterClass:
          _readString(json, ['character_class', 'characterClass', 'class']),
      characterLevel:
          _readInt(json, ['character_level', 'characterLevel', 'level']),
      characterImage:
          _readString(json, ['character_image', 'characterImage', 'image']),
    );
  }

  NexonCharacterSummary merge(NexonCharacterSummary other) {
    return NexonCharacterSummary(
      ocid: other.ocid.isNotEmpty ? other.ocid : ocid,
      characterName:
          other.characterName.isNotEmpty ? other.characterName : characterName,
      worldName: other.worldName.isNotEmpty ? other.worldName : worldName,
      characterClass: other.characterClass.isNotEmpty
          ? other.characterClass
          : characterClass,
      characterLevel: other.characterLevel ?? characterLevel,
      characterImage: other.characterImage.isNotEmpty
          ? other.characterImage
          : characterImage,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'ocid': ocid,
      'characterName': characterName,
      'worldName': worldName,
      'characterClass': characterClass,
      'characterLevel': characterLevel,
      'characterImage': characterImage,
    };
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) {
        return value.toString();
      }
    }
    return '';
  }

  static int? _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is String) {
        return int.tryParse(value);
      }
    }
    return null;
  }
}

class SchedulerSnapshot {
  const SchedulerSnapshot({
    required this.dailyItems,
    required this.weeklyItems,
    required this.bossItems,
    this.weeklyBossClearCount,
    this.weeklyBossClearLimit,
  });

  final List<SchedulerItemSummary> dailyItems;
  final List<SchedulerItemSummary> weeklyItems;
  final List<SchedulerItemSummary> bossItems;
  final int? weeklyBossClearCount;
  final int? weeklyBossClearLimit;

  bool get hasDailyItems => dailyItems.isNotEmpty;
  bool get hasWeeklyItems => weeklyItems.isNotEmpty;
  bool get hasBossItems => bossItems.isNotEmpty;

  SchedulerSnapshot withCachedEmptySections(SchedulerSnapshot cached) {
    return SchedulerSnapshot(
      dailyItems: dailyItems.isEmpty
          ? cached.dailyItems
              .map((item) => item.asUnfinished(resetProgress: true))
              .toList()
          : dailyItems,
      weeklyItems: weeklyItems.isEmpty
          ? cached.weeklyItems.map((item) => item.asUnfinished()).toList()
          : weeklyItems,
      bossItems: _mergeMissingBossCycles(cached),
      weeklyBossClearCount: weeklyBossClearCount ?? cached.weeklyBossClearCount,
      weeklyBossClearLimit: weeklyBossClearLimit ?? cached.weeklyBossClearLimit,
    );
  }

  SchedulerSnapshot asUnfinishedWithoutDailyLogin() {
    return SchedulerSnapshot(
      dailyItems: dailyItems,
      weeklyItems: weeklyItems
          .map((item) => item.asUnfinished(resetProgress: true))
          .toList(),
      bossItems: bossItems
          .map((item) => item.asUnfinished(resetProgress: true))
          .toList(),
      weeklyBossClearCount: 0,
      weeklyBossClearLimit: weeklyBossClearLimit,
    );
  }

  List<SchedulerItemSummary> _mergeMissingBossCycles(
    SchedulerSnapshot cached,
  ) {
    final mergedItems = [...bossItems];
    for (final cycle in const ['daily', 'weekly', 'monthly']) {
      final hasCurrentCycle = mergedItems.any(
        (item) => _matchesBossCycle(item, cycle),
      );
      if (!hasCurrentCycle) {
        mergedItems.addAll(
          cached.bossItems.where((item) => _matchesBossCycle(item, cycle)).map(
                (item) => item.asUnfinished(
                  resetProgress: cycle == 'daily',
                ),
              ),
        );
      }
    }
    return mergedItems;
  }

  static bool _matchesBossCycle(SchedulerItemSummary item, String cycle) {
    final normalized = item.cycle.trim().toLowerCase();
    return switch (cycle) {
      'daily' => normalized == 'daily' ||
          normalized == 'day' ||
          normalized == '일간' ||
          normalized == '일일',
      'weekly' =>
        normalized == 'weekly' || normalized == 'week' || normalized == '주간',
      'monthly' =>
        normalized == 'monthly' || normalized == 'month' || normalized == '월간',
      _ => false,
    };
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'dailyItems': dailyItems.map((item) => item.toCacheJson()).toList(),
      'weeklyItems': weeklyItems.map((item) => item.toCacheJson()).toList(),
      'bossItems': bossItems.map((item) => item.toCacheJson()).toList(),
      'weeklyBossClearCount': weeklyBossClearCount,
      'weeklyBossClearLimit': weeklyBossClearLimit,
    };
  }

  factory SchedulerSnapshot.fromCacheJson(Map<String, dynamic> json) {
    List<SchedulerItemSummary> readItems(String key) {
      final value = json[key];
      if (value is! List) {
        return const [];
      }
      return value
          .whereType<Map>()
          .map((item) => SchedulerItemSummary.fromCacheJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    }

    return SchedulerSnapshot(
      dailyItems: readItems('dailyItems'),
      weeklyItems: readItems('weeklyItems'),
      bossItems: readItems('bossItems'),
      weeklyBossClearCount: _readInt(json, ['weeklyBossClearCount']),
      weeklyBossClearLimit: _readInt(json, ['weeklyBossClearLimit']),
    );
  }

  factory SchedulerSnapshot.fromJson(Map<String, dynamic> json) {
    return SchedulerSnapshot(
      dailyItems: _readItems(json, [
        'daily_contents',
        'daily_content',
        'daily_contents_info',
        'daily_content_info',
      ]),
      weeklyItems: _readItems(json, [
        'weekly_contents',
        'weekly_content',
        'weekly_contents_info',
        'weekly_content_info',
      ]),
      bossItems: _readItems(json, [
        'boss_contents',
        'boss_content',
        'boss_contents_info',
        'boss_content_info',
      ]),
      weeklyBossClearCount: _readInt(json, [
        'weekly_boss_clear_count',
        'weekly_boss_clear_cnt',
      ]),
      weeklyBossClearLimit: _readInt(json, [
        'weekly_boss_clear_limit',
        'weekly_boss_clear_limit_count',
      ]),
    );
  }

  static int? _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value);
      }
    }
    return null;
  }

  static List<SchedulerItemSummary> _readItems(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where(SchedulerItemSummary.isRegistered)
            .map(SchedulerItemSummary.fromJson)
            .toList();
      }
    }
    return const [];
  }
}

class SchedulerItemSummary {
  const SchedulerItemSummary({
    required this.title,
    required this.meta,
    required this.difficulty,
    required this.cycle,
    required this.done,
    this.currentCount,
    this.maxCount,
  });

  final String title;
  final String meta;
  final String difficulty;
  final String cycle;
  final bool done;
  final int? currentCount;
  final int? maxCount;

  SchedulerItemSummary asUnfinished({bool resetProgress = false}) {
    return SchedulerItemSummary(
      title: title,
      meta: resetProgress ? _resetCurrentProgress(meta) : meta,
      difficulty: difficulty,
      cycle: cycle,
      done: false,
      currentCount: resetProgress ? 0 : currentCount,
      maxCount: maxCount,
    );
  }

  static String _resetCurrentProgress(String value) {
    return value.replaceFirst(RegExp(r'^\s*\d+\s*/'), '0 /');
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'title': title,
      'meta': meta,
      'difficulty': difficulty,
      'cycle': cycle,
      'done': done,
      'currentCount': currentCount,
      'maxCount': maxCount,
    };
  }

  factory SchedulerItemSummary.fromCacheJson(Map<String, dynamic> json) {
    return SchedulerItemSummary(
      title: json['title'] as String? ?? '이름 없음',
      meta: json['meta'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? '',
      cycle: json['cycle'] as String? ?? '',
      done: json['done'] == true,
      currentCount: _readInt(json, ['currentCount']),
      maxCount: _readInt(json, ['maxCount']),
    );
  }

  factory SchedulerItemSummary.fromJson(Map<String, dynamic> json) {
    final title = _readString(json, [
      'content_name',
      'boss_name',
      'quest_name',
      'name',
      'title',
    ]);
    final current = _readInt(json, [
      'current_clear_count',
      'current_count',
      'current_score',
      'now_count',
      'count',
    ]);
    final max = _readInt(json, [
      'max_clear_count',
      'max_count',
      'max_score',
      'limit_count',
    ]);
    final state = _readString(json, [
      'progress_state',
      'quest_state',
      'state',
      'status',
    ]);
    final difficulty = _readString(json, [
      'difficulty',
      'boss_difficulty',
      'difficulty_name',
    ]);
    final cycle = _readString(json, [
      'cycle',
      'reset_cycle',
      'boss_reset_cycle',
    ]);
    final hasExplicitDone = _readBool(json, [
      'done',
      'is_done',
      'clear',
      'completed',
      'complete_flag',
      'is_completed',
      'is_clear',
      'clear_status',
    ]);
    final normalizedTitle = title.isEmpty ? '이름 없음' : title;
    final meta = _schedulerItemMeta(
      title: normalizedTitle,
      state: state,
      current: current,
      max: max,
    );
    final done = hasExplicitDone ||
        state == '2' ||
        _isEpicDungeonDone(normalizedTitle, current, max) ||
        _isGuildWeeklyMissionDone(normalizedTitle, current, max) ||
        _isCountDone(normalizedTitle, current, max);

    return SchedulerItemSummary(
      title: normalizedTitle,
      meta: meta,
      difficulty: difficulty,
      cycle: cycle,
      done: done,
      currentCount: current,
      maxCount: max,
    );
  }

  static String _schedulerItemMeta({
    required String title,
    required String state,
    required int? current,
    required int? max,
  }) {
    final count = current ?? 0;

    if (state == '0' && count == 0) {
      return '';
    }
    if (state == '2' && count == 0) {
      return '';
    }
    if (_isEpicDungeon(title)) {
      return '$count / 5';
    }
    if (_usesCountRatio(title) && current != null && max != null) {
      return '$current / $max';
    }
    if (state.isEmpty && count == 0 && max != null) {
      return '$max';
    }
    if (current != null && max != null && max > 0) {
      return '$current / $max';
    }
    if (current != null && max != null && max == 0) {
      return current > 0 ? '$current' : '';
    }
    return '';
  }

  static bool _isEpicDungeonDone(String title, int? current, int? max) {
    if (!_isEpicDungeon(title)) {
      return false;
    }
    return (current ?? 0) >= 5;
  }

  static bool _isEpicDungeon(String title) {
    return title.contains('에픽 던전');
  }

  static bool _isGuildWeeklyMissionDone(
    String title,
    int? current,
    int? max,
  ) {
    return title.contains('길드') &&
        title.contains('주간') &&
        current != null &&
        max != null &&
        max > 0 &&
        current >= max;
  }

  static bool _isCountDone(String title, int? current, int? max) {
    return _usesCountRatio(title) &&
        current != null &&
        max != null &&
        max > 0 &&
        current >= max;
  }

  static bool _usesCountRatio(String title) {
    const names = [
      '에르다 스펙트럼',
      '배고픈 무토',
      '미드나잇 체이서',
      '스피릿 세이비어',
      '엔하임 디펜스',
      '프로텍트 에스페라인',
    ];

    return names.any(title.contains);
  }

  static bool isRegistered(Map<String, dynamic> json) {
    const keys = [
      'is_registered',
      'registered',
      'registration_flag',
      'is_registered_in_game',
      'is_registered_ingame',
      'is_ingame_registered',
      'is_in_game_registered',
      'ingame_registered',
      'in_game_registered',
      'in_game_register',
      'ingame_register',
    ];

    for (final key in keys) {
      if (!json.containsKey(key)) {
        continue;
      }

      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final normalized = value.toLowerCase();
        return normalized == 'true' ||
            normalized == '1' ||
            normalized == 'y' ||
            normalized == 'yes' ||
            normalized == '등록';
      }
    }

    return false;
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) {
        return value.toString();
      }
    }
    return '';
  }

  static int? _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value);
      }
    }
    return null;
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is String) {
        return value.toLowerCase() == 'true';
      }
    }
    return false;
  }
}

class NoticeItemSummary {
  const NoticeItemSummary({
    required this.noticeType,
    required this.title,
    required this.link,
    required this.registeredAt,
    required this.thumbnail,
    required this.eventStartAt,
    required this.eventEndAt,
    required this.saleStartAt,
    required this.saleEndAt,
    required this.saleOngoing,
    required this.content,
    required this.contentImageUrls,
  });

  final String noticeType;
  final String title;
  final String link;
  final String registeredAt;
  final String thumbnail;
  final String eventStartAt;
  final String eventEndAt;
  final String saleStartAt;
  final String saleEndAt;
  final bool saleOngoing;
  final String content;
  final List<String> contentImageUrls;

  Map<String, dynamic> toCacheJson() {
    return {
      'noticeType': noticeType,
      'title': title,
      'link': link,
      'registeredAt': registeredAt,
      'thumbnail': thumbnail,
      'eventStartAt': eventStartAt,
      'eventEndAt': eventEndAt,
      'saleStartAt': saleStartAt,
      'saleEndAt': saleEndAt,
      'saleOngoing': saleOngoing,
      'content': content,
      'contentImageUrls': contentImageUrls,
    };
  }

  factory NoticeItemSummary.fromJson(Map<String, dynamic> json) {
    return NoticeItemSummary(
      noticeType: _readString(json, ['noticeType', 'notice_type', 'type']),
      title: _readString(json, ['title', 'notice_title']),
      link: _readString(json, ['link', 'url']),
      registeredAt:
          _readString(json, ['registeredAt', 'registered_at', 'date']),
      thumbnail: _readString(
        json,
        [
          'thumbnail',
          'thumbnailUrl',
          'thumbnail_url',
          'image',
          'imageUrl',
          'image_url',
          'bannerImage',
          'banner_image',
        ],
      ),
      eventStartAt: _readString(
          json, ['eventStartAt', 'event_start_at', 'date_event_start']),
      eventEndAt:
          _readString(json, ['eventEndAt', 'event_end_at', 'date_event_end']),
      saleStartAt: _readString(
          json, ['saleStartAt', 'sale_start_at', 'date_sale_start']),
      saleEndAt:
          _readString(json, ['saleEndAt', 'sale_end_at', 'date_sale_end']),
      saleOngoing: _readBool(json, [
        'saleOngoing',
        'sale_ongoing',
        'ongoing_flag',
        'ongoingFlag',
        'always_sale',
        'alwaysSale',
      ]),
      content: _readString(json, ['content', 'contents', 'body']),
      contentImageUrls: _readStringList(
          json, ['contentImageUrls', 'content_image_urls', 'contentImages']),
    );
  }

  String get label {
    return switch (displayType) {
      'maintenance' => '점검',
      'event' => '이벤트',
      'cashshop' => '캐시샵',
      'update' => '업데이트',
      _ => '공지',
    };
  }

  String get displayType {
    if (title.contains('[패치완료]') || title.contains('[점검완료]')) {
      return 'maintenance';
    }
    return noticeType;
  }

  String get dateText {
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(registeredAt);
    return match?.group(0) ?? registeredAt;
  }

  String get eventPeriodText {
    final start = _dateOnly(eventStartAt);
    final end = _dateOnly(eventEndAt);
    if (start.isEmpty || end.isEmpty) {
      return dateText;
    }
    return '$start ~ $end';
  }

  String get cashshopPeriodText {
    if (saleOngoing) {
      return '상시판매';
    }
    final start = _dateOnly(saleStartAt);
    final end = _dateOnly(saleEndAt);
    if (start.isEmpty || end.isEmpty) {
      return eventPeriodText;
    }
    return '$start ~ $end';
  }

  static String _dateOnly(String value) {
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) {
        return value.toString();
      }
    }
    return '';
  }

  static List<String> _readStringList(
      Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is List) {
        return value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      if (value is String && value.isNotEmpty) {
        return [value];
      }
    }
    return const [];
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
    }
    return false;
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
