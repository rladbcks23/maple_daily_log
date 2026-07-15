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

  Future<SchedulerSnapshot> fetchScheduler(String ocid) async {
    final response =
        await _httpClient.get(Uri.parse('$baseUrl/api/nexon/scheduler/$ocid'));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('스케쥴러 정보를 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('스케쥴러 응답 형식이 올바르지 않습니다.');
    }

    return SchedulerSnapshot.fromJson(decoded);
  }

  Future<List<NoticeItemSummary>> fetchCurrentNotices() async {
    final response =
        await _httpClient.get(Uri.parse('$baseUrl/api/notices/current'));

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
  });

  final List<SchedulerItemSummary> dailyItems;
  final List<SchedulerItemSummary> weeklyItems;
  final List<SchedulerItemSummary> bossItems;

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
    );
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
    required this.done,
  });

  final String title;
  final String meta;
  final bool done;

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
    final done = _readBool(json, ['done', 'is_done', 'clear', 'completed']) ||
        state == '2' ||
        (current != null && max != null && max > 0 && current >= max);

    return SchedulerItemSummary(
      title: title.isEmpty ? '이름 없음' : title,
      meta: current != null && max != null
          ? '$current / $max'
          : (done ? '완료' : '미완료'),
      done: done,
    );
  }

  static bool isRegistered(Map<String, dynamic> json) {
    const keys = [
      'is_registered',
      'registered',
      'is_ingame_registered',
      'is_in_game_registered',
      'ingame_registered',
      'in_game_registered',
      'is_available',
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

    return true;
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
  });

  final String noticeType;
  final String title;
  final String link;
  final String registeredAt;
  final String thumbnail;

  factory NoticeItemSummary.fromJson(Map<String, dynamic> json) {
    return NoticeItemSummary(
      noticeType: _readString(json, ['noticeType', 'notice_type', 'type']),
      title: _readString(json, ['title', 'notice_title']),
      link: _readString(json, ['link', 'url']),
      registeredAt:
          _readString(json, ['registeredAt', 'registered_at', 'date']),
      thumbnail: _readString(
        json,
        ['thumbnail', 'thumbnail_url', 'image', 'image_url', 'banner_image'],
      ),
    );
  }

  String get label {
    return switch (noticeType) {
      'event' => '이벤트',
      'cashshop' => '캐시샵',
      'update' => '업데이트',
      _ => '공지',
    };
  }

  String get dateText {
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(registeredAt);
    return match?.group(0) ?? registeredAt;
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
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
