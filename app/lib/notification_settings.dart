import 'dart:convert';
import 'dart:io';

class NotificationSettings {
  const NotificationSettings({
    required this.reminderHour,
    required this.reminderMinute,
    required this.checkOnStartup,
  });

  static const defaults = NotificationSettings(
    reminderHour: 21,
    reminderMinute: 0,
    checkOnStartup: true,
  );

  final int reminderHour;
  final int reminderMinute;
  final bool checkOnStartup;

  NotificationSettings copyWith({
    int? reminderHour,
    int? reminderMinute,
    bool? checkOnStartup,
  }) {
    return NotificationSettings(
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      checkOnStartup: checkOnStartup ?? this.checkOnStartup,
    );
  }

  Map<String, dynamic> toJson() => {
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'checkOnStartup': checkOnStartup,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final hour = _readBoundedInt(json['reminderHour'], 0, 23) ??
        NotificationSettings.defaults.reminderHour;
    final minute = _readBoundedInt(json['reminderMinute'], 0, 59) ??
        NotificationSettings.defaults.reminderMinute;
    return NotificationSettings(
      reminderHour: hour,
      reminderMinute: minute,
      checkOnStartup: json['checkOnStartup'] as bool? ??
          NotificationSettings.defaults.checkOnStartup,
    );
  }

  static int? _readBoundedInt(Object? value, int min, int max) {
    final parsed = switch (value) {
      int number => number,
      String text => int.tryParse(text),
      _ => null,
    };
    if (parsed == null || parsed < min || parsed > max) {
      return null;
    }
    return parsed;
  }
}

class NotificationSettingsStore {
  Future<File> get _settingsFile async {
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
      '${directory.path}${Platform.pathSeparator}notification_settings.json',
    );
  }

  Future<void> ensure() async {
    final file = await _settingsFile;
    if (!await file.exists()) {
      await save(NotificationSettings.defaults);
    }
  }

  Future<NotificationSettings> load() async {
    try {
      final file = await _settingsFile;
      if (!await file.exists()) {
        return NotificationSettings.defaults;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return NotificationSettings.fromJson(
            Map<String, dynamic>.from(decoded));
      }
    } on FileSystemException {
      return NotificationSettings.defaults;
    } on FormatException {
      return NotificationSettings.defaults;
    }
    return NotificationSettings.defaults;
  }

  Future<void> save(NotificationSettings settings) async {
    final file = await _settingsFile;
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
