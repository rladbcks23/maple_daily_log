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
    final response = await _httpClient.get(Uri.parse('$baseUrl/api/nexon/characters'));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('캐릭터 목록을 불러오지 못했습니다. (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final characters = _extractCharacterItems(decoded);

    return characters.map(NexonCharacterSummary.fromJson).toList();
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
    required this.characterName,
    required this.worldName,
    required this.characterClass,
    required this.characterLevel,
  });

  final String characterName;
  final String worldName;
  final String characterClass;
  final int? characterLevel;

  factory NexonCharacterSummary.fromJson(Map<String, dynamic> json) {
    return NexonCharacterSummary(
      characterName: _readString(json, ['character_name', 'characterName', 'name']),
      worldName: _readString(json, ['world_name', 'worldName', 'world']),
      characterClass: _readString(json, ['character_class', 'characterClass', 'class']),
      characterLevel: _readInt(json, ['character_level', 'characterLevel', 'level']),
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

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
