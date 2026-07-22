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
      if (decoded is! Map) {
        return null;
      }
      final snapshots = decoded['snapshots'] is Map
          ? Map<String, dynamic>.from(decoded['snapshots'] as Map)
          : Map<String, dynamic>.from(decoded);
      final entry = snapshots[ocid];
      if (entry is! Map) {
        return null;
      }
      final snapshot = entry['snapshot'] is Map
          ? Map<String, dynamic>.from(entry['snapshot'] as Map)
          : Map<String, dynamic>.from(entry);
      return SchedulerSnapshot.fromCacheJson(
        snapshot,
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
      await file.writeAsString(jsonEncode({}));
    }
  }

  Future<void> save(String ocid, SchedulerSnapshot snapshot) async {
    final file = await _cacheFile;
    Map<String, dynamic> snapshots = {};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          snapshots = decoded['snapshots'] is Map
              ? Map<String, dynamic>.from(decoded['snapshots'] as Map)
              : Map<String, dynamic>.from(decoded);
        }
      } on FileSystemException {
        snapshots = {};
      } on FormatException {
        snapshots = {};
      }
    }
    snapshots[ocid] = snapshot.toCacheJson();
    await file.writeAsString(jsonEncode(snapshots));
  }
}
