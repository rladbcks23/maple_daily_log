import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class CharacterProfileCache {
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
      '${directory.path}${Platform.pathSeparator}character_profiles.json',
    );
  }

  Future<Map<String, NexonCharacterSummary>> load() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['characters'] is! List) {
        return {};
      }
      final profiles = <String, NexonCharacterSummary>{};
      for (final item in (decoded['characters'] as List).whereType<Map>()) {
        final character = NexonCharacterSummary.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (character.ocid.isNotEmpty) {
          profiles[character.ocid] = character;
        }
      }
      return profiles;
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> mergeAndSave(
    Iterable<NexonCharacterSummary> characters,
  ) async {
    final cachedProfiles = await load();
    for (final character in characters) {
      if (character.ocid.isEmpty) {
        continue;
      }
      cachedProfiles[character.ocid] =
          (cachedProfiles[character.ocid] ?? character).merge(character);
    }

    final file = await _cacheFile;
    await file.writeAsString(
      jsonEncode({
        'characters': cachedProfiles.values
            .map((character) => character.toCacheJson())
            .toList(),
      }),
    );
  }
}
