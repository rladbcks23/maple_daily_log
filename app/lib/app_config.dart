import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  static const defaults = AppConfig(apiBaseUrl: defaultApiBaseUrl);

  final String apiBaseUrl;

  AppConfig copyWith({String? apiBaseUrl}) {
    return AppConfig(apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl);
  }

  Map<String, dynamic> toJson() => {
        'apiBaseUrl': apiBaseUrl,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final rawBaseUrl = json['apiBaseUrl'] as String? ?? defaultApiBaseUrl;
    return AppConfig(
      apiBaseUrl: ApiClient.isValidBaseUrl(rawBaseUrl)
          ? ApiClient.normalizeBaseUrl(rawBaseUrl)
          : defaultApiBaseUrl,
    );
  }
}

class AppConfigStore {
  Future<File> get _configFile async {
    final appDataDirectory = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    final directory = Directory(
      '$appDataDirectory${Platform.pathSeparator}MapleTaskReminder',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}${Platform.pathSeparator}app_config.json');
  }

  Future<void> ensure() async {
    final file = await _configFile;
    if (!await file.exists()) {
      await save(AppConfig.defaults);
    }
  }

  Future<AppConfig> load() async {
    try {
      final file = await _configFile;
      if (!await file.exists()) {
        return AppConfig.defaults;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return AppConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on FileSystemException {
      return AppConfig.defaults;
    } on FormatException {
      return AppConfig.defaults;
    }
    return AppConfig.defaults;
  }

  Future<void> save(AppConfig config) async {
    final file = await _configFile;
    await file.writeAsString(jsonEncode(config.toJson()));
  }
}
