import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class CharacterCacheData {
  const CharacterCacheData({
    required this.characters,
    required this.selectedOcid,
  });

  final List<NexonCharacterSummary> characters;
  final String selectedOcid;
}

class CharacterCache {
  Future<File> get _cacheFile async {
    final appDataDirectory = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    final directory = Directory(
      '$appDataDirectory${Platform.pathSeparator}MapleTaskReminder',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(
      '${directory.path}${Platform.pathSeparator}selected_characters.json',
    );
  }

  Future<CharacterCacheData?> load() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['characters'] is! List) {
        return null;
      }
      final characters = (decoded['characters'] as List)
          .whereType<Map>()
          .map((item) => NexonCharacterSummary.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((character) => character.ocid.isNotEmpty)
          .toList();
      return CharacterCacheData(
        characters: characters,
        selectedOcid: decoded['selectedOcid'] as String? ?? '',
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> ensure() async {
    final file = await _cacheFile;
    if (!await file.exists()) {
      await file.writeAsString(
        jsonEncode({'characters': const [], 'selectedOcid': ''}),
      );
    }
  }

  Future<void> save(
    List<NexonCharacterSummary> characters,
    NexonCharacterSummary? selectedCharacter,
  ) async {
    final file = await _cacheFile;
    await file.writeAsString(
      jsonEncode({
        'characters':
            characters.map((character) => character.toCacheJson()).toList(),
        'selectedOcid': selectedCharacter?.ocid ?? '',
      }),
    );
  }
}
