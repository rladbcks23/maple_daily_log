import 'dart:convert';
import 'dart:io';

class PartySchedule {
  const PartySchedule({
    required this.id,
    required this.members,
    required this.bossName,
    required this.difficulty,
    required this.scheduledAt,
    required this.alertEnabled,
    required this.cleared,
  });

  final String id;
  final List<String> members;
  final String bossName;
  final String difficulty;
  final DateTime scheduledAt;
  final bool alertEnabled;
  final bool cleared;

  PartySchedule copyWith({
    String? id,
    List<String>? members,
    String? bossName,
    String? difficulty,
    DateTime? scheduledAt,
    bool? alertEnabled,
    bool? cleared,
  }) {
    return PartySchedule(
      id: id ?? this.id,
      members: members ?? this.members,
      bossName: bossName ?? this.bossName,
      difficulty: difficulty ?? this.difficulty,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      alertEnabled: alertEnabled ?? this.alertEnabled,
      cleared: cleared ?? this.cleared,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'members': members,
        'bossName': bossName,
        'difficulty': difficulty,
        'scheduledAt': scheduledAt.toIso8601String(),
        'alertEnabled': alertEnabled,
        'cleared': cleared,
      };

  factory PartySchedule.fromJson(Map<String, dynamic> json) {
    return PartySchedule(
      id: _readString(json['id']),
      members: _readStringList(json['members']),
      bossName: _readString(json['bossName']),
      difficulty: _readString(json['difficulty']),
      scheduledAt:
          DateTime.tryParse(_readString(json['scheduledAt'])) ?? DateTime.now(),
      alertEnabled: json['alertEnabled'] as bool? ?? true,
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
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<PartySchedule> schedules) async {
    final file = await _scheduleFile;
    final sorted = [...schedules]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    await file.writeAsString(
      jsonEncode({'items': sorted.map((item) => item.toJson()).toList()}),
    );
  }
}
