import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class SchedulerCache {
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
        '${directory.path}${Platform.pathSeparator}scheduler_cache.json');
  }

  Future<SchedulerSnapshot?> load(String ocid) async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded[ocid] is! Map) {
        return null;
      }
      return SchedulerSnapshot.fromCacheJson(
        Map<String, dynamic>.from(decoded[ocid] as Map),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(String ocid, SchedulerSnapshot snapshot) async {
    final file = await _cacheFile;
    Map<String, dynamic> cache = {};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          cache = Map<String, dynamic>.from(decoded);
        }
      } on FileSystemException {
        cache = {};
      } on FormatException {
        cache = {};
      }
    }
    cache[ocid] = snapshot.toCacheJson();
    await file.writeAsString(jsonEncode(cache));
  }
}
