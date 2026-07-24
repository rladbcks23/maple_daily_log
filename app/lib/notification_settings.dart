import 'dart:convert';
import 'dart:io';

class NotificationSettings {
  const NotificationSettings({
    required this.reminderHour,
    required this.reminderMinute,
    required this.enabled,
    required this.checkOnStartup,
    required this.dailyEnabled,
    required this.weeklyEnabled,
    required this.weeklyWeekdays,
    required this.monthlyEnabled,
    required this.noticeEnabled,
  });

  static const defaults = NotificationSettings(
    reminderHour: 21,
    reminderMinute: 0,
    enabled: true,
    checkOnStartup: true,
    dailyEnabled: true,
    weeklyEnabled: true,
    weeklyWeekdays: [DateTime.tuesday, DateTime.wednesday],
    monthlyEnabled: true,
    noticeEnabled: true,
  );

  final int reminderHour;
  final int reminderMinute;
  final bool enabled;
  final bool checkOnStartup;
  final bool dailyEnabled;
  final bool weeklyEnabled;
  final List<int> weeklyWeekdays;
  final bool monthlyEnabled;
  final bool noticeEnabled;

  NotificationSettings copyWith({
    int? reminderHour,
    int? reminderMinute,
    bool? enabled,
    bool? checkOnStartup,
    bool? dailyEnabled,
    bool? weeklyEnabled,
    List<int>? weeklyWeekdays,
    bool? monthlyEnabled,
    bool? noticeEnabled,
  }) {
    return NotificationSettings(
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      enabled: enabled ?? this.enabled,
      checkOnStartup: checkOnStartup ?? this.checkOnStartup,
      dailyEnabled: dailyEnabled ?? this.dailyEnabled,
      weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
      weeklyWeekdays: weeklyWeekdays ?? this.weeklyWeekdays,
      monthlyEnabled: monthlyEnabled ?? this.monthlyEnabled,
      noticeEnabled: noticeEnabled ?? this.noticeEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'enabled': enabled,
        'checkOnStartup': checkOnStartup,
        'dailyEnabled': dailyEnabled,
        'weeklyEnabled': weeklyEnabled,
        'weeklyWeekdays': weeklyWeekdays,
        'monthlyEnabled': monthlyEnabled,
        'noticeEnabled': noticeEnabled,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final hour = _readBoundedInt(json['reminderHour'], 0, 23) ??
        NotificationSettings.defaults.reminderHour;
    final minute = _readBoundedInt(json['reminderMinute'], 0, 59) ??
        NotificationSettings.defaults.reminderMinute;
    return NotificationSettings(
      reminderHour: hour,
      reminderMinute: minute,
      enabled:
          json['enabled'] as bool? ?? NotificationSettings.defaults.enabled,
      checkOnStartup: json['checkOnStartup'] as bool? ??
          NotificationSettings.defaults.checkOnStartup,
      dailyEnabled: json['dailyEnabled'] as bool? ??
          NotificationSettings.defaults.dailyEnabled,
      weeklyEnabled: json['weeklyEnabled'] as bool? ??
          NotificationSettings.defaults.weeklyEnabled,
      weeklyWeekdays: _readWeekdays(json['weeklyWeekdays']),
      monthlyEnabled: json['monthlyEnabled'] as bool? ??
          NotificationSettings.defaults.monthlyEnabled,
      noticeEnabled: json['noticeEnabled'] as bool? ??
          NotificationSettings.defaults.noticeEnabled,
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

  static List<int> _readWeekdays(Object? value) {
    if (value is! List) {
      return NotificationSettings.defaults.weeklyWeekdays;
    }

    final weekdays = value
        .map((item) => _readBoundedInt(item, DateTime.monday, DateTime.sunday))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return weekdays.isEmpty
        ? NotificationSettings.defaults.weeklyWeekdays
        : weekdays;
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
