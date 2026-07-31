import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class EventNoticeCache {
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
    return File('${directory.path}${Platform.pathSeparator}events.json');
  }

  Future<void> ensure() async {
    final file = await _cacheFile;
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode({'events': []}));
    }
  }

  Future<List<NoticeItemSummary>> load() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      final events = decoded is Map ? decoded['events'] : decoded;
      if (events is! List) {
        return const [];
      }

      return events
          .whereType<Map>()
          .map((event) => NoticeItemSummary.fromJson(
                Map<String, dynamic>.from(event),
              ))
          .where(
              (event) => event.noticeType == 'event' && event.title.isNotEmpty)
          .toList();
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<NoticeItemSummary> events) async {
    final file = await _cacheFile;
    await file.writeAsString(jsonEncode({
      'events': events.map((event) => event.toCacheJson()).toList(),
    }));
  }
}
