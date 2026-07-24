import 'dart:convert';
import 'dart:io';

class PartySchedule {
  const PartySchedule({
    required this.id,
    required this.members,
    required this.bossName,
    required this.difficulty,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.cleared,
  });

  final String id;
  final List<String> members;
  final String bossName;
  final String difficulty;
  final int weekday;
  final int hour;
  final int minute;
  final bool cleared;

  DateTime nextScheduleFrom(DateTime now) {
    final daysUntil = (weekday - now.weekday) % DateTime.daysPerWeek;
    var next = DateTime(now.year, now.month, now.day, hour, minute)
        .add(Duration(days: daysUntil));
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: DateTime.daysPerWeek));
    }
    return next;
  }

  DateTime currentWeekScheduleFrom(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final daysFromTarget = (now.weekday - weekday) % DateTime.daysPerWeek;
    return startOfToday
        .subtract(Duration(days: daysFromTarget))
        .add(Duration(hours: hour, minutes: minute));
  }

  PartySchedule copyWith({
    String? id,
    List<String>? members,
    String? bossName,
    String? difficulty,
    int? weekday,
    int? hour,
    int? minute,
    bool? cleared,
  }) {
    return PartySchedule(
      id: id ?? this.id,
      members: members ?? this.members,
      bossName: bossName ?? this.bossName,
      difficulty: difficulty ?? this.difficulty,
      weekday: weekday ?? this.weekday,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      cleared: cleared ?? this.cleared,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'members': members,
        'bossName': bossName,
        'difficulty': difficulty,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'cleared': cleared,
      };

  factory PartySchedule.fromJson(Map<String, dynamic> json) {
    final legacySchedule = DateTime.tryParse(_readString(json['scheduledAt']));
    return PartySchedule(
      id: _readString(json['id']),
      members: _readStringList(json['members']),
      bossName: _readString(json['bossName']),
      difficulty: _readString(json['difficulty']),
      weekday:
          _readInt(json['weekday'], legacySchedule?.weekday ?? 2).clamp(1, 7),
      hour: _readInt(json['hour'], legacySchedule?.hour ?? 21).clamp(0, 23),
      minute:
          _readInt(json['minute'], legacySchedule?.minute ?? 0).clamp(0, 59),
      cleared: json['cleared'] as bool? ?? false,
    );
  }

  static String _readString(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static int _readInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class PartyScheduleStore {
  Future<File> get _scheduleFile async {
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
      '${directory.path}${Platform.pathSeparator}party_schedules.json',
    );
  }

  Future<void> ensure() async {
    final file = await _scheduleFile;
    if (!await file.exists()) {
      await save(const []);
    }
  }

  Future<List<PartySchedule>> load() async {
    try {
      final file = await _scheduleFile;
      if (!await file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      final items = decoded is Map ? decoded['items'] : decoded;
      if (items is! List) {
        return const [];
      }
      return items
          .whereType<Map>()
          .map((item) => PartySchedule.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.id.isNotEmpty)
          .toList()
        ..sort(_comparePartySchedule);
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<PartySchedule> schedules) async {
    final file = await _scheduleFile;
    final sorted = [...schedules]..sort(_comparePartySchedule);
    await file.writeAsString(
      jsonEncode({'items': sorted.map((item) => item.toJson()).toList()}),
    );
  }
}

int _comparePartySchedule(PartySchedule a, PartySchedule b) {
  final weekdayCompare = a.weekday.compareTo(b.weekday);
  if (weekdayCompare != 0) {
    return weekdayCompare;
  }
  final hourCompare = a.hour.compareTo(b.hour);
  if (hourCompare != 0) {
    return hourCompare;
  }
  final minuteCompare = a.minute.compareTo(b.minute);
  if (minuteCompare != 0) {
    return minuteCompare;
  }
  return a.bossName.compareTo(b.bossName);
}
