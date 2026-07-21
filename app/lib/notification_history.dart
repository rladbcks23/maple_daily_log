import 'dart:convert';
import 'dart:io';

class NotificationHistory {
  Future<File> get _historyFile async {
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
      '${directory.path}${Platform.pathSeparator}notification_history.json',
    );
  }

  Future<bool> hasSent(String ruleKey) async {
    final history = await _load();
    return history.containsKey(ruleKey);
  }

  Future<void> markSent(String ruleKey) async {
    final history = await _load();
    history[ruleKey] = DateTime.now().toIso8601String();
    final file = await _historyFile;
    await file.writeAsString(jsonEncode(history));
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final file = await _historyFile;
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
    return {};
  }
}
