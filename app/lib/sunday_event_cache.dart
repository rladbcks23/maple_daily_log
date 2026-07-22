import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class SundayEventCache {
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
    return File('${directory.path}${Platform.pathSeparator}sunday_event.json');
  }

  Future<NoticeItemSummary?> load() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final cachedEvent = decoded['event'] ?? decoded;
      if (cachedEvent is! Map) {
        return null;
      }
      final event = NoticeItemSummary.fromJson(
        Map<String, dynamic>.from(cachedEvent),
      );
      return event.title.isEmpty ? null : event;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> ensure() async {
    final file = await _cacheFile;
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode({'event': null}));
    }
  }

  Future<void> save(NoticeItemSummary event) async {
    final file = await _cacheFile;
    await file.writeAsString(jsonEncode({'event': event.toCacheJson()}));
  }
}
