import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'api_client.dart';

class PendingUpdateInfo {
  const PendingUpdateInfo({
    required this.version,
    required this.notes,
  });

  final String version;
  final String notes;

  Map<String, dynamic> toJson() => {
        'version': version,
        'notes': notes,
      };

  factory PendingUpdateInfo.fromJson(Map<String, dynamic> json) {
    return PendingUpdateInfo(
      version: json['version']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class AppUpdateService {
  const AppUpdateService();

  Future<PendingUpdateInfo?> takePendingUpdateInfo() async {
    try {
      final file = await _pendingUpdateInfoFile();
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      await file.delete();
      if (decoded is Map) {
        return PendingUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<bool> downloadAndRunInstaller(AppVersionInfo info) async {
    final trimmedUrl = info.downloadUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (trimmedUrl.isEmpty ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    try {
      final installer = await _downloadInstaller(trimmedUrl);
      final pendingInfoCandidate = await _createPendingUpdateInfoCandidate(
        info,
      );
      await _runDownloadedInstaller(installer, pendingInfoCandidate);
      return true;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: trimmedUrl));
      return false;
    }
  }

  Future<Directory> _localAppDataDirectory() async {
    final appDataDirectory = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    final directory = Directory(
      '$appDataDirectory${Platform.pathSeparator}MapleTaskReminder',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _pendingUpdateInfoFile() async {
    final directory = await _localAppDataDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}pending_update.json',
    );
  }

  Future<File> _createPendingUpdateInfoCandidate(AppVersionInfo info) async {
    final directory = await _localAppDataDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'pending_update_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final pendingInfo = PendingUpdateInfo(
      version: info.version,
      notes: info.notes,
    );
    await file.writeAsString(jsonEncode(pendingInfo.toJson()));
    return file;
  }

  Future<File> _downloadInstaller(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FileSystemException('Update installer download failed.');
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      if (contentType.toLowerCase().contains('text/html')) {
        throw const FileSystemException(
          'Update URL must point to an installer file.',
        );
      }

      final fileName = _installerFileName(uri, response);
      if (!fileName.toLowerCase().endsWith('.exe')) {
        throw const FileSystemException(
          'Update URL must point to a Windows installer exe.',
        );
      }

      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'MapleTaskReminderUpdates',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close(force: true);
    }
  }

  String _installerFileName(Uri originalUri, HttpClientResponse response) {
    final redirectUri = response.redirects.isEmpty
        ? originalUri
        : response.redirects.last.location;
    final decodedName = Uri.decodeComponent(
      redirectUri.pathSegments.isEmpty ? '' : redirectUri.pathSegments.last,
    );
    if (decodedName.toLowerCase().endsWith('.exe')) {
      return decodedName;
    }
    return 'MapleTaskReminder-Setup.exe';
  }

  Future<void> _runDownloadedInstaller(
    File installer,
    File pendingInfoCandidate,
  ) async {
    final pendingInfoFile = await _pendingUpdateInfoFile();
    if (await pendingInfoCandidate.exists()) {
      await pendingInfoCandidate.copy(pendingInfoFile.path);
    }

    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'MapleTaskReminderUpdates',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final logPath = '${directory.path}${Platform.pathSeparator}'
        'installer_${DateTime.now().millisecondsSinceEpoch}.log';
    final scriptPath = '${directory.path}${Platform.pathSeparator}'
        'updater_${DateTime.now().millisecondsSinceEpoch}.ps1';
    final launcherPath = '${directory.path}${Platform.pathSeparator}'
        'updater_${DateTime.now().millisecondsSinceEpoch}.vbs';
    final powershell = File(
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}'
      r'\System32\WindowsPowerShell\v1.0\powershell.exe',
    );
    final powershellCommand =
        await powershell.exists() ? powershell.path : 'powershell.exe';
    final appExecutable = Platform.resolvedExecutable;
    final script = '''
\$ErrorActionPreference = 'Continue'
\$targetPid = $pid
\$installer = ${_powerShellLiteral(installer.path)}
\$logPath = ${_powerShellLiteral(logPath)}
\$appExecutable = ${_powerShellLiteral(appExecutable)}

try {
  Wait-Process -Id \$targetPid -Timeout 30 -ErrorAction SilentlyContinue
} catch {}

Start-Sleep -Milliseconds 500
\$arguments = @(
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/SP-',
  '/CLOSEAPPLICATIONS',
  '/FORCECLOSEAPPLICATIONS',
  "/LOG=\$logPath"
)

try {
  Start-Process -FilePath \$installer -ArgumentList \$arguments -Wait -WindowStyle Hidden
} catch {
  Add-Content -LiteralPath \$logPath -Value ("installer failed: " + \$_.Exception.Message)
}

Start-Sleep -Milliseconds 700
if (Test-Path -LiteralPath \$appExecutable) {
  try {
    Start-Process -FilePath \$appExecutable
  } catch {
    Add-Content -LiteralPath \$logPath -Value ("restart failed: " + \$_.Exception.Message)
  }
}
''';
    final scriptFile = File(scriptPath);
    await _writeWindowsScript(scriptFile, script);
    final launcherFile = File(launcherPath);
    final launcher = 'Set shell = CreateObject("WScript.Shell")\r\n'
        'shell.Run ${_vbScriptLiteral('$powershellCommand -NoProfile -ExecutionPolicy Bypass -File "$scriptPath"')}, 0, False\r\n';
    await _writeWindowsScript(launcherFile, launcher);

    await Process.start(
      'wscript.exe',
      [launcherFile.path],
      mode: ProcessStartMode.detached,
    );
  }

  String _powerShellLiteral(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  Future<void> _writeWindowsScript(File file, String content) async {
    final bytes = <int>[0xff, 0xfe];
    for (final codeUnit in content.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  String _vbScriptLiteral(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }
}

bool isNewerVersion(String latestVersion, String currentVersion) {
  final latest = _versionParts(latestVersion);
  final current = _versionParts(currentVersion);
  for (var index = 0; index < mathMax(latest.length, current.length); index++) {
    final latestPart = index < latest.length ? latest[index] : 0;
    final currentPart = index < current.length ? current[index] : 0;
    if (latestPart > currentPart) {
      return true;
    }
    if (latestPart < currentPart) {
      return false;
    }
  }
  return false;
}

int mathMax(int left, int right) => left > right ? left : right;

List<int> _versionParts(String version) {
  final coreVersion = version.split('+').first;
  return coreVersion.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}
