import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app_config.dart';
import 'api_client.dart';
import 'character_cache.dart';
import 'character_profile_cache.dart';
import 'event_notice_cache.dart';
import 'local_notification_service.dart';
import 'notification_history.dart';
import 'notification_settings.dart';
import 'party_schedule_store.dart';
import 'scheduler_cache.dart';
import 'sunday_event_cache.dart';

const appCurrentVersion = '0.1.32';
const _mainWindowSize = Size(1280, 860);
const _nativeWindowChannel = MethodChannel('maple_task_reminder/window');
const _mapleProcessNames = {
  'maplestory.exe',
  'maplestoryclient.exe',
  'nexonplug.exe',
  'nexonlauncher.exe',
};
const _singleInstancePort = 48721;
const _singleInstanceShowCommand = 'show';

// Keep a reference to the bound socket so the single-instance lock stays alive.
// ignore: unused_element
ServerSocket? _singleInstanceSocket;
final _mainWindowShowRequests = StreamController<void>.broadcast();
var _isExitingMainApplication = false;
var _isHidingMainWindowToTray = false;
var _isShowingMainWindowFromTray = false;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();
  final windowArguments = _decodeWindowArguments(windowController.arguments);
  if (windowArguments['type'] == 'alert') {
    final alert = _OverlayAlertData(
      title: windowArguments['title']?.toString() ?? '알림',
      body: windowArguments['body']?.toString() ?? '',
    );
    await _configureAlertWindow(alert, windowController);
    runApp(
      _MapleAlertWindowApp(
        windowController: windowController,
        alert: alert,
      ),
    );
    return;
  }

  if (!await _ensureSingleMainInstance()) {
    await windowManager.destroy();
    return;
  }

  await _prepareMainWindowControls();
  runApp(const MapleTaskReminderApp());
}

Future<void> _prepareMainWindowControls() async {
  await _lockCurrentWindowSize(_mainWindowSize);
  if (!Platform.isWindows) {
    await windowManager.setPreventClose(true);
  }
}

Future<void> _hideMainWindowToTray() async {
  if (_isExitingMainApplication || _isHidingMainWindowToTray) {
    return;
  }
  _isHidingMainWindowToTray = true;
  try {
    if (Platform.isWindows) {
      await _nativeWindowChannel.invokeMethod<void>('hideMainWindow');
    } else {
      await windowManager.setPreventClose(true);
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  } finally {
    _isHidingMainWindowToTray = false;
  }
}

Future<void> _showMainWindowFromTray() async {
  if (_isExitingMainApplication || _isShowingMainWindowFromTray) {
    return;
  }
  _isShowingMainWindowFromTray = true;
  try {
    if (Platform.isWindows) {
      await _nativeWindowChannel.invokeMethod<void>('restoreMainWindow');
      return;
    }
    try {
      await windowManager.setPreventClose(true);
    } catch (error) {
      debugPrint('Failed to keep prevent-close enabled: $error');
    }
    try {
      await windowManager.setSkipTaskbar(false);
    } catch (error) {
      debugPrint('Failed to restore taskbar visibility: $error');
    }
    try {
      await windowManager.show();
    } catch (error) {
      debugPrint('Failed to show main window from tray: $error');
    }
    try {
      await windowManager.restore();
    } catch (error) {
      debugPrint('Failed to restore main window from tray: $error');
    }
    try {
      await windowManager.focus();
    } catch (error) {
      debugPrint('Failed to focus main window from tray: $error');
    }
  } catch (error) {
    debugPrint('Failed to recover main window from tray: $error');
    // Keep the tray process alive even if Windows rejects a foreground request.
  } finally {
    _isShowingMainWindowFromTray = false;
  }
}

Future<void> _exitMainApplication() async {
  _isExitingMainApplication = true;
  if (Platform.isWindows) {
    try {
      await _nativeWindowChannel.invokeMethod<void>('exitApplication');
      return;
    } catch (error) {
      debugPrint('Failed to exit through native window channel: $error');
    }
  }
  await windowManager.setPreventClose(false);
  await windowManager.destroy();
  exit(0);
}

Future<bool> _ensureSingleMainInstance() async {
  try {
    _singleInstanceSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      _singleInstancePort,
      shared: false,
    );
    _listenForSingleInstanceSignals(_singleInstanceSocket!);
    return true;
  } on SocketException {
    await _notifyExistingMainInstance(_singleInstanceShowCommand);
    return false;
  }
}

void _listenForSingleInstanceSignals(ServerSocket serverSocket) {
  serverSocket.listen((client) {
    unawaited(() async {
      try {
        final command = (await utf8.decoder.bind(client).join()).trim();
        if (command == _singleInstanceShowCommand) {
          _mainWindowShowRequests.add(null);
        }
      } catch (error) {
        debugPrint('Failed to process single-instance signal: $error');
      } finally {
        await client.close();
      }
    }());
  });
}

Future<void> _notifyExistingMainInstance(String command) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _singleInstancePort,
      timeout: const Duration(milliseconds: 800),
    );
    socket.write(command);
    await socket.flush();
    await socket.close();
  } catch (error) {
    debugPrint('Failed to notify existing main instance: $error');
  }
}

Map<String, dynamic> _decodeWindowArguments(String rawArguments) {
  if (rawArguments.isEmpty) {
    return const {};
  }

  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    return const {};
  }

  return const {};
}

bool _isAlertWindow(WindowController controller) {
  final arguments = _decodeWindowArguments(controller.arguments);
  return arguments['type'] == 'alert';
}

int _windowSortKey(WindowController controller) {
  return int.tryParse(controller.windowId) ?? 0x7fffffff;
}

Future<WindowController?> _primaryAlertWindow() async {
  final controllers = await WindowController.getAll();
  final alertWindows = controllers
      .where((controller) => _isAlertWindow(controller))
      .toList()
    ..sort((a, b) => _windowSortKey(a).compareTo(_windowSortKey(b)));
  return alertWindows.isEmpty ? null : alertWindows.first;
}

Future<void> _hideDuplicateAlertWindows(WindowController primaryWindow) async {
  final controllers = await WindowController.getAll();
  for (final controller in controllers) {
    if (controller.windowId == primaryWindow.windowId ||
        !_isAlertWindow(controller)) {
      continue;
    }

    try {
      await controller.invokeMethod('hideAlert');
    } catch (_) {
      // Older alert windows may not know this method.
    }
    try {
      await controller.hide();
    } catch (_) {
      // Stale duplicate windows should not block the active alert window.
    }
  }
}

Future<void> _lockCurrentWindowSize(Size size) async {
  await windowManager.setSize(size);
  await windowManager.setMinimumSize(size);
  await windowManager.setMaximumSize(size);
  await windowManager.setResizable(false);
}

Future<void> _configureAlertWindow(
  _OverlayAlertData alert,
  WindowController windowController,
) async {
  final alertSize = _alertWindowSize(alert);
  final windowOptions = WindowOptions(
    size: alertSize,
    minimumSize: alertSize,
    maximumSize: alertSize,
    center: true,
    backgroundColor: AppColors.surface,
    skipTaskbar: false,
    title: '알림',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    final primaryWindow = await _primaryAlertWindow();
    if (primaryWindow != null &&
        primaryWindow.windowId != windowController.windowId) {
      await windowManager.hide();
      return;
    }

    await _lockCurrentWindowSize(alertSize);
    await _hideDuplicateAlertWindows(windowController);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  });
}

class _MapleAlertWindowApp extends StatefulWidget {
  const _MapleAlertWindowApp({
    required this.windowController,
    required this.alert,
  });

  final WindowController windowController;
  final _OverlayAlertData alert;

  @override
  State<_MapleAlertWindowApp> createState() => _MapleAlertWindowAppState();
}

class _MapleAlertWindowAppState extends State<_MapleAlertWindowApp>
    with WindowListener {
  late _OverlayAlertData alert = widget.alert;

  @override
  void initState() {
    super.initState();
    windowManager.setPreventClose(true);
    windowManager.addListener(this);
    widget.windowController.setWindowMethodHandler((call) async {
      if (call.method == 'hideAlert') {
        await windowManager.hide();
        return true;
      }

      if (call.method != 'showAlert') {
        return null;
      }

      final arguments = call.arguments;
      if (arguments is! String) {
        return null;
      }

      final decoded = _decodeWindowArguments(arguments);
      if (!mounted) {
        return null;
      }

      setState(() {
        alert = _OverlayAlertData(
          title: decoded['title']?.toString() ?? '알림',
          body: decoded['body']?.toString() ?? '',
        );
      });
      await _resizeAlertWindow(alert);
      await _hideDuplicateAlertWindows(widget.windowController);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
      return true;
    });
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  @override
  void dispose() {
    widget.windowController.setWindowMethodHandler(null);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      title: '알림',
      theme: ThemeData(
        fontFamily: 'Malgun Gothic',
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
      ),
      home: _OverlayAlertWindow(
        alert: alert,
        onTodayMuteChanged: NotificationHistory().setMutedToday,
        onConfirm: () => unawaited(windowManager.hide()),
      ),
    );
  }
}

class MapleTaskReminderApp extends StatelessWidget {
  const MapleTaskReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      title: '메이플 숙제알리미',
      theme: ThemeData(
        fontFamily: 'Malgun Gothic',
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

class _StartupData {
  const _StartupData({
    required this.appConfig,
    required this.noticeItems,
    this.sundayEvent,
    required this.hasLoadedNotices,
  });

  final AppConfig appConfig;
  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool hasLoadedNotices;
}

class _PendingUpdateInfo {
  const _PendingUpdateInfo({
    required this.version,
    required this.notes,
  });

  final String version;
  final String notes;

  Map<String, dynamic> toJson() => {
        'version': version,
        'notes': notes,
      };

  factory _PendingUpdateInfo.fromJson(Map<String, dynamic> json) {
    return _PendingUpdateInfo(
      version: json['version']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
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
  final pendingInfo = _PendingUpdateInfo(
    version: info.version,
    notes: info.notes,
  );
  await file.writeAsString(jsonEncode(pendingInfo.toJson()));
  return file;
}

Future<_PendingUpdateInfo?> _takePendingUpdateInfo() async {
  try {
    final file = await _pendingUpdateInfoFile();
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    await file.delete();
    if (decoded is Map) {
      return _PendingUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  return null;
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<_StartupData> _startupData = _loadStartupData();

  Future<_StartupData> _loadStartupData() async {
    final appConfigStore = AppConfigStore();
    final appConfig = await appConfigStore.load();
    final apiClient = ApiClient(baseUrl: appConfig.apiBaseUrl);
    final eventCache = EventNoticeCache();
    final sundayCache = SundayEventCache();
    await eventCache.ensure();
    final cachedSundayEvent = await sundayCache.load();

    try {
      final fetchedNoticeItems = await apiClient.fetchCurrentNotices();
      final noticeItems = await _mergeCurrentNoticeItemsWithEventCache(
        fetchedNoticeItems,
        eventCache,
      );
      var sundayEvent = _findSpecialSundayEvent(noticeItems);
      sundayEvent ??= await apiClient.fetchLatestSundayEvent();
      if (sundayEvent != null) {
        await sundayCache.save(sundayEvent);
      }
      return _StartupData(
        appConfig: appConfig,
        noticeItems: noticeItems,
        sundayEvent: sundayEvent ?? cachedSundayEvent,
        hasLoadedNotices: true,
      );
    } catch (_) {
      return _StartupData(
        appConfig: appConfig,
        noticeItems: const [],
        sundayEvent: cachedSundayEvent,
        hasLoadedNotices: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupData>(
      future: _startupData,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _MapleAppShell(startupData: snapshot.requireData);
        }
        return const _StartupLoadingScreen();
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '메이플 숙제알리미',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NexonApiSetupScreen extends StatefulWidget {
  const _NexonApiSetupScreen({
    required this.onSave,
  });

  final Future<void> Function(String apiKey) onSave;

  @override
  State<_NexonApiSetupScreen> createState() => _NexonApiSetupScreenState();
}

class _NexonApiSetupScreenState extends State<_NexonApiSetupScreen> {
  final apiKeyController = TextEditingController();
  var showApiKey = false;
  var saving = false;

  @override
  void dispose() {
    apiKeyController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final apiKey = apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('넥슨 Open API 키를 입력해주세요.')),
      );
      return;
    }

    setState(() {
      saving = true;
    });
    try {
      await widget.onSave(apiKey);
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '메이플 숙제알리미',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '먼저 넥슨 Open API 키를 설정해주세요.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '캐릭터 조회와 스케줄러 확인에 사용할 API 키입니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: apiKeyController,
                        enabled: !saving,
                        obscureText: !showApiKey,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(submit()),
                        decoration: InputDecoration(
                          labelText: '넥슨 Open API 키',
                          border: const OutlineInputBorder(),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.navAccent,
                              width: 1.4,
                            ),
                          ),
                          suffixIcon: IconButton(
                            tooltip: showApiKey ? 'API 키 숨기기' : 'API 키 보기',
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                      showApiKey = !showApiKey;
                                    }),
                            icon: Icon(
                              showApiKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: saving ? null : submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('시작하기'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayAlertData {
  const _OverlayAlertData({
    required this.title,
    required this.body,
    this.payload,
  });

  final String title;
  final String body;
  final String? payload;
}

_OverlayAlertData _mergeOverlayAlerts(List<_OverlayAlertData> alerts) {
  if (alerts.length == 1) {
    return alerts.first;
  }

  final titleSet = alerts.map((alert) => alert.title).toSet();
  final payloadSet = alerts.map((alert) => alert.payload).toSet();
  final body = alerts
      .map((alert) => alert.body.trim())
      .where((body) => body.isNotEmpty)
      .join('\n');

  return _OverlayAlertData(
    title:
        titleSet.length == 1 ? alerts.first.title : '알림 ${alerts.length}개가 있어요',
    body: body,
    payload: payloadSet.length == 1 ? alerts.first.payload : null,
  );
}

int _estimatedAlertBodyLines(String body) {
  if (body.trim().isEmpty) {
    return 1;
  }
  return body
      .split('\n')
      .map((line) => math.max(1, (line.trim().length / 24).ceil()))
      .fold(0, (sum, lineCount) => sum + lineCount)
      .clamp(1, 28);
}

Size _alertWindowSize(_OverlayAlertData alert) {
  final bodyHeight = _alertBodyHeight(alert.body);
  final longestLine = alert.body
      .split('\n')
      .fold<int>(0, (maxLength, line) => math.max(maxLength, line.length));
  final width = longestLine > 42 || alert.body.length > 90 ? 480.0 : 408.0;
  final height = (332 + bodyHeight).clamp(368.0, 860.0).toDouble();
  return Size(width, height);
}

double _alertBodyHeight(String body) {
  final lines = _estimatedAlertBodyLines(body);
  return math.min(560.0, math.max(58.0, lines * 23.0 + 8.0));
}

Future<void> _resizeAlertWindow(_OverlayAlertData alert) async {
  final size = _alertWindowSize(alert);
  await _lockCurrentWindowSize(size);
  await windowManager.center();
}

class _OverlayAlertWindow extends StatelessWidget {
  const _OverlayAlertWindow({
    required this.alert,
    required this.onTodayMuteChanged,
    required this.onConfirm,
  });

  final _OverlayAlertData alert;
  final Future<void> Function(bool muted) onTodayMuteChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final size = _alertWindowSize(alert);
    final bodyMaxHeight = _alertBodyHeight(alert.body);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onConfirm();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.surface,
            body: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Container(
                        width: size.width - 8,
                        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFFE9DD),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '!',
                                style: TextStyle(
                                  color: AppColors.navAccent,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              alert.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: bodyMaxHeight,
                              child: Center(
                                child: Text(
                                  alert.body,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 14,
                                    height: 1.45,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _TodayMuteSwitch(onChanged: onTodayMuteChanged),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: onConfirm,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.navAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: const Text('확인'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayMuteSwitch extends StatefulWidget {
  const _TodayMuteSwitch({required this.onChanged});

  final Future<void> Function(bool muted) onChanged;

  @override
  State<_TodayMuteSwitch> createState() => _TodayMuteSwitchState();
}

class _TodayMuteSwitchState extends State<_TodayMuteSwitch> {
  var muted = false;
  var saving = false;

  Future<void> _setMuted(bool value) async {
    if (saving) {
      return;
    }

    setState(() {
      muted = value;
      saving = true;
    });

    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: saving ? null : () => unawaited(_setMuted(!muted)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '오늘 알림 끄기',
                style: TextStyle(
                  color: muted ? AppColors.navAccent : AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 22,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: muted ? AppColors.navAccent : const Color(0xFFF2EDE7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: muted ? AppColors.navAccent : AppColors.border,
                  ),
                ),
                alignment: muted ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: muted ? Colors.white : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFFEFBF2);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE8E2D4);
  static const softBorder = Color(0xFFE8EAF0);
  static const text = Color(0xFF3D4048);
  static const muted = Color(0xFF7B8291);
  static const primary = Color(0xFF5E76B7);
  static const selected = Color(0xFFEAF0FF);
  static const selectedBorder = Color(0xFFB8C8F8);
  static const navAccent = Color(0xFFE98946);
  static const navBorder = Color(0xFFF1B98C);
  static const completionTag = Color(0xFFFFFAF8);
  static const completionTagBorder = Color(0xFFE6B9AC);
  static const completionTagText = Color(0xFFA76150);
  static const button = Color(0xFF3D4048);
  static const disabled = Color(0xFFB8BEC9);
}

enum AppSection {
  dashboard('대시보드', Icons.dashboard_outlined),
  character('캐릭터 선택', Icons.person_add_alt_1_rounded),
  scheduler('스케쥴러', Icons.event_note_rounded),
  party('파티 일정', Icons.groups_2_outlined),
  events('진행중인 이벤트', Icons.celebration_rounded),
  notices('공지사항', Icons.campaign_rounded),
  sunday('이번주 썬데이', Icons.wb_sunny_rounded),
  settings('설정', Icons.settings_outlined);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _MapleAppShell extends StatefulWidget {
  const _MapleAppShell({required this.startupData});

  final _StartupData startupData;

  @override
  State<_MapleAppShell> createState() => _MapleAppShellState();
}

class _MapleAppShellState extends State<_MapleAppShell> with WindowListener {
  late ApiClient apiClient;
  final AppConfigStore appConfigStore = AppConfigStore();
  final CharacterCache characterCache = CharacterCache();
  final CharacterProfileCache characterProfileCache = CharacterProfileCache();
  final SchedulerCache schedulerCache = SchedulerCache();
  final EventNoticeCache eventNoticeCache = EventNoticeCache();
  final SundayEventCache sundayEventCache = SundayEventCache();
  final NotificationHistory notificationHistory = NotificationHistory();
  final PartyScheduleStore partyScheduleStore = PartyScheduleStore();
  final NotificationSettingsStore notificationSettingsStore =
      NotificationSettingsStore();

  Timer? notificationTimer;
  Timer? launcherMonitorTimer;
  Timer? overlayAlertBatchTimer;
  StreamSubscription<void>? mainWindowShowRequestSubscription;
  var isCheckingScheduledNotifications = false;
  var isCheckingNoticeNotifications = false;
  var isCheckingLauncherProcess = false;
  var isFlushingOverlayAlerts = false;
  var isHidingWindowToTray = false;
  var hasActiveLauncherSession = false;
  var appConfig = AppConfig.defaults;
  var notificationSettings = NotificationSettings.defaults;
  var currentSection = AppSection.character;
  var isLoading = false;
  var isSchedulerLoading = false;
  var isSchedulerRefreshing = false;
  var isNoticeLoading = false;
  var isNoticeRefreshing = false;
  String? errorMessage;
  String? schedulerErrorMessage;
  String? noticeErrorMessage;
  NexonCharacterSummary? selectedCharacter;
  List<NexonCharacterSummary> selectedCharacters = const [];
  Set<String> notificationDisabledOcids = {};
  SchedulerSnapshot? schedulerSnapshot;
  Map<String, SchedulerSnapshot> dashboardSnapshots = const {};
  List<NoticeItemSummary> noticeItems = const [];
  List<PartySchedule> partySchedules = const [];
  NoticeItemSummary? sundayEvent;
  _OverlayAlertData? overlayAlert;
  WindowController? alertWindowController;
  Future<WindowController?>? alertWindowCreation;
  final pendingOverlayAlerts = <_OverlayAlertData>[];
  final pendingPartyScheduleRuleKeys = <String>{};
  var wasHiddenBeforeOverlay = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    mainWindowShowRequestSubscription = _mainWindowShowRequests.stream.listen(
      (_) => unawaited(showWindowFromTray()),
    );
    appConfig = widget.startupData.appConfig;
    apiClient = ApiClient(
      baseUrl: appConfig.apiBaseUrl,
      nexonApiKey: appConfig.nexonApiKey,
    );
    noticeItems = widget.startupData.noticeItems;
    sundayEvent = widget.startupData.sundayEvent;
    LocalNotificationService.instance.setOnNotificationTap(
      handleNotificationTap,
    );
    unawaited(initializeDesktopControls());
    unawaited(initializeNotifications());
    unawaited(initializeCachedState());
    if (!widget.startupData.hasLoadedNotices) {
      unawaited(loadInitialNoticeData());
    }
    notificationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(checkScheduledNotifications()),
    );
    launcherMonitorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(checkLauncherProcess()),
    );
    unawaited(checkScheduledNotifications());
    unawaited(checkLauncherProcess());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(showPendingUpdateInfo());
    });
  }

  Future<void> showPendingUpdateInfo() async {
    final pendingInfo = await _takePendingUpdateInfo();
    if (pendingInfo == null || !mounted) {
      return;
    }
    if (pendingInfo.version != appCurrentVersion) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('업데이트 완료 ${pendingInfo.version}'),
          content: Text(
            pendingInfo.notes.trim().isEmpty
                ? '최신 버전으로 업데이트했습니다.'
                : pendingInfo.notes.trim(),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> initializeNotifications() async {
    final payload = await LocalNotificationService.instance.initialize();
    if (payload != null) {
      handleNotificationTap(payload);
    }
  }

  Future<void> initializeDesktopControls() async {
    await _lockCurrentWindowSize(_mainWindowSize);
    if (!Platform.isWindows) {
      await windowManager.setPreventClose(true);
    }
  }

  @override
  void dispose() {
    notificationTimer?.cancel();
    launcherMonitorTimer?.cancel();
    overlayAlertBatchTimer?.cancel();
    mainWindowShowRequestSubscription?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  Future<void> _handleWindowClose() async {
    await hideWindowToTray();
  }

  Future<void> hideWindowToTray() async {
    await _hideMainWindowToTray();
  }

  Future<void> showWindowFromTray() async {
    await _showMainWindowFromTray();
  }

  Future<void> exitApplication() async {
    await _exitMainApplication();
  }

  Future<void> checkLauncherProcess() async {
    if (!Platform.isWindows || isCheckingLauncherProcess) {
      return;
    }

    isCheckingLauncherProcess = true;
    try {
      final launcherRunning = await _isMapleLauncherRunning();
      if (launcherRunning) {
        hasActiveLauncherSession = true;
      } else if (hasActiveLauncherSession) {
        hasActiveLauncherSession = false;
      }
    } finally {
      isCheckingLauncherProcess = false;
    }
  }

  Future<bool> _isMapleLauncherRunning() async {
    try {
      final result = await Process.run(
        'tasklist',
        const ['/fo', 'csv', '/nh'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        return false;
      }

      final output = result.stdout.toString().toLowerCase();
      return _mapleProcessNames.any(output.contains);
    } on ProcessException {
      return false;
    }
  }

  Future<bool> _showSystemNotificationIfLauncherActive({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!hasActiveLauncherSession) {
      return false;
    }

    await LocalNotificationService.instance.showNotification(
      id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title: title,
      body: body,
      payload: payload,
    );
    return true;
  }

  Future<void> showOverlayAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (await notificationHistory.isMutedToday()) {
      return;
    }

    pendingOverlayAlerts.add(
      _OverlayAlertData(
        title: title,
        body: body,
        payload: payload,
      ),
    );

    overlayAlertBatchTimer ??= Timer(const Duration(milliseconds: 250), () {
      overlayAlertBatchTimer = null;
      unawaited(_flushOverlayAlerts());
    });
  }

  Future<void> _flushOverlayAlerts() async {
    if (isFlushingOverlayAlerts) {
      return;
    }

    isFlushingOverlayAlerts = true;
    try {
      while (pendingOverlayAlerts.isNotEmpty) {
        final alerts = List<_OverlayAlertData>.of(pendingOverlayAlerts);
        pendingOverlayAlerts.clear();
        await _showOverlayAlertNow(_mergeOverlayAlerts(alerts));
      }
    } finally {
      isFlushingOverlayAlerts = false;
      if (pendingOverlayAlerts.isNotEmpty && overlayAlertBatchTimer == null) {
        overlayAlertBatchTimer = Timer(const Duration(milliseconds: 250), () {
          overlayAlertBatchTimer = null;
          unawaited(_flushOverlayAlerts());
        });
      }
    }
  }

  Future<WindowController?> _findReusableAlertWindow() async {
    final primaryAlertWindow = await _primaryAlertWindow();
    if (primaryAlertWindow == null) {
      return null;
    }

    await _hideDuplicateAlertWindows(primaryAlertWindow);
    return primaryAlertWindow;
  }

  Future<void> _showOverlayAlertNow(_OverlayAlertData alert) async {
    if (await notificationHistory.isMutedToday()) {
      return;
    }

    await checkLauncherProcess();
    if (await _showSystemNotificationIfLauncherActive(
      title: alert.title,
      body: alert.body,
      payload: alert.payload,
    )) {
      return;
    }

    final alertArguments = jsonEncode({
      'type': 'alert',
      'title': alert.title,
      'body': alert.body,
    });

    try {
      final existingAlertWindow =
          alertWindowController ?? await _findReusableAlertWindow();
      if (existingAlertWindow != null) {
        alertWindowController = existingAlertWindow;
        await existingAlertWindow.invokeMethod('showAlert', alertArguments);
        return;
      }

      final creatingAlertWindow = alertWindowCreation;
      if (creatingAlertWindow != null) {
        final createdWindow = await creatingAlertWindow;
        if (createdWindow != null) {
          await createdWindow.invokeMethod('showAlert', alertArguments);
          return;
        }
      }

      final creation = WindowController.create(
        WindowConfiguration(
          arguments: alertArguments,
          hiddenAtLaunch: true,
        ),
      );
      alertWindowCreation = creation;
      alertWindowController = await creation;
      alertWindowCreation = null;
      return;
    } catch (_) {
      alertWindowController = null;
      alertWindowCreation = null;
      // Fall back to the in-app overlay if the native alert window fails.
    }

    final isVisible = await windowManager.isVisible();
    wasHiddenBeforeOverlay = !isVisible;
    if (!mounted) {
      return;
    }

    if (!isVisible) {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
    }

    setState(() {
      overlayAlert = alert;
    });
  }

  Future<void> closeOverlayAlert() async {
    final payload = overlayAlert?.payload;
    setState(() {
      overlayAlert = null;
    });

    if (payload != null) {
      if (wasHiddenBeforeOverlay) {
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        await windowManager.focus();
      }
      handleNotificationTap(payload);
    } else if (wasHiddenBeforeOverlay) {
      await hideWindowToTray();
    }
    wasHiddenBeforeOverlay = false;
  }

  Future<void> initializeCachedState() async {
    await Future.wait([
      characterCache.ensure(),
      characterProfileCache.ensure(),
      schedulerCache.ensure(),
      eventNoticeCache.ensure(),
      sundayEventCache.ensure(),
      partyScheduleStore.ensure(),
      notificationSettingsStore.ensure(),
      appConfigStore.ensure(),
    ]);
    final loadedNotificationSettings = await notificationSettingsStore.load();
    final loadedPartySchedules = await partyScheduleStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      notificationSettings = loadedNotificationSettings;
      partySchedules = loadedPartySchedules;
    });
    unawaited(checkNewNoticeNotifications());
    await loadCachedCharacters();
    unawaited(refreshCharacterListCache());
  }

  Future<void> loadCachedCharacters() async {
    final cachedData = await characterCache.load();
    if (!mounted || cachedData == null || cachedData.characters.isEmpty) {
      return;
    }

    final selected = cachedData.characters.firstWhere(
      (character) => character.ocid == cachedData.selectedOcid,
      orElse: () => cachedData.characters.first,
    );
    setState(() {
      selectedCharacters = cachedData.characters;
      selectedCharacter = selected;
      notificationDisabledOcids = cachedData.notificationDisabledOcids;
    });
    unawaited(loadDashboardSnapshots());
    unawaited(loadScheduler(selected));
    unawaited(refreshSelectedCharacterProfiles());
    unawaited(refreshRegisteredSchedulers(skipOcid: selected.ocid));
    unawaited(checkStartupScheduledNotifications());
  }

  void persistCharacters() {
    final selectedOcids =
        selectedCharacters.map((character) => character.ocid).toSet();
    notificationDisabledOcids =
        notificationDisabledOcids.intersection(selectedOcids);
    unawaited(
      characterCache.save(
        selectedCharacters,
        selectedCharacter,
        notificationDisabledOcids,
      ),
    );
  }

  Future<void> refreshCharacterListCache() async {
    try {
      final characters = await apiClient.fetchNexonCharacters();
      await characterProfileCache.replaceAndSave(characters);

      const batchSize = 4;
      for (var start = 0; start < characters.length; start += batchSize) {
        final end = start + batchSize > characters.length
            ? characters.length
            : start + batchSize;
        final details = await Future.wait(
          characters.sublist(start, end).map(apiClient.fetchCharacterBasic),
        );
        await characterProfileCache.mergeAndSave(details);
      }
    } catch (_) {
      // Keep the most recently cached character list when the API fails.
    }
  }

  Future<void> refreshSelectedCharacterProfiles() async {
    if (selectedCharacters.isEmpty) {
      return;
    }

    try {
      final refreshedCharacters = <NexonCharacterSummary>[];
      const batchSize = 4;
      for (var start = 0;
          start < selectedCharacters.length;
          start += batchSize) {
        final end = start + batchSize > selectedCharacters.length
            ? selectedCharacters.length
            : start + batchSize;
        final details = await Future.wait(
          selectedCharacters
              .sublist(start, end)
              .map(apiClient.fetchCharacterBasic),
        );
        refreshedCharacters.addAll(details);
      }
      if (!mounted || refreshedCharacters.isEmpty) {
        return;
      }

      await characterProfileCache.mergeAndSave(refreshedCharacters);

      setState(() {
        final refreshedByOcid = {
          for (final character in refreshedCharacters)
            character.ocid: character,
        };
        selectedCharacters = selectedCharacters
            .map((character) => character.merge(
                  refreshedByOcid[character.ocid] ?? character,
                ))
            .toList();
        final current = selectedCharacter;
        if (current != null) {
          selectedCharacter = selectedCharacters.firstWhere(
            (character) => _isSameCharacter(character, current),
            orElse: () =>
                current.merge(refreshedByOcid[current.ocid] ?? current),
          );
        }
      });
      persistCharacters();
      unawaited(loadDashboardSnapshots());
    } catch (_) {
      // Cached character data remains usable when the basic info refresh fails.
    }
  }

  Future<void> loadDashboardSnapshots() async {
    final entries = await Future.wait(
      selectedCharacters.map((character) async {
        final snapshot = await schedulerCache.load(character.ocid);
        return MapEntry(character.ocid, snapshot);
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      dashboardSnapshots = {
        for (final entry in entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    });
  }

  Future<void> refreshRegisteredSchedulers({String? skipOcid}) async {
    final characters = selectedCharacters
        .where((character) => character.ocid != skipOcid)
        .toList();
    const batchSize = 4;
    for (var start = 0; start < characters.length; start += batchSize) {
      final end = start + batchSize > characters.length
          ? characters.length
          : start + batchSize;
      await Future.wait(characters.sublist(start, end).map(loadScheduler));
    }
  }

  Future<void> loadInitialNoticeData() async {
    final cachedSundayEvent = await sundayEventCache.load();
    if (mounted && cachedSundayEvent != null) {
      setState(() {
        sundayEvent = cachedSundayEvent;
      });
    }
    await loadCurrentNotices();
  }

  Future<void> openCharacterPicker() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final cachedProfilesFuture = characterProfileCache.load();
      final characters = await apiClient.fetchNexonCharacters();
      if (!mounted) {
        return;
      }
      final cachedProfiles = await cachedProfilesFuture;
      if (!mounted) {
        return;
      }
      await characterProfileCache.replaceAndSave(characters);
      if (!mounted) {
        return;
      }

      final sortedCharacters = characters
          .map(
            (character) =>
                character.merge(cachedProfiles[character.ocid] ?? character),
          )
          .toList()
        ..sort((a, b) {
          final levelComparison =
              (b.characterLevel ?? -1).compareTo(a.characterLevel ?? -1);
          if (levelComparison != 0) {
            return levelComparison;
          }
          return a.characterName.compareTo(b.characterName);
        });

      final selected = await showDialog<NexonCharacterSummary>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return _CharacterPickerDialog(
            characters: sortedCharacters,
            selectedCharacter: selectedCharacter,
            selectedCharacters: selectedCharacters,
            loadCharacterBasic: apiClient.fetchCharacterBasic,
            cacheCharacterBasics: characterProfileCache.mergeAndSave,
          );
        },
      );

      if (selected != null && mounted) {
        final detailed = selected.characterImage.isEmpty
            ? await apiClient.fetchCharacterBasic(selected)
            : selected;
        if (!mounted) {
          return;
        }
        unawaited(characterProfileCache.mergeAndSave([detailed]));

        setState(() {
          final nextCharacters = [...selectedCharacters];
          final existingIndex = nextCharacters.indexWhere(
            (character) => _isSameCharacter(character, detailed),
          );
          if (existingIndex == -1) {
            nextCharacters.add(detailed);
          } else {
            nextCharacters[existingIndex] = detailed;
          }
          selectedCharacters = nextCharacters;
          selectedCharacter = detailed;
          schedulerSnapshot = null;
          schedulerErrorMessage = null;
        });
        persistCharacters();
        unawaited(loadDashboardSnapshots());
        await loadScheduler(detailed, refresh: true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> selectCharacter(NexonCharacterSummary character) async {
    if (_isSameCharacter(character, selectedCharacter)) {
      return;
    }

    setState(() {
      selectedCharacter = character;
      schedulerSnapshot = null;
      schedulerErrorMessage = null;
    });
    persistCharacters();
    await loadScheduler(character, refresh: true);
  }

  void openCharacterScheduler(NexonCharacterSummary character) {
    if (!_isSameCharacter(character, selectedCharacter)) {
      unawaited(selectCharacter(character));
    }
    selectSection(AppSection.scheduler);
  }

  void deleteCharacter(NexonCharacterSummary character) {
    final deletesSelected = _isSameCharacter(character, selectedCharacter);
    NexonCharacterSummary? nextSelectedCharacter;

    setState(() {
      selectedCharacters = selectedCharacters
          .where((selected) => !_isSameCharacter(selected, character))
          .toList();
      dashboardSnapshots = Map<String, SchedulerSnapshot>.from(
        dashboardSnapshots,
      )..remove(character.ocid);
      notificationDisabledOcids = {...notificationDisabledOcids}
        ..remove(character.ocid);
      if (deletesSelected) {
        nextSelectedCharacter =
            selectedCharacters.isEmpty ? null : selectedCharacters.first;
        selectedCharacter = nextSelectedCharacter;
        schedulerSnapshot = null;
        schedulerErrorMessage = null;
        if (nextSelectedCharacter == null) {
          currentSection = AppSection.character;
        }
      }
    });
    persistCharacters();

    if (nextSelectedCharacter != null) {
      unawaited(loadScheduler(nextSelectedCharacter!));
    }
  }

  void moveCharacterToIndex(NexonCharacterSummary character, int targetIndex) {
    final currentIndex = selectedCharacters.indexWhere(
      (selected) => _isSameCharacter(selected, character),
    );
    if (currentIndex < 0) {
      return;
    }

    final normalizedTargetIndex =
        targetIndex.clamp(0, selectedCharacters.length - 1);
    if (currentIndex == normalizedTargetIndex) {
      return;
    }

    final nextCharacters = [...selectedCharacters];
    final movedCharacter = nextCharacters.removeAt(currentIndex);
    nextCharacters.insert(normalizedTargetIndex, movedCharacter);

    setState(() {
      selectedCharacters = nextCharacters;
    });
    persistCharacters();
  }

  void toggleCharacterNotification(NexonCharacterSummary character) {
    setState(() {
      final nextDisabledOcids = {...notificationDisabledOcids};
      if (nextDisabledOcids.contains(character.ocid)) {
        nextDisabledOcids.remove(character.ocid);
      } else {
        nextDisabledOcids.add(character.ocid);
      }
      notificationDisabledOcids = nextDisabledOcids;
    });
    persistCharacters();
  }

  Future<void> loadScheduler(
    NexonCharacterSummary character, {
    bool refresh = false,
  }) async {
    final cachedSnapshot = await schedulerCache.load(character.ocid);
    if (!mounted) {
      return;
    }

    final isCurrentCharacter = _isSameCharacter(character, selectedCharacter);
    final hasCachedSnapshot = cachedSnapshot != null;
    if (isCurrentCharacter) {
      setState(() {
        if (refresh || hasCachedSnapshot) {
          isSchedulerRefreshing = true;
        } else {
          isSchedulerLoading = true;
        }
        schedulerErrorMessage = null;
        if (hasCachedSnapshot) {
          schedulerSnapshot = cachedSnapshot;
        }
      });
    }

    try {
      final snapshot = await apiClient.fetchScheduler(
        character.ocid,
        forceRefresh: refresh,
      );
      final mergedSnapshot = cachedSnapshot == null
          ? snapshot
          : snapshot.withCachedEmptySections(cachedSnapshot);
      final displayedSnapshot = mergedSnapshot;
      if (snapshot.hasDailyItems ||
          snapshot.hasWeeklyItems ||
          snapshot.hasBossItems) {
        final snapshotToCache = SchedulerSnapshot(
          dailyItems: snapshot.hasDailyItems
              ? snapshot.dailyItems
              : cachedSnapshot?.dailyItems ?? const [],
          weeklyItems: snapshot.hasWeeklyItems
              ? snapshot.weeklyItems
              : cachedSnapshot?.weeklyItems ?? const [],
          bossItems: snapshot.hasBossItems
              ? snapshot
                  .withCachedEmptySections(cachedSnapshot ?? snapshot)
                  .bossItems
              : cachedSnapshot?.bossItems ?? const [],
          weeklyBossClearCount: snapshot.weeklyBossClearCount ??
              cachedSnapshot?.weeklyBossClearCount,
          weeklyBossClearLimit: snapshot.weeklyBossClearLimit ??
              cachedSnapshot?.weeklyBossClearLimit,
        );
        await schedulerCache.save(character.ocid, snapshotToCache);
      }
      if (!mounted) {
        return;
      }

      setState(() {
        dashboardSnapshots = Map<String, SchedulerSnapshot>.from(
          dashboardSnapshots,
        )..[character.ocid] = displayedSnapshot;
        if (_isSameCharacter(character, selectedCharacter)) {
          schedulerSnapshot = displayedSnapshot;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (!hasCachedSnapshot &&
          _isSameCharacter(character, selectedCharacter)) {
        setState(() {
          schedulerErrorMessage = error.toString();
        });
      }
    } finally {
      if (mounted && _isSameCharacter(character, selectedCharacter)) {
        setState(() {
          if (refresh || hasCachedSnapshot) {
            isSchedulerRefreshing = false;
          } else {
            isSchedulerLoading = false;
          }
        });
      }
    }
  }

  Future<void> loadCurrentNotices({bool refresh = false}) async {
    setState(() {
      if (refresh) {
        isNoticeRefreshing = true;
      } else {
        isNoticeLoading = true;
      }
      noticeErrorMessage = null;
    });

    try {
      final fetchedItems = await apiClient.fetchCurrentNotices(
        forceRefresh: refresh,
      );
      final items = await _mergeCurrentNoticeItemsWithEventCache(
        fetchedItems,
        eventNoticeCache,
      );
      final currentSundayEvent = _findSpecialSundayEvent(items);
      NoticeItemSummary? nextSundayEvent = currentSundayEvent;
      if (nextSundayEvent == null) {
        try {
          nextSundayEvent = await apiClient.fetchLatestSundayEvent(
            forceRefresh: refresh,
          );
        } on ApiException {
          nextSundayEvent = null;
        }
      }
      if (nextSundayEvent != null) {
        await sundayEventCache.save(nextSundayEvent);
      }
      if (!mounted) {
        return;
      }

      setState(() {
        noticeItems = items;
        if (nextSundayEvent != null) {
          sundayEvent = nextSundayEvent;
        }
      });
      if (refresh) {
        unawaited(checkNewNoticeNotifications());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        noticeErrorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          if (refresh) {
            isNoticeRefreshing = false;
          } else {
            isNoticeLoading = false;
          }
        });
      }
    }
  }

  Future<void> refreshCurrentSection() async {
    if (currentSection == AppSection.scheduler) {
      final character = selectedCharacter;
      if (character != null) {
        await loadScheduler(character, refresh: true);
      }
      return;
    }

    if (currentSection == AppSection.events ||
        currentSection == AppSection.notices ||
        currentSection == AppSection.sunday) {
      await loadCurrentNotices(refresh: true);
    }
  }

  Future<void> showTestNotification() async {
    await showOverlayAlert(
      title: '알림',
      body: '알림이 정상적으로 작동합니다.',
      payload: 'section:character',
    );
  }

  Future<void> saveNotificationSettings(NotificationSettings settings) async {
    await notificationSettingsStore.save(settings);
    if (!mounted) {
      return;
    }
    setState(() {
      notificationSettings = settings;
    });
  }

  Future<void> saveAppConfig(AppConfig config) async {
    await appConfigStore.save(config);
    if (!mounted) {
      return;
    }
    setState(() {
      appConfig = config;
      apiClient = ApiClient(
        baseUrl: config.apiBaseUrl,
        nexonApiKey: config.nexonApiKey,
      );
    });
  }

  Future<void> savePartySchedule(PartySchedule schedule) async {
    final existingSchedules = [
      for (final item in partySchedules)
        if (item.id != schedule.id) item,
    ];
    if (_hasDuplicatePartyBoss(existingSchedules, schedule.bossName)) {
      return;
    }
    final nextSchedules = [
      ...existingSchedules,
      schedule,
    ]..sort(_comparePartySchedules);

    await partyScheduleStore.save(nextSchedules);
    if (!mounted) {
      return;
    }
    setState(() {
      partySchedules = nextSchedules;
    });
  }

  Future<void> deletePartySchedule(PartySchedule schedule) async {
    final nextSchedules =
        partySchedules.where((item) => item.id != schedule.id).toList();
    await partyScheduleStore.save(nextSchedules);
    if (!mounted) {
      return;
    }
    setState(() {
      partySchedules = nextSchedules;
    });
  }

  void handleNotificationTap(String? payload) {
    if (!mounted) {
      return;
    }

    switch (payload) {
      case 'section:character':
        setState(() {
          currentSection = AppSection.character;
        });
      case 'section:scheduler':
        setState(() {
          currentSection = selectedCharacter == null
              ? AppSection.character
              : AppSection.scheduler;
        });
      case 'section:notices':
        setState(() {
          currentSection = AppSection.notices;
        });
      case 'section:party':
        setState(() {
          currentSection = AppSection.party;
        });
    }
  }

  Future<void> checkScheduledNotifications() async {
    if (!notificationSettings.enabled ||
        isCheckingScheduledNotifications ||
        (selectedCharacters.isEmpty && partySchedules.isEmpty)) {
      return;
    }

    isCheckingScheduledNotifications = true;
    try {
      final now = DateTime.now();
      await _checkPartyScheduleNotifications(now);

      if (now.hour != notificationSettings.reminderHour ||
          now.minute != notificationSettings.reminderMinute ||
          selectedCharacters.isEmpty) {
        return;
      }

      if (notificationSettings.dailyEnabled) {
        await _checkDailyLoginNotification(now);
      }
      if (notificationSettings.weeklyEnabled &&
          notificationSettings.weeklyWeekdays.contains(now.weekday)) {
        await _checkWeeklyReminderNotification(now);
      }
    } finally {
      isCheckingScheduledNotifications = false;
    }
  }

  Future<void> checkStartupScheduledNotifications() async {
    if (!notificationSettings.enabled || !notificationSettings.checkOnStartup) {
      return;
    }
    await runScheduledNotificationChecks(DateTime.now());
  }

  Future<void> checkNewNoticeNotifications() async {
    if (!notificationSettings.enabled ||
        !notificationSettings.noticeEnabled ||
        isCheckingNoticeNotifications) {
      return;
    }

    isCheckingNoticeNotifications = true;
    try {
      var currentItems = noticeItems;
      if (currentItems.isEmpty) {
        final fetchedItems = await apiClient.fetchCurrentNotices();
        currentItems = await _mergeCurrentNoticeItemsWithEventCache(
          fetchedItems,
          eventNoticeCache,
        );
      }

      final previousSnapshot = await notificationHistory.loadNoticeSnapshot();
      final currentSnapshot = {
        for (final item in currentItems)
          item.notificationKey: {
            'title': item.title,
            'type': item.displayType,
            'eventEndAt': item.eventEndAt,
          },
      };

      if (previousSnapshot.isEmpty) {
        await notificationHistory.saveNoticeSnapshot(currentSnapshot);
        return;
      }

      final newItems = currentItems
          .where((item) => !previousSnapshot.containsKey(item.notificationKey))
          .toList();
      final endedEvents = previousSnapshot.entries
          .where((entry) =>
              entry.value['type'] == 'event' &&
              _isSnapshotEventEnded(entry.value, DateTime.now()) &&
              !currentSnapshot.containsKey(entry.key))
          .map((entry) => entry.value['title'] ?? '')
          .where((title) => title.isNotEmpty)
          .toList();

      await notificationHistory.saveNoticeSnapshot(currentSnapshot);

      if (newItems.isEmpty && endedEvents.isEmpty) {
        return;
      }

      final title = _noticeChangeTitle(newItems, endedEvents);
      final body = _noticeChangeBody(newItems, endedEvents);

      await showOverlayAlert(
        title: title,
        body: body,
        payload: 'section:notices',
      );
    } on ApiException {
      // 공지 알림 확인 실패는 앱 사용을 막지 않는다.
    } finally {
      isCheckingNoticeNotifications = false;
    }
  }

  Future<void> runScheduledNotificationChecks(DateTime now) async {
    if (!notificationSettings.enabled ||
        isCheckingScheduledNotifications ||
        (selectedCharacters.isEmpty && partySchedules.isEmpty)) {
      return;
    }

    isCheckingScheduledNotifications = true;
    try {
      await _checkPartyScheduleNotifications(now);
      if (selectedCharacters.isEmpty) {
        return;
      }
      if (notificationSettings.dailyEnabled) {
        await _checkDailyLoginNotification(now);
      }
      if (notificationSettings.weeklyEnabled &&
          notificationSettings.weeklyWeekdays.contains(now.weekday)) {
        await _checkWeeklyReminderNotification(now);
      }
    } finally {
      isCheckingScheduledNotifications = false;
    }
  }

  Future<void> _checkPartyScheduleNotifications(DateTime now) async {
    final dueSchedules = <({PartySchedule schedule, String ruleKey})>[];
    for (final schedule in partySchedules) {
      final targetTime = schedule.currentScheduleFrom(now);
      final elapsed = now.difference(targetTime);
      if (_isPartyScheduleClearedBySnapshots(schedule, dashboardSnapshots) ||
          targetTime.isAfter(now) ||
          elapsed > const Duration(minutes: 30)) {
        continue;
      }

      final ruleKey =
          'party-schedule-${schedule.id}-${schedule.repeatType}-${_dateKey(targetTime)}-${schedule.hour}-${schedule.minute}';
      if (pendingPartyScheduleRuleKeys.contains(ruleKey) ||
          await notificationHistory.hasSent(ruleKey)) {
        continue;
      }

      dueSchedules.add((schedule: schedule, ruleKey: ruleKey));
    }

    if (dueSchedules.isEmpty) {
      return;
    }

    for (final item in dueSchedules) {
      pendingPartyScheduleRuleKeys.add(item.ruleKey);
    }

    await showOverlayAlert(
      title: dueSchedules.length == 1
          ? '파티 일정 시간이 됐어요'
          : '파티 일정 ${dueSchedules.length}개 시간이 됐어요',
      body: dueSchedules
          .map((item) => _partyScheduleNotificationText(item.schedule))
          .join('\n'),
      payload: 'section:party',
    );

    for (final item in dueSchedules) {
      await notificationHistory.markSent(item.ruleKey);
      pendingPartyScheduleRuleKeys.remove(item.ruleKey);
    }
  }

  String _partyScheduleNotificationText(PartySchedule schedule) {
    final memberText =
        schedule.members.isEmpty ? '등록된 파티원 없음' : schedule.members.join(', ');
    return '${schedule.difficulty.toUpperCase()} ${schedule.bossName} - $memberText';
  }

  Future<void> _checkDailyLoginNotification(DateTime now) async {
    final ruleKey = 'daily-login-${_dateKey(now)}';
    if (await notificationHistory.hasSent(ruleKey)) {
      return;
    }

    final missingCharacters = <NexonCharacterSummary>[];
    for (final character in notificationTargetCharacters) {
      try {
        final snapshot = await apiClient.fetchScheduler(character.ocid);
        if (!snapshot.hasDailyItems) {
          missingCharacters.add(character);
        }
      } on ApiException {
        // A failed lookup should not turn into a missed-login notification.
      }
    }

    if (missingCharacters.isEmpty) {
      return;
    }

    await showOverlayAlert(
      title: '오늘 접속 기록이 없어요',
      body: '${_characterNames(missingCharacters)} 접속 후 일일 숙제를 확인해주세요.',
      payload: 'section:scheduler',
    );
    await notificationHistory.markSent(ruleKey);
  }

  Future<void> _checkWeeklyReminderNotification(DateTime now) async {
    final ruleKey = 'weekly-reminder-${_dateKey(now)}';
    if (await notificationHistory.hasSent(ruleKey)) {
      return;
    }

    final incompleteCharacters = <NexonCharacterSummary>[];
    for (final character in notificationTargetCharacters) {
      try {
        final snapshot = await apiClient.fetchScheduler(character.ocid);
        final cachedSnapshot = await schedulerCache.load(character.ocid);
        final displayedSnapshot = cachedSnapshot == null
            ? snapshot
            : snapshot.withCachedEmptySections(cachedSnapshot);
        final hasIncompleteWeeklyContent =
            displayedSnapshot.weeklyItems.any((item) => !item.done);
        final hasIncompleteWeeklyBoss = displayedSnapshot.bossItems
            .where(_isWeeklyBoss)
            .any((item) => !item.done);
        if (hasIncompleteWeeklyContent || hasIncompleteWeeklyBoss) {
          incompleteCharacters.add(character);
        }
      } on ApiException {
        // A failed lookup should not turn into an unfinished-content notification.
      }
    }

    if (incompleteCharacters.isEmpty) {
      return;
    }

    await showOverlayAlert(
      title: '이번 주 숙제가 남아 있어요',
      body: '${_characterNames(incompleteCharacters)} 목요일 전에 주간 콘텐츠를 확인해주세요.',
      payload: 'section:scheduler',
    );
    await notificationHistory.markSent(ruleKey);
  }

  List<NexonCharacterSummary> get notificationTargetCharacters {
    return selectedCharacters
        .where(
            (character) => !notificationDisabledOcids.contains(character.ocid))
        .toList();
  }

  bool _isWeeklyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.trim().toLowerCase();
    return cycle == 'weekly' || cycle == 'week' || cycle == '주간';
  }

  String _dateKey(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day';
  }

  String _characterNames(List<NexonCharacterSummary> characters) {
    if (characters.length == 1) {
      return '${characters.first.characterName}님의';
    }
    return '${characters.first.characterName}님 외 ${characters.length - 1}명의';
  }

  String _newNoticeTitle(NoticeItemSummary item) {
    return switch (item.displayType) {
      'event' => '새 이벤트가 올라왔어요',
      'cashshop' => '새 캐시샵 공지가 올라왔어요',
      'update' => '새 업데이트 공지가 올라왔어요',
      'maintenance' => '새 점검 공지가 올라왔어요',
      _ => '새 공지가 올라왔어요',
    };
  }

  String _noticeChangeTitle(
    List<NoticeItemSummary> newItems,
    List<String> endedEvents,
  ) {
    final newEvents = newItems.where((item) => item.displayType == 'event');
    if (newEvents.isNotEmpty && endedEvents.isNotEmpty) {
      return '이벤트 변경사항이 있어요';
    }
    if (newEvents.isNotEmpty) {
      return '새 이벤트가 올라왔어요';
    }
    if (endedEvents.isNotEmpty) {
      return '이벤트가 종료됐어요';
    }
    return newItems.length == 1
        ? _newNoticeTitle(newItems.first)
        : '새 공지가 올라왔어요';
  }

  String _noticeChangeBody(
    List<NoticeItemSummary> newItems,
    List<String> endedEvents,
  ) {
    final lines = <String>[];
    final newEvents = newItems.where((item) => item.displayType == 'event');
    final newNotices = newItems.where((item) => item.displayType != 'event');

    _appendNoticeChangeLines(
      lines,
      header: '새 이벤트',
      titles: newEvents.map((item) => item.title).toList(),
    );
    _appendNoticeChangeLines(
      lines,
      header: '종료된 이벤트',
      titles: endedEvents,
    );
    _appendNoticeChangeLines(
      lines,
      header: '새 공지',
      titles: newNotices.map((item) => item.title).toList(),
    );

    return lines.join('\n');
  }

  void _appendNoticeChangeLines(
    List<String> lines, {
    required String header,
    required List<String> titles,
  }) {
    if (titles.isEmpty) {
      return;
    }

    lines.add('$header:');
    for (final title in titles.take(3)) {
      lines.add('- $title');
    }
    if (titles.length > 3) {
      lines.add('- 외 ${titles.length - 3}건');
    }
  }

  void selectSection(AppSection section) {
    if (section != AppSection.dashboard &&
        section != AppSection.character &&
        section != AppSection.party &&
        section != AppSection.settings &&
        selectedCharacter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캐릭터를 먼저 선택해주세요.')),
      );
      return;
    }

    setState(() {
      currentSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (appConfig.nexonApiKey.trim().isEmpty) {
      return _NexonApiSetupScreen(
        onSave: (apiKey) async {
          await saveAppConfig(appConfig.copyWith(nexonApiKey: apiKey));
          if (!mounted) {
            return;
          }
          setState(() {
            currentSection = AppSection.character;
            errorMessage = null;
          });
        },
      );
    }

    final alert = overlayAlert;
    return Stack(
      children: [
        Scaffold(
          body: Row(
            children: [
              _AppSidebar(
                currentSection: currentSection,
                selectedCharacter: selectedCharacter,
                noticeItems: noticeItems,
                onAddCharacter: () => selectSection(AppSection.character),
                onSelectSection: selectSection,
              ),
              Expanded(
                child: _MainPanel(
                  currentSection: currentSection,
                  selectedCharacter: selectedCharacter,
                  selectedCharacters: selectedCharacters,
                  partySchedules: partySchedules,
                  schedulerSnapshot: schedulerSnapshot,
                  dashboardSnapshots: dashboardSnapshots,
                  noticeItems: noticeItems,
                  sundayEvent: sundayEvent,
                  isLoading: isLoading,
                  isSchedulerLoading: isSchedulerLoading,
                  isSchedulerRefreshing: isSchedulerRefreshing,
                  isNoticeLoading: isNoticeLoading,
                  isNoticeRefreshing: isNoticeRefreshing,
                  errorMessage: errorMessage,
                  schedulerErrorMessage: schedulerErrorMessage,
                  noticeErrorMessage: noticeErrorMessage,
                  onAddCharacter: openCharacterPicker,
                  onRefresh: refreshCurrentSection,
                  onTestNotification: showTestNotification,
                  notificationSettings: notificationSettings,
                  appConfig: appConfig,
                  onNotificationSettingsChanged: saveNotificationSettings,
                  onAppConfigChanged: saveAppConfig,
                  onSelectSection: selectSection,
                  onSelectCharacter: selectCharacter,
                  onOpenCharacterScheduler: openCharacterScheduler,
                  onDeleteCharacter: deleteCharacter,
                  onMoveCharacter: moveCharacterToIndex,
                  notificationDisabledOcids: notificationDisabledOcids,
                  onToggleCharacterNotification: toggleCharacterNotification,
                  onSavePartySchedule: savePartySchedule,
                  onDeletePartySchedule: deletePartySchedule,
                ),
              ),
            ],
          ),
        ),
        if (alert != null)
          Positioned.fill(
            child: _OverlayAlertWindow(
              alert: alert,
              onTodayMuteChanged: notificationHistory.setMutedToday,
              onConfirm: () => unawaited(closeOverlayAlert()),
            ),
          ),
      ],
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.currentSection,
    required this.selectedCharacter,
    required this.noticeItems,
    required this.onAddCharacter,
    required this.onSelectSection,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final List<NoticeItemSummary> noticeItems;
  final VoidCallback onAddCharacter;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final hasCharacter = selectedCharacter != null;

    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SidebarBrand(),
              const SizedBox(height: 18),
              _SidebarNavItem(
                section: AppSection.dashboard,
                selected: currentSection == AppSection.dashboard,
                enabled: true,
                onPressed: () => onSelectSection(AppSection.dashboard),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _SidebarCharacterButton(
                selectedCharacter: selectedCharacter,
                selected: currentSection == AppSection.character,
                onPressed: onAddCharacter,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Divider(height: 1, color: AppColors.border),
              ),
              for (final section in AppSection.values)
                if (section != AppSection.dashboard &&
                    section != AppSection.character &&
                    section != AppSection.settings) ...[
                  _SidebarNavItem(
                    section: section,
                    label: _sectionLabel(section, noticeItems),
                    selected: currentSection == section,
                    enabled: hasCharacter || section == AppSection.party,
                    onPressed: () => onSelectSection(section),
                  ),
                  if (section == AppSection.party)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                      child: Divider(height: 1, color: AppColors.border),
                    ),
                ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _SidebarNavItem(
                section: AppSection.settings,
                label: _sectionLabel(AppSection.settings, noticeItems),
                selected: currentSection == AppSection.settings,
                enabled: true,
                onPressed: () => onSelectSection(AppSection.settings),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Image.asset(
            'assets/images/app_logo.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '메이플 숙제알리미',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '놓친 숙제, 이제 안 놓치게',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarCharacterButton extends StatelessWidget {
  const _SidebarCharacterButton({
    required this.selectedCharacter,
    required this.selected,
    required this.onPressed,
  });

  final NexonCharacterSummary? selectedCharacter;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final character = selectedCharacter;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.navBorder : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: character == null
                    ? const ColoredBox(
                        color: Color(0xFFFFF4EC),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: AppColors.navAccent,
                        ),
                      )
                    : _WorldImage(character: character, radius: 12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character == null
                          ? '캐릭터 추가'
                          : _displayCharacterName(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      character == null
                          ? '먼저 알림 대상을 선택'
                          : _characterDescription(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.section,
    this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final AppSection section;
  final String? label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.disabled
        : selected
            ? Colors.white
            : AppColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color:
                  selected && enabled ? AppColors.navAccent : AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected && enabled
                    ? AppColors.navAccent
                    : AppColors.navBorder,
              ),
            ),
            child: Text(
              label ?? section.label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.currentSection,
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.partySchedules,
    required this.schedulerSnapshot,
    required this.dashboardSnapshots,
    required this.noticeItems,
    required this.sundayEvent,
    required this.isLoading,
    required this.isSchedulerLoading,
    required this.isSchedulerRefreshing,
    required this.isNoticeLoading,
    required this.isNoticeRefreshing,
    required this.errorMessage,
    required this.schedulerErrorMessage,
    required this.noticeErrorMessage,
    required this.onAddCharacter,
    required this.onRefresh,
    required this.onTestNotification,
    required this.notificationSettings,
    required this.appConfig,
    required this.onNotificationSettingsChanged,
    required this.onAppConfigChanged,
    required this.onSelectSection,
    required this.onSelectCharacter,
    required this.onOpenCharacterScheduler,
    required this.onDeleteCharacter,
    required this.onMoveCharacter,
    required this.notificationDisabledOcids,
    required this.onToggleCharacterNotification,
    required this.onSavePartySchedule,
    required this.onDeletePartySchedule,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final List<PartySchedule> partySchedules;
  final SchedulerSnapshot? schedulerSnapshot;
  final Map<String, SchedulerSnapshot> dashboardSnapshots;
  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool isLoading;
  final bool isSchedulerLoading;
  final bool isSchedulerRefreshing;
  final bool isNoticeLoading;
  final bool isNoticeRefreshing;
  final String? errorMessage;
  final String? schedulerErrorMessage;
  final String? noticeErrorMessage;
  final VoidCallback onAddCharacter;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTestNotification;
  final NotificationSettings notificationSettings;
  final AppConfig appConfig;
  final Future<void> Function(NotificationSettings settings)
      onNotificationSettingsChanged;
  final Future<void> Function(AppConfig config) onAppConfigChanged;
  final ValueChanged<AppSection> onSelectSection;
  final ValueChanged<NexonCharacterSummary> onSelectCharacter;
  final ValueChanged<NexonCharacterSummary> onOpenCharacterScheduler;
  final ValueChanged<NexonCharacterSummary> onDeleteCharacter;
  final void Function(NexonCharacterSummary character, int targetIndex)
      onMoveCharacter;
  final Set<String> notificationDisabledOcids;
  final ValueChanged<NexonCharacterSummary> onToggleCharacterNotification;
  final Future<void> Function(PartySchedule schedule) onSavePartySchedule;
  final Future<void> Function(PartySchedule schedule) onDeletePartySchedule;

  @override
  Widget build(BuildContext context) {
    final sectionLabel = _sectionLabel(currentSection, noticeItems);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  sectionLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (currentSection == AppSection.scheduler ||
                    currentSection == AppSection.events ||
                    currentSection == AppSection.notices ||
                    currentSection == AppSection.sunday) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: '강제 새로고침',
                    child: _RefreshButton(
                      refreshing: currentSection == AppSection.scheduler
                          ? isSchedulerRefreshing
                          : isNoticeRefreshing,
                      enabled: !(currentSection == AppSection.scheduler
                          ? isSchedulerLoading || isSchedulerRefreshing
                          : isNoticeLoading || isNoticeRefreshing),
                      onPressed: () => onRefresh(),
                    ),
                  ),
                ],
                const Spacer(),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: switch (currentSection) {
                AppSection.dashboard => _DashboardPanel(
                    characters: selectedCharacters,
                    snapshots: dashboardSnapshots,
                    partySchedules: partySchedules,
                    onOpenCharacterScheduler: onOpenCharacterScheduler,
                  ),
                AppSection.character => _CharacterSelectPanel(
                    selectedCharacter: selectedCharacter,
                    selectedCharacters: selectedCharacters,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onAddCharacter: onAddCharacter,
                    onSelectCharacter: onSelectCharacter,
                    onDeleteCharacter: onDeleteCharacter,
                    onMoveCharacter: onMoveCharacter,
                    notificationDisabledOcids: notificationDisabledOcids,
                    onToggleCharacterNotification:
                        onToggleCharacterNotification,
                  ),
                AppSection.party => _PartySchedulePanel(
                    schedules: partySchedules,
                    characters: selectedCharacters,
                    dashboardSnapshots: dashboardSnapshots,
                    onSave: onSavePartySchedule,
                    onDelete: onDeletePartySchedule,
                  ),
                AppSection.settings => _SettingsPanel(
                    settings: notificationSettings,
                    appConfig: appConfig,
                    onChanged: onNotificationSettingsChanged,
                    onAppConfigChanged: onAppConfigChanged,
                    onTestNotification: onTestNotification,
                  ),
                _ => _LockedFeaturePanel(
                    section: currentSection,
                    selectedCharacter: selectedCharacter,
                    schedulerSnapshot: schedulerSnapshot,
                    noticeItems: noticeItems,
                    sundayEvent: sundayEvent,
                    schedulerLoading: isSchedulerLoading,
                    noticeLoading: isNoticeLoading,
                    schedulerErrorMessage: schedulerErrorMessage,
                    noticeErrorMessage: noticeErrorMessage,
                    onSelectSection: onSelectSection,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.settings,
    required this.appConfig,
    required this.onChanged,
    required this.onAppConfigChanged,
    required this.onTestNotification,
  });

  final NotificationSettings settings;
  final AppConfig appConfig;
  final Future<void> Function(NotificationSettings settings) onChanged;
  final Future<void> Function(AppConfig config) onAppConfigChanged;
  final Future<void> Function() onTestNotification;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late NotificationSettings draft;
  late AppConfig configDraft;
  late final TextEditingController hourController;
  late final TextEditingController minuteController;
  late final TextEditingController nexonApiKeyController;
  AppVersionInfo? updateInfo;
  String? updateMessage;
  var checkingUpdate = false;
  var saving = false;
  var showNexonApiKey = false;

  @override
  void initState() {
    super.initState();
    draft = widget.settings;
    configDraft = widget.appConfig;
    hourController =
        TextEditingController(text: _twoDigits(draft.reminderHour));
    minuteController =
        TextEditingController(text: _twoDigits(draft.reminderMinute));
    nexonApiKeyController =
        TextEditingController(text: configDraft.nexonApiKey);
  }

  @override
  void didUpdateWidget(covariant _SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && !saving) {
      draft = widget.settings;
      hourController.text = _twoDigits(draft.reminderHour);
      minuteController.text = _twoDigits(draft.reminderMinute);
    }
    if (oldWidget.appConfig != widget.appConfig && !saving) {
      configDraft = widget.appConfig;
      nexonApiKeyController.text = configDraft.nexonApiKey;
    }
  }

  @override
  void dispose() {
    hourController.dispose();
    minuteController.dispose();
    nexonApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SettingsSectionTitle('예약 알림 시간', small: true),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: saving ? null : _pickReminderTime,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(
                  color: AppColors.navBorder,
                  width: 1.2,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child:
                  Text(_formatTime(draft.reminderHour, draft.reminderMinute)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hourController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '시',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.navAccent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: minuteController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '분',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.navAccent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _NotificationSettingSwitch(
              title: '알림 ON/OFF',
              subtitle: '전체 알림을 한 번에 켜거나 끕니다.',
              value: draft.enabled,
              saving: saving,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(enabled: value);
              }),
            ),
            _NotificationSettingSwitch(
              title: '앱 시작 시 알림',
              subtitle: '컴퓨터를 켤 때 놓친 알림을 한 번 확인합니다.',
              value: draft.checkOnStartup,
              saving: saving || !draft.enabled,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(checkOnStartup: value);
              }),
            ),
            _NotificationSettingSwitch(
              title: '일간 알림',
              subtitle: '오늘 접속 기록과 일일 콘텐츠를 확인합니다.',
              value: draft.dailyEnabled,
              saving: saving || !draft.enabled,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(dailyEnabled: value);
              }),
            ),
            _NotificationSettingSwitch(
              title: '주간 알림',
              subtitle: '이번 주 완료되지 않은 주간 콘텐츠를 확인합니다.',
              value: draft.weeklyEnabled,
              saving: saving || !draft.enabled,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(
                  weeklyEnabled: value,
                  weeklyWeekdays: value
                      ? (draft.weeklyWeekdays.isEmpty
                          ? NotificationSettings.defaults.weeklyWeekdays
                          : draft.weeklyWeekdays)
                      : const [],
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final weekday in const [
                    DateTime.monday,
                    DateTime.tuesday,
                    DateTime.wednesday,
                    DateTime.thursday,
                    DateTime.friday,
                    DateTime.saturday,
                    DateTime.sunday,
                  ])
                    FilterChip(
                      label: Text(_weekdayLabel(weekday)),
                      selected: draft.weeklyWeekdays.contains(weekday),
                      showCheckmark: false,
                      onSelected: saving || !draft.enabled
                          ? null
                          : (selected) {
                              final weekdays = draft.weeklyWeekdays.toSet();
                              if (selected) {
                                weekdays.add(weekday);
                              } else {
                                weekdays.remove(weekday);
                              }
                              final sortedWeekdays = weekdays.toList()..sort();
                              setState(() {
                                draft = draft.copyWith(
                                  weeklyEnabled: sortedWeekdays.isNotEmpty,
                                  weeklyWeekdays: sortedWeekdays,
                                );
                              });
                            },
                      selectedColor:
                          AppColors.navAccent.withValues(alpha: 0.15),
                      side: BorderSide(
                        color: draft.weeklyWeekdays.contains(weekday)
                            ? AppColors.navAccent
                            : AppColors.border,
                      ),
                      labelStyle: TextStyle(
                        color: draft.weeklyWeekdays.contains(weekday)
                            ? AppColors.navAccent
                            : AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            _NotificationSettingSwitch(
              title: '월간 알림',
              subtitle: '월간 콘텐츠 알림 기준으로 사용합니다.',
              value: draft.monthlyEnabled,
              saving: saving || !draft.enabled,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(monthlyEnabled: value);
              }),
            ),
            _NotificationSettingSwitch(
              title: '공지/이벤트 알림',
              subtitle: '새 공지, 이벤트, 캐시샵, 업데이트가 올라오면 알려줍니다.',
              value: draft.noticeEnabled,
              saving: saving || !draft.enabled,
              onChanged: (value) => setState(() {
                draft = draft.copyWith(noticeEnabled: value);
              }),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: saving ? null : widget.onTestNotification,
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: const Text('알림 테스트'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(
                  color: AppColors.navBorder,
                  width: 1.2,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const _SettingsSectionTitle('넥슨 API'),
            const SizedBox(height: 8),
            TextField(
              controller: nexonApiKeyController,
              enabled: !saving,
              obscureText: !showNexonApiKey,
              decoration: InputDecoration(
                labelText: '넥슨 OpenAPI 키',
                hintText: 'Nexon OpenAPI 키를 입력해주세요.',
                helperText: '캐릭터 목록과 스케줄러 조회에 사용합니다.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.navAccent),
                ),
                suffixIcon: IconButton(
                  tooltip: showNexonApiKey ? '숨기기' : '보기',
                  onPressed: saving
                      ? null
                      : () => setState(() {
                            showNexonApiKey = !showNexonApiKey;
                          }),
                  icon: Icon(
                    showNexonApiKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const _SettingsSectionTitle('앱 업데이트'),
            const SizedBox(height: 8),
            Text(
              updateMessage ?? '현재 버전 $appCurrentVersion',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (updateInfo?.notes.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(
                updateInfo!.notes,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        saving || checkingUpdate ? null : _checkUpdateVersion,
                    icon: checkingUpdate
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('버전 확인'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canOpenUpdate(updateInfo)
                        ? () => _openUpdate(updateInfo!)
                        : null,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('업데이트'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: saving ? null : _resetDraft,
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _BoundedTimePickerDialog(
        initialTime: TimeOfDay(
          hour: draft.reminderHour,
          minute: draft.reminderMinute,
        ),
      ),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      draft = draft.copyWith(
        reminderHour: picked.hour,
        reminderMinute: picked.minute,
      );
      hourController.text = _twoDigits(picked.hour);
      minuteController.text = _twoDigits(picked.minute);
    });
  }

  Future<void> _checkUpdateVersion() async {
    setState(() {
      checkingUpdate = true;
      updateMessage = '최신 버전을 확인하고 있어요.';
    });
    try {
      final info = await ApiClient(baseUrl: configDraft.apiBaseUrl)
          .fetchAppVersionInfo();
      final hasUpdate = _isNewerVersion(info.version, appCurrentVersion);
      setState(() {
        updateInfo = info;
        updateMessage = hasUpdate
            ? '새 버전 ${info.version}을 사용할 수 있어요.'
            : '현재 최신 버전을 사용 중이에요.';
      });
    } on ApiException catch (error) {
      setState(() {
        updateMessage = error.message;
      });
    } finally {
      setState(() {
        checkingUpdate = false;
      });
    }
  }

  Future<void> _openUpdate(AppVersionInfo info) async {
    final opened = await _openDownloadUrl(info);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('다운로드 주소를 열지 못해서 클립보드에 복사했어요.'),
        ),
      );
    }
  }

  Future<void> _save() async {
    final normalized = _normalizedTime(
      hourController.text,
      minuteController.text,
    );
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시간은 0~23, 분은 0~59로 입력해주세요.')),
      );
      return;
    }
    setState(() {
      saving = true;
      configDraft = configDraft.copyWith(
        nexonApiKey: nexonApiKeyController.text.trim(),
      );
      draft = draft.copyWith(
        reminderHour: normalized.hour,
        reminderMinute: normalized.minute,
      );
    });
    await widget.onChanged(draft);
    await widget.onAppConfigChanged(configDraft);
    if (mounted) {
      setState(() {
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장했어요.')),
      );
    }
  }

  void _resetDraft() {
    setState(() {
      draft = widget.settings;
      configDraft = widget.appConfig;
      hourController.text = _twoDigits(draft.reminderHour);
      minuteController.text = _twoDigits(draft.reminderMinute);
      nexonApiKeyController.text = configDraft.nexonApiKey;
    });
  }

  String _formatTime(int hour, int minute) {
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$period $displayHour:${_twoDigits(minute)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '월',
      DateTime.tuesday => '화',
      DateTime.wednesday => '수',
      DateTime.thursday => '목',
      DateTime.friday => '금',
      DateTime.saturday => '토',
      DateTime.sunday => '일',
      _ => '',
    };
  }

  TimeOfDay? _normalizedTime(String hourText, String minuteText) {
    final hour = int.tryParse(hourText);
    final minute = int.tryParse(minuteText);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  bool _canOpenUpdate(AppVersionInfo? info) {
    return info != null &&
        info.downloadUrl.isNotEmpty &&
        _isNewerVersion(info.version, appCurrentVersion);
  }

  Future<bool> _openDownloadUrl(AppVersionInfo info) async {
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
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await windowManager.destroy();
      exit(0);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: trimmedUrl));
      return false;
    }
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
  "/LOG=\$logPath"
)

try {
  Start-Process -FilePath \$installer -ArgumentList \$arguments -Wait -WindowStyle Hidden
} catch {}

Start-Sleep -Milliseconds 700
if (Test-Path -LiteralPath \$appExecutable) {
  try {
    Start-Process -FilePath \$appExecutable
  } catch {}
}
''';
    final encodedScript = base64Encode(
      script.codeUnits
          .expand((unit) => [unit & 0xff, (unit >> 8) & 0xff])
          .toList(),
    );

    await Process.start(
      powershellCommand,
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        encodedScript,
      ],
      mode: ProcessStartMode.detached,
    );
  }

  String _powerShellLiteral(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  bool _isNewerVersion(String latestVersion, String currentVersion) {
    final latest = _versionParts(latestVersion);
    final current = _versionParts(currentVersion);
    for (var index = 0;
        index < math.max(latest.length, current.length);
        index++) {
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

  List<int> _versionParts(String version) {
    final coreVersion = version.split('+').first;
    return coreVersion
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.text, {this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.text,
        fontSize: small ? 14 : 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _BoundedTimePickerDialog extends StatefulWidget {
  const _BoundedTimePickerDialog({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_BoundedTimePickerDialog> createState() =>
      _BoundedTimePickerDialogState();
}

class _BoundedTimePickerDialogState extends State<_BoundedTimePickerDialog> {
  late int _hour;
  late int _minute;
  late bool _isPm;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;

  int get _displayHour {
    final hour = _hour % 12;
    return hour == 0 ? 12 : hour;
  }

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
    _isPm = _hour >= 12;
    _hourController = TextEditingController(text: _displayHour.toString());
    _minuteController = TextEditingController(
      text: _minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _setDisplayHour(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 12) {
      return;
    }
    setState(() {
      _hour = _to24Hour(parsed, _isPm);
    });
  }

  void _setMinuteInput(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 59) {
      return;
    }
    setState(() {
      _minute = parsed;
    });
  }

  void _setMinute(int minute) {
    setState(() {
      _minute = minute;
      _minuteController.text = minute.toString().padLeft(2, '0');
    });
  }

  void _setPeriod(bool isPm) {
    setState(() {
      _isPm = isPm;
      _hour = _to24Hour(_displayHour, _isPm);
    });
  }

  int _to24Hour(int displayHour, bool isPm) {
    final normalized = displayHour % 12;
    return isPm ? normalized + 12 : normalized;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('알림 시간 선택'),
      content: SizedBox(
        width: 520,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hourController,
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: const InputDecoration(
                            labelText: '시',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _setDisplayHour,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          ':',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _minuteController,
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: const InputDecoration(
                            labelText: '분',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _setMinuteInput,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('AM')),
                      ButtonSegment(value: true, label: Text('PM')),
                    ],
                    selected: {_isPm},
                    style: ButtonStyle(
                      foregroundColor:
                          WidgetStateProperty.resolveWith<Color>((states) {
                        return states.contains(WidgetState.selected)
                            ? Colors.white
                            : AppColors.text;
                      }),
                      backgroundColor:
                          WidgetStateProperty.resolveWith<Color>((states) {
                        return states.contains(WidgetState.selected)
                            ? AppColors.navAccent
                            : Colors.white;
                      }),
                    ),
                    onSelectionChanged: (selected) {
                      _setPeriod(selected.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '시/분을 직접 입력하거나 시계에서 분을 선택하세요.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 28),
            _ClockDial(minute: _minute, onMinuteChanged: _setMinute),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute));
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class _ClockDial extends StatelessWidget {
  const _ClockDial({required this.minute, required this.onMinuteChanged});

  static const double size = 240;
  static const double interactiveRadius = 112;

  final int minute;
  final ValueChanged<int> onMinuteChanged;

  void _handlePointer(Offset localPosition) {
    const center = Offset(size / 2, size / 2);
    final distance = (localPosition - center).distance;
    if (distance > interactiveRadius) {
      return;
    }

    final angle = math.atan2(
      localPosition.dy - center.dy,
      localPosition.dx - center.dx,
    );
    final normalized = (angle + math.pi / 2 + math.pi * 2) % (math.pi * 2);
    final rawMinute = ((normalized / (math.pi * 2)) * 60).round() % 60;
    final roundedMinute = ((rawMinute / 5).round() * 5) % 60;
    onMinuteChanged(roundedMinute);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (details) => _handlePointer(details.localPosition),
      onPanUpdate: (details) => _handlePointer(details.localPosition),
      child: CustomPaint(
        size: const Size.square(size),
        painter: _ClockDialPainter(minute: minute),
      ),
    );
  }
}

class _ClockDialPainter extends CustomPainter {
  const _ClockDialPainter({required this.minute});

  final int minute;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final backgroundPaint = Paint()..color = AppColors.navAccent.withAlpha(18);
    final handPaint = Paint()
      ..color = AppColors.navAccent
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final selectedPaint = Paint()..color = AppColors.navAccent;
    final dotPaint = Paint()..color = AppColors.navAccent;

    canvas.drawCircle(center, radius, backgroundPaint);

    final selectedAngle = (minute / 60) * math.pi * 2 - math.pi / 2;
    final selectedOffset = Offset(
      center.dx + math.cos(selectedAngle) * (radius - 38),
      center.dy + math.sin(selectedAngle) * (radius - 38),
    );
    canvas.drawLine(center, selectedOffset, handPaint);
    canvas.drawCircle(center, 4, dotPaint);
    canvas.drawCircle(selectedOffset, 24, selectedPaint);

    for (var value = 0; value < 60; value += 5) {
      final angle = (value / 60) * math.pi * 2 - math.pi / 2;
      final offset = Offset(
        center.dx + math.cos(angle) * (radius - 38),
        center.dy + math.sin(angle) * (radius - 38),
      );
      final isSelected = value == minute;
      final textPainter = TextPainter(
        text: TextSpan(
          text: value.toString().padLeft(2, '0'),
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.text,
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClockDialPainter oldDelegate) {
    return oldDelegate.minute != minute;
  }
}

class _NotificationSettingSwitch extends StatelessWidget {
  const _NotificationSettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: saving ? null : onChanged,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.navAccent,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(subtitle),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.refreshing,
    required this.enabled,
    required this.onPressed,
  });

  final bool refreshing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.navAccent,
              ),
            )
          : const Icon(Icons.refresh_rounded),
      color: AppColors.navAccent,
      disabledColor: AppColors.disabled,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.characters,
    required this.snapshots,
    required this.partySchedules,
    required this.onOpenCharacterScheduler,
  });

  final List<NexonCharacterSummary> characters;
  final Map<String, SchedulerSnapshot> snapshots;
  final List<PartySchedule> partySchedules;
  final ValueChanged<NexonCharacterSummary> onOpenCharacterScheduler;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return const _DashboardEmptyState(
        message: '등록된 캐릭터가 없습니다.\n캐릭터 선택에서 알림 대상을 추가해주세요.',
      );
    }

    var weeklyBossClearCount = 0;
    var loadedCharacterCount = 0;
    for (final character in characters) {
      final snapshot = snapshots[character.ocid];
      if (snapshot == null) {
        continue;
      }
      loadedCharacterCount++;
      final weeklyBosses =
          snapshot.bossItems.where(_isDashboardWeeklyBoss).toList();
      weeklyBossClearCount += snapshot.weeklyBossClearCount ??
          weeklyBosses.where((item) => item.done).length;
    }

    final weeklyContentCharacters = <String, List<String>>{};
    for (final character in characters) {
      final snapshot = snapshots[character.ocid];
      if (snapshot == null) {
        continue;
      }
      for (final item in snapshot.weeklyItems) {
        if (_isSharedWeeklyContentItem(item)) {
          continue;
        }
        weeklyContentCharacters.putIfAbsent(item.title, () => []);
        final isSuro = _isGuildSuroItem(item);
        final isCompleted = isSuro ? (item.currentCount ?? 0) >= 1 : item.done;
        if (isCompleted) {
          final label = isSuro
              ? '${character.characterName} · ${item.currentCount}점'
              : character.characterName;
          weeklyContentCharacters[item.title]!.add(label);
        }
      }
    }

    final monsterParkUsage = _buildMonsterParkUsage(characters, snapshots);
    final sharedContentUsage = _buildSharedWeeklyContentUsage(
      characters,
      snapshots,
    );

    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashboardSectionTitle(
            title: '주간 보스 현황',
            subtitle: '등록된 캐릭터당 주 12개 · 처치 기록 기준입니다.',
          ),
          const SizedBox(height: 12),
          _AccountBossSummary(
            clearCount: weeklyBossClearCount,
            clearLimit: characters.length * 12,
            loadedCharacterCount: loadedCharacterCount,
            totalCharacterCount: characters.length,
          ),
          const SizedBox(height: 30),
          const _DashboardSectionTitle(
            title: '몬스터파크',
            subtitle: '월드당 일 14회 제한이며 등록된 캐릭터를 함께 표시합니다.',
          ),
          const SizedBox(height: 12),
          _MonsterParkSummary(items: monsterParkUsage),
          const SizedBox(height: 30),
          const _DashboardSectionTitle(
            title: '캐릭터별 진행 현황',
            subtitle: '등록한 캐릭터의 주간 보스와 일일 콘텐츠 완료 수',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 18) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final character in characters)
                    SizedBox(
                      width: cardWidth,
                      child: _CharacterProgressCard(
                        character: character,
                        snapshot: snapshots[character.ocid],
                        partySchedules: partySchedules,
                        onOpenScheduler: () =>
                            onOpenCharacterScheduler(character),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 30),
          const _DashboardSectionTitle(
            title: '주간 콘텐츠 완료 캐릭터',
            subtitle: '주간 제한 콘텐츠를 어느 캐릭터로 완료했는지 확인합니다.',
          ),
          const SizedBox(height: 12),
          _SharedWeeklyContentSummary(items: sharedContentUsage),
          const SizedBox(height: 18),
          _WeeklyContentCharacterList(
            items: weeklyContentCharacters,
            hasSchedulerData: snapshots.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  const _DashboardSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AccountBossSummary extends StatelessWidget {
  const _AccountBossSummary({
    required this.clearCount,
    required this.clearLimit,
    required this.loadedCharacterCount,
    required this.totalCharacterCount,
  });

  final int clearCount;
  final int clearLimit;
  final int loadedCharacterCount;
  final int totalCharacterCount;

  @override
  Widget build(BuildContext context) {
    if (loadedCharacterCount == 0) {
      return const _DashboardEmptyState(
        message: '주간 보스 데이터를 아직 불러오지 못했습니다.\n캐릭터의 스케쥴러를 조회하면 현황이 표시됩니다.',
      );
    }

    final count = clearCount;
    final limit = clearLimit;
    final progress = limit == 0 ? 0.0 : (count / limit).clamp(0.0, 1.0);
    final percentage = (progress * 100).round();
    final remaining = (limit - count).clamp(0, limit);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            height: 116,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 12,
                    backgroundColor: AppColors.selected,
                    color: AppColors.navAccent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      '처치 완료',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이번주 처치한 주간 보스',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count / $limit',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '조회된 캐릭터 $loadedCharacterCount / $totalCharacterCount명 · 처치 기록 기준 · 남은 주간 보스 $remaining마리',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterProgressCard extends StatelessWidget {
  const _CharacterProgressCard({
    required this.character,
    required this.snapshot,
    required this.partySchedules,
    required this.onOpenScheduler,
  });

  final NexonCharacterSummary character;
  final SchedulerSnapshot? snapshot;
  final List<PartySchedule> partySchedules;
  final VoidCallback onOpenScheduler;

  @override
  Widget build(BuildContext context) {
    if (snapshot == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _dashboardCardDecoration(),
        child: _DashboardCharacterHeader(
            character: character,
            onTap: onOpenScheduler,
            child: const Text(
              '스케쥴러 데이터가 없습니다.',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            )),
      );
    }

    final weeklyBosses = snapshot!.bossItems
        .where((item) => _isDashboardWeeklyBoss(item))
        .toList();
    final completedBosses = snapshot!.weeklyBossClearCount ??
        weeklyBosses.where((item) => item.done).length;
    final weeklyBossLimit = snapshot!.weeklyBossClearLimit ?? 12;
    final completedDaily =
        snapshot!.dailyItems.where((item) => item.done).length;
    final rewardSummary = _buildWeeklyRewardSummary(
      character: character,
      snapshot: snapshot!,
      partySchedules: partySchedules,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _dashboardCardDecoration(),
      child: _DashboardCharacterHeader(
        character: character,
        onTap: onOpenScheduler,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CharacterMetric(
                    icon: Icons.shield_outlined,
                    label: '주간 보스',
                    value: '$completedBosses / $weeklyBossLimit',
                  ),
                ),
                Container(width: 1, height: 42, color: AppColors.border),
                Expanded(
                  child: _CharacterMetric(
                    icon: Icons.today_outlined,
                    label: '일일 콘텐츠',
                    value: '$completedDaily / ${snapshot!.dailyItems.length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _CharacterMetric(
                    icon: Icons.monetization_on_outlined,
                    label: '주간 보스 수익',
                    value: _formatMesos(rewardSummary.crystalMesos),
                  ),
                ),
                Container(width: 1, height: 42, color: AppColors.border),
                Expanded(
                  child: _CharacterMetric(
                    icon: Icons.auto_awesome_outlined,
                    label: '솔 에르다 기운',
                    value: _formatSolErdaEnergy(rewardSummary.solErdaEnergy),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _dashboardCardDecoration() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    );

class _DashboardCharacterHeader extends StatelessWidget {
  const _DashboardCharacterHeader({
    required this.character,
    required this.child,
    this.onTap,
  });

  final NexonCharacterSummary character;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  character.characterName,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${character.worldName} · Lv.${character.characterLevel ?? '-'}',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        child,
      ],
    );
  }
}

class _CharacterMetric extends StatelessWidget {
  const _CharacterMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.navAccent),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _WeeklyRewardSummary {
  const _WeeklyRewardSummary({
    required this.crystalMesos,
    required this.solErdaEnergy,
  });

  final int crystalMesos;
  final int solErdaEnergy;
}

class _BossRewardInfo {
  const _BossRewardInfo({
    required this.crystalMesos,
    required this.solErdaEnergy,
  });

  final int crystalMesos;
  final int solErdaEnergy;
}

_WeeklyRewardSummary _buildWeeklyRewardSummary({
  required NexonCharacterSummary character,
  required SchedulerSnapshot snapshot,
  required List<PartySchedule> partySchedules,
}) {
  var crystalMesos = 0;
  var solErdaEnergy = 0;

  for (final item in snapshot.bossItems.where(_isDashboardWeeklyBoss)) {
    final reward = _bossRewardFor(item);
    if (reward == null) {
      continue;
    }
    final shareSize = _partyShareSizeFor(
      character: character,
      bossItem: item,
      partySchedules: partySchedules,
    );
    crystalMesos += reward.crystalMesos ~/ shareSize;
    solErdaEnergy += reward.solErdaEnergy ~/ shareSize;
  }

  return _WeeklyRewardSummary(
    crystalMesos: crystalMesos,
    solErdaEnergy: solErdaEnergy,
  );
}

_BossRewardInfo? _bossRewardFor(SchedulerItemSummary item) {
  return _bossRewards[_bossRewardKey(item.title, item.difficulty)];
}

int _partyShareSizeFor({
  required NexonCharacterSummary character,
  required SchedulerItemSummary bossItem,
  required List<PartySchedule> partySchedules,
}) {
  if (_isSeasonBossReward(bossItem.title)) {
    return 1;
  }

  PartySchedule? fallback;
  for (final schedule in partySchedules) {
    if (_bossRewardKey(schedule.bossName, schedule.difficulty) !=
        _bossRewardKey(bossItem.title, bossItem.difficulty)) {
      continue;
    }
    fallback ??= schedule;
    if (schedule.members.any((member) =>
        _normalizePartyBossValue(member) ==
        _normalizePartyBossValue(character.characterName))) {
      return math.max(1, schedule.members.length);
    }
  }
  return math.max(1, fallback?.members.length ?? 1);
}

String _bossRewardKey(String bossName, String difficulty) {
  return '${_normalizePartyBossValue(bossName)}#${_normalizeDifficulty(difficulty)}';
}

String _normalizeDifficulty(String value) {
  final normalized = _normalizePartyBossValue(value);
  return switch (normalized) {
    '이지' => 'easy',
    '노멀' || '노말' => 'normal',
    '하드' => 'hard',
    '카오스' => 'chaos',
    '익스트림' => 'extreme',
    _ => normalized,
  };
}

String _formatMesos(int mesos) {
  if (mesos <= 0) {
    return '-';
  }
  final eok = mesos ~/ 100000000;
  final man = (mesos % 100000000) ~/ 10000;
  if (eok > 0 && man > 0) {
    return '$eok억 $man만';
  }
  if (eok > 0) {
    return '$eok억';
  }
  if (man > 0) {
    return '$man만';
  }
  return mesos.toString();
}

String _formatSolErdaEnergy(int energy) {
  if (energy <= 0) {
    return '-';
  }
  return '$energy기운';
}

bool _isSeasonBossReward(String title) {
  final normalized = _normalizePartyBossValue(title);
  return normalized.contains('시즌보스') || normalized.contains('메이린');
}

class _MonsterParkWorldUsage {
  const _MonsterParkWorldUsage({
    required this.worldName,
    required this.totalCount,
    required this.characterNames,
  });

  final String worldName;
  final int? totalCount;
  final List<String> characterNames;
}

List<_MonsterParkWorldUsage> _buildMonsterParkUsage(
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  final groupedCharacters = <String, List<String>>{};
  final worldCounts = <String, int>{};

  for (final character in characters) {
    groupedCharacters
        .putIfAbsent(character.worldName, () => [])
        .add(character.characterName);

    final snapshot = snapshots[character.ocid];
    if (snapshot == null) {
      continue;
    }
    final monsterParkItems =
        snapshot.dailyItems.where(_isMonsterParkItem).toList();
    if (monsterParkItems.isEmpty) {
      continue;
    }
    final count = monsterParkItems.fold<int>(
      0,
      (sum, item) => sum + (item.currentCount ?? 0),
    );
    final previousCount = worldCounts[character.worldName];
    if (previousCount == null || count > previousCount) {
      worldCounts[character.worldName] = count;
    }
  }

  return groupedCharacters.entries
      .map(
        (entry) => _MonsterParkWorldUsage(
          worldName: entry.key,
          totalCount: worldCounts[entry.key],
          characterNames: entry.value,
        ),
      )
      .toList();
}

bool _isMonsterParkItem(SchedulerItemSummary item) {
  return item.title.replaceAll(' ', '').contains('몬스터파크');
}

class _MonsterParkSummary extends StatelessWidget {
  const _MonsterParkSummary({required this.items});

  final List<_MonsterParkWorldUsage> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _DashboardEmptyState(
        message: '몬스터파크 데이터를 아직 불러오지 못했습니다.',
      );
    }

    return Column(
      children: [
        for (final item in items)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: _dashboardCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.worldName,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      item.totalCount == null
                          ? '조회 필요'
                          : '${item.totalCount} / 14',
                      style: const TextStyle(
                        color: AppColors.navAccent,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final characterName in item.characterNames)
                      _MonsterParkCharacterChip(
                        characterName: characterName,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonsterParkCharacterChip extends StatelessWidget {
  const _MonsterParkCharacterChip({required this.characterName});

  final String characterName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.completionTag,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.completionTagBorder),
      ),
      child: Text(
        characterName,
        style: const TextStyle(
          color: AppColors.completionTagText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SharedWeeklyContentRule {
  const _SharedWeeklyContentRule({
    required this.title,
    required this.scope,
    required this.limit,
    required this.matches,
  });

  final String title;
  final String scope;
  final int limit;
  final bool Function(SchedulerItemSummary item) matches;
}

class _SharedWeeklyContentUsage {
  const _SharedWeeklyContentUsage({
    required this.rule,
    required this.characterNames,
    required this.completionDetails,
  });

  final _SharedWeeklyContentRule rule;
  final List<String> characterNames;
  final List<String> completionDetails;

  int get completedCount => _isEpicDungeonSharedRule(rule)
      ? completionDetails.length
      : characterNames.length;

  bool get hasCompletions => completedCount > 0;

  String get emptyLabel =>
      _isEpicDungeonSharedRule(rule) ? '완료 던전 없음' : '완료 캐릭터 없음';
}

final _sharedWeeklyContentRules = <_SharedWeeklyContentRule>[
  _SharedWeeklyContentRule(
    title: '에픽 던전',
    scope: '넥슨 ID',
    limit: 3,
    matches: (item) => item.title.replaceAll(' ', '').contains('에픽던전'),
  ),
  _SharedWeeklyContentRule(
    title: '익스트림 몬스터파커',
    scope: '월드',
    limit: 2,
    matches: (item) => item.title.replaceAll(' ', '').contains('익스트림몬스터파커'),
  ),
];

List<_SharedWeeklyContentUsage> _buildSharedWeeklyContentUsage(
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  return [
    for (final rule in _sharedWeeklyContentRules)
      _SharedWeeklyContentUsage(
        rule: rule,
        characterNames: _completedCharacterNames(rule, characters, snapshots),
        completionDetails: _isEpicDungeonSharedRule(rule)
            ? _epicDungeonCompletionDetails(rule, characters, snapshots)
            : const [],
      ),
  ];
}

bool _isSharedWeeklyContentItem(SchedulerItemSummary item) {
  return _sharedWeeklyContentRules.any((rule) => rule.matches(item));
}

List<String> _completedCharacterNames(
  _SharedWeeklyContentRule rule,
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  return [
    for (final character in characters)
      if ((snapshots[character.ocid]?.weeklyItems ?? const []).any((item) =>
          rule.matches(item) && _isSharedWeeklyContentDone(rule, item)))
        character.characterName,
  ];
}

List<String> _epicDungeonCompletionDetails(
  _SharedWeeklyContentRule rule,
  List<NexonCharacterSummary> characters,
  Map<String, SchedulerSnapshot> snapshots,
) {
  return <String>{
    for (final character in characters)
      for (final item in snapshots[character.ocid]?.weeklyItems ?? const [])
        if (rule.matches(item) && _isSharedWeeklyContentDone(rule, item))
          item.title,
  }.toList();
}

bool _isSharedWeeklyContentDone(
  _SharedWeeklyContentRule rule,
  SchedulerItemSummary item,
) {
  if (_isEpicDungeonSharedRule(rule)) {
    return (item.currentCount ?? 0) >= 5;
  }
  return item.done;
}

bool _isEpicDungeonSharedRule(_SharedWeeklyContentRule rule) {
  return rule.title.replaceAll(' ', '').contains('에픽던전');
}

class _SharedWeeklyContentSummary extends StatelessWidget {
  const _SharedWeeklyContentSummary({required this.items});

  final List<_SharedWeeklyContentUsage> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _dashboardCardDecoration(),
      child: Column(
        children: [
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 19,
                    color: AppColors.navAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.rule.title == '에픽 던전'
                          ? '에픽 던전 · 넥슨 ID당 각 던전 주 1회'
                          : '${item.rule.title} · ${item.rule.scope}당 주 ${item.rule.limit}캐릭터',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    item.hasCompletions
                        ? '${item.completedCount} / ${item.rule.limit}'
                        : item.emptyLabel,
                    style: TextStyle(
                      color: item.hasCompletions
                          ? AppColors.navAccent
                          : AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (item.hasCompletions)
              Padding(
                padding: const EdgeInsets.fromLTRB(49, 0, 20, 15),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in item.completionDetails.isEmpty
                          ? item.characterNames
                          : item.completionDetails)
                        _CompletionCharacterTag(label: label),
                    ],
                  ),
                ),
              ),
            if (item != items.last)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _CompletionCharacterTag extends StatelessWidget {
  const _CompletionCharacterTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.completionTag,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.completionTagBorder),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.completionTagText,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WeeklyContentCharacterList extends StatelessWidget {
  const _WeeklyContentCharacterList({
    required this.items,
    required this.hasSchedulerData,
  });

  final Map<String, List<String>> items;
  final bool hasSchedulerData;

  @override
  Widget build(BuildContext context) {
    if (!hasSchedulerData) {
      return const _DashboardEmptyState(
        message: '스케쥴러를 조회한 캐릭터가 없습니다.',
      );
    }
    if (items.isEmpty) {
      return const _DashboardEmptyState(
        message: '등록된 주간 콘텐츠가 없습니다.',
      );
    }

    return Container(
      decoration: _dashboardCardDecoration(),
      child: Column(
        children: [
          for (final entry in items.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 19,
                    color: AppColors.navAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (entry.value.isEmpty)
                    const Text(
                      '완료 캐릭터 없음',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _CompletionCharacterTag(
                          label: entry.value.join(', '),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (entry.key != items.entries.last.key)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: _dashboardCardDecoration(),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

bool _isDashboardWeeklyBoss(SchedulerItemSummary item) {
  final cycle = item.cycle.trim().toLowerCase();
  return cycle == 'weekly' ||
      cycle == 'week' ||
      cycle == 'bossweekly' ||
      cycle == '주간';
}

bool _isGuildSuroItem(SchedulerItemSummary item) {
  return item.title.replaceAll(' ', '').contains('지하수로');
}

const _partyBossDifficultyOptions = <String, List<String>>{
  '발록': ['easy', 'normal'],
  '자쿰': ['normal', 'chaos'],
  '매그너스': ['easy', 'normal', 'hard'],
  '힐라': ['normal', 'hard'],
  '반 레온': ['easy', 'normal', 'hard'],
  '혼테일': ['easy', 'normal', 'chaos'],
  '아카이럼': ['easy', 'normal'],
  '핑크빈': ['normal', 'chaos'],
  '시그너스': ['normal'],
  '카웅': ['normal'],
  '파풀라투스': ['easy', 'normal', 'chaos'],
  '피에르': ['normal', 'chaos'],
  '반반': ['normal', 'chaos'],
  '블러디퀸': ['normal', 'chaos'],
  '벨룸': ['normal', 'chaos'],
  '스우': ['normal', 'hard', 'extreme'],
  '데미안': ['normal', 'hard'],
  '가디언 엔젤 슬라임': ['normal', 'chaos'],
  '루시드': ['easy', 'normal', 'hard'],
  '윌': ['easy', 'normal', 'hard'],
  '더스크': ['normal', 'chaos'],
  '진 힐라': ['normal', 'hard'],
  '듄켈': ['normal', 'hard'],
  '검은 마법사': ['hard', 'extreme'],
  '선택받은 세렌': ['normal', 'hard', 'extreme'],
  '감시자 칼로스': ['easy', 'normal', 'chaos', 'extreme'],
  '카링': ['easy', 'normal', 'hard', 'extreme'],
  '림보': ['normal', 'hard'],
  '발드릭스': ['normal', 'hard'],
  '최초의 대적자': ['easy', 'normal', 'hard', 'extreme'],
  '찬란한 흉성': ['normal', 'hard'],
  '유피테르': ['normal', 'hard'],
  '시즌 보스 메이린': ['normal', 'hard'],
};

int _partyBossMaxMembers(String bossName, String difficulty) {
  final normalizedDifficulty = _normalizeDifficulty(difficulty);
  if (bossName == '스우' && normalizedDifficulty == 'extreme') {
    return 2;
  }
  if (const {
    '림보',
    '발드릭스',
    '최초의 대적자',
    '찬란한 흉성',
    '유피테르',
  }.contains(bossName)) {
    return 3;
  }
  return 6;
}

const _partyBossPriorityOrder = <String>[
  '유피테르',
  '찬란한 흉성',
  '최초의 대적자',
  '발드릭스',
  '림보',
  '카링',
  '감시자 칼로스',
  '선택받은 세렌',
  '검은 마법사',
  '시즌 보스 메이린',
  '듄켈',
  '진 힐라',
  '더스크',
  '윌',
  '루시드',
  '가디언 엔젤 슬라임',
  '데미안',
  '스우',
  '벨룸',
  '블러디퀸',
  '반반',
  '피에르',
  '파풀라투스',
  '카웅',
  '시그너스',
  '핑크빈',
  '아카이럼',
  '혼테일',
  '반 레온',
  '힐라',
  '매그너스',
  '자쿰',
  '발록',
];

List<String> _partyBossSelectionOptions() {
  final ranked = _partyBossPriorityOrder
      .where(_partyBossDifficultyOptions.containsKey)
      .toList();
  final rankedSet = ranked.toSet();
  return [
    ...ranked,
    ..._partyBossDifficultyOptions.keys
        .where((boss) => !rankedSet.contains(boss)),
  ];
}

String _partyBossImageAsset(String bossName) {
  final fileName = switch (bossName) {
    '블러디퀸' => '블러디 퀸',
    '시즌 보스 메이린' => '메이린',
    _ => bossName,
  };
  return 'assets/images/bosses/$fileName.webp';
}

final _bossRewards = <String, _BossRewardInfo>{
  _bossRewardKey('자쿰', 'normal'):
      const _BossRewardInfo(crystalMesos: 354800, solErdaEnergy: 0),
  _bossRewardKey('자쿰', 'chaos'):
      const _BossRewardInfo(crystalMesos: 8080000, solErdaEnergy: 0),
  _bossRewardKey('매그너스', 'easy'):
      const _BossRewardInfo(crystalMesos: 418300, solErdaEnergy: 0),
  _bossRewardKey('매그너스', 'normal'):
      const _BossRewardInfo(crystalMesos: 1160000, solErdaEnergy: 0),
  _bossRewardKey('매그너스', 'hard'):
      const _BossRewardInfo(crystalMesos: 8560000, solErdaEnergy: 0),
  _bossRewardKey('힐라', 'normal'):
      const _BossRewardInfo(crystalMesos: 463500, solErdaEnergy: 0),
  _bossRewardKey('힐라', 'hard'):
      const _BossRewardInfo(crystalMesos: 1280000, solErdaEnergy: 0),
  _bossRewardKey('카웅', 'normal'):
      const _BossRewardInfo(crystalMesos: 1250000, solErdaEnergy: 0),
  _bossRewardKey('파풀라투스', 'easy'):
      const _BossRewardInfo(crystalMesos: 396500, solErdaEnergy: 0),
  _bossRewardKey('파풀라투스', 'normal'):
      const _BossRewardInfo(crystalMesos: 1200000, solErdaEnergy: 0),
  _bossRewardKey('파풀라투스', 'chaos'):
      const _BossRewardInfo(crystalMesos: 13100000, solErdaEnergy: 0),
  _bossRewardKey('피에르', 'normal'):
      const _BossRewardInfo(crystalMesos: 968000, solErdaEnergy: 0),
  _bossRewardKey('피에르', 'chaos'):
      const _BossRewardInfo(crystalMesos: 8170000, solErdaEnergy: 0),
  _bossRewardKey('반반', 'normal'):
      const _BossRewardInfo(crystalMesos: 968000, solErdaEnergy: 0),
  _bossRewardKey('반반', 'chaos'):
      const _BossRewardInfo(crystalMesos: 8150000, solErdaEnergy: 0),
  _bossRewardKey('블러디퀸', 'normal'):
      const _BossRewardInfo(crystalMesos: 968000, solErdaEnergy: 0),
  _bossRewardKey('블러디퀸', 'chaos'):
      const _BossRewardInfo(crystalMesos: 8140000, solErdaEnergy: 0),
  _bossRewardKey('벨룸', 'normal'):
      const _BossRewardInfo(crystalMesos: 968000, solErdaEnergy: 0),
  _bossRewardKey('벨룸', 'chaos'):
      const _BossRewardInfo(crystalMesos: 9280000, solErdaEnergy: 0),
  _bossRewardKey('스우', 'normal'):
      const _BossRewardInfo(crystalMesos: 16700000, solErdaEnergy: 0),
  _bossRewardKey('스우', 'hard'):
      const _BossRewardInfo(crystalMesos: 51500000, solErdaEnergy: 40),
  _bossRewardKey('스우', 'extreme'):
      const _BossRewardInfo(crystalMesos: 574000000, solErdaEnergy: 400),
  _bossRewardKey('데미안', 'normal'):
      const _BossRewardInfo(crystalMesos: 17500000, solErdaEnergy: 0),
  _bossRewardKey('데미안', 'hard'):
      const _BossRewardInfo(crystalMesos: 48900000, solErdaEnergy: 40),
  _bossRewardKey('가디언 엔젤 슬라임', 'normal'):
      const _BossRewardInfo(crystalMesos: 25500000, solErdaEnergy: 0),
  _bossRewardKey('가디언 엔젤 슬라임', 'chaos'):
      const _BossRewardInfo(crystalMesos: 75100000, solErdaEnergy: 60),
  _bossRewardKey('루시드', 'easy'):
      const _BossRewardInfo(crystalMesos: 29800000, solErdaEnergy: 0),
  _bossRewardKey('루시드', 'normal'):
      const _BossRewardInfo(crystalMesos: 35600000, solErdaEnergy: 40),
  _bossRewardKey('루시드', 'hard'):
      const _BossRewardInfo(crystalMesos: 62900000, solErdaEnergy: 70),
  _bossRewardKey('윌', 'easy'):
      const _BossRewardInfo(crystalMesos: 32300000, solErdaEnergy: 0),
  _bossRewardKey('윌', 'normal'):
      const _BossRewardInfo(crystalMesos: 41100000, solErdaEnergy: 50),
  _bossRewardKey('윌', 'hard'):
      const _BossRewardInfo(crystalMesos: 77100000, solErdaEnergy: 80),
  _bossRewardKey('더스크', 'normal'):
      const _BossRewardInfo(crystalMesos: 44000000, solErdaEnergy: 45),
  _bossRewardKey('더스크', 'chaos'):
      const _BossRewardInfo(crystalMesos: 69800000, solErdaEnergy: 90),
  _bossRewardKey('진 힐라', 'normal'):
      const _BossRewardInfo(crystalMesos: 71200000, solErdaEnergy: 50),
  _bossRewardKey('진 힐라', 'hard'):
      const _BossRewardInfo(crystalMesos: 106000000, solErdaEnergy: 100),
  _bossRewardKey('듄켈', 'normal'):
      const _BossRewardInfo(crystalMesos: 47500000, solErdaEnergy: 50),
  _bossRewardKey('듄켈', 'hard'):
      const _BossRewardInfo(crystalMesos: 94400000, solErdaEnergy: 90),
  _bossRewardKey('검은 마법사', 'hard'):
      const _BossRewardInfo(crystalMesos: 665000000, solErdaEnergy: 250),
  _bossRewardKey('검은 마법사', 'extreme'):
      const _BossRewardInfo(crystalMesos: 8740000000, solErdaEnergy: 1000),
  _bossRewardKey('선택받은 세렌', 'normal'):
      const _BossRewardInfo(crystalMesos: 239000000, solErdaEnergy: 120),
  _bossRewardKey('선택받은 세렌', 'hard'):
      const _BossRewardInfo(crystalMesos: 356000000, solErdaEnergy: 220),
  _bossRewardKey('선택받은 세렌', 'extreme'):
      const _BossRewardInfo(crystalMesos: 2835000000, solErdaEnergy: 600),
  _bossRewardKey('감시자 칼로스', 'easy'):
      const _BossRewardInfo(crystalMesos: 280000000, solErdaEnergy: 140),
  _bossRewardKey('감시자 칼로스', 'normal'):
      const _BossRewardInfo(crystalMesos: 505000000, solErdaEnergy: 240),
  _bossRewardKey('감시자 칼로스', 'chaos'):
      const _BossRewardInfo(crystalMesos: 1273000000, solErdaEnergy: 420),
  _bossRewardKey('감시자 칼로스', 'extreme'):
      const _BossRewardInfo(crystalMesos: 4104000000, solErdaEnergy: 650),
  _bossRewardKey('카링', 'easy'):
      const _BossRewardInfo(crystalMesos: 377000000, solErdaEnergy: 160),
  _bossRewardKey('카링', 'normal'):
      const _BossRewardInfo(crystalMesos: 678000000, solErdaEnergy: 260),
  _bossRewardKey('카링', 'hard'):
      const _BossRewardInfo(crystalMesos: 1739000000, solErdaEnergy: 500),
  _bossRewardKey('카링', 'extreme'):
      const _BossRewardInfo(crystalMesos: 5387000000, solErdaEnergy: 800),
  _bossRewardKey('림보', 'normal'):
      const _BossRewardInfo(crystalMesos: 1026000000, solErdaEnergy: 420),
  _bossRewardKey('림보', 'hard'):
      const _BossRewardInfo(crystalMesos: 2385000000, solErdaEnergy: 750),
  _bossRewardKey('발드릭스', 'normal'):
      const _BossRewardInfo(crystalMesos: 1368000000, solErdaEnergy: 500),
  _bossRewardKey('발드릭스', 'hard'):
      const _BossRewardInfo(crystalMesos: 3078000000, solErdaEnergy: 900),
  _bossRewardKey('시즌 보스 메이린', 'normal'): const _BossRewardInfo(
    crystalMesos: 300000000,
    solErdaEnergy: 400,
  ),
  _bossRewardKey('시즌 보스 메이린', 'hard'): const _BossRewardInfo(
    crystalMesos: 600000000,
    solErdaEnergy: 550,
  ),
  _bossRewardKey('메이린', 'normal'): const _BossRewardInfo(
    crystalMesos: 300000000,
    solErdaEnergy: 400,
  ),
  _bossRewardKey('메이린', 'hard'): const _BossRewardInfo(
    crystalMesos: 600000000,
    solErdaEnergy: 550,
  ),
};

int _comparePartySchedules(PartySchedule a, PartySchedule b) {
  final repeatCompare = a.repeatType.compareTo(b.repeatType);
  if (repeatCompare != 0) {
    return repeatCompare;
  }
  final weekdayCompare = a.weekday.compareTo(b.weekday);
  if (weekdayCompare != 0) {
    return weekdayCompare;
  }
  final monthDayCompare = a.monthDay.compareTo(b.monthDay);
  if (monthDayCompare != 0) {
    return monthDayCompare;
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

String _partyWeekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '월요일',
    DateTime.tuesday => '화요일',
    DateTime.wednesday => '수요일',
    DateTime.thursday => '목요일',
    DateTime.friday => '금요일',
    DateTime.saturday => '토요일',
    DateTime.sunday => '일요일',
    _ => '화요일',
  };
}

String _partyWeekdayShortLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '월',
    DateTime.tuesday => '화',
    DateTime.wednesday => '수',
    DateTime.thursday => '목',
    DateTime.friday => '금',
    DateTime.saturday => '토',
    DateTime.sunday => '일',
    _ => '화',
  };
}

String _partyScheduleText(PartySchedule schedule) {
  final hour = schedule.hour.toString().padLeft(2, '0');
  final minute = schedule.minute.toString().padLeft(2, '0');
  if (schedule.isMonthly) {
    return '매월 ${schedule.monthDay}일 $hour:$minute';
  }
  return '매주 ${_partyWeekdayLabel(schedule.weekday)} $hour:$minute';
}

String _defaultPartyRepeatType(String bossName) {
  return bossName == '검은 마법사' ? 'monthly' : 'weekly';
}

String _partyRepeatTypeLabel(String repeatType) {
  return repeatType == 'monthly' ? '월간' : '주간';
}

bool _isMonthlyPartyBoss(String bossName) {
  return bossName == '검은 마법사';
}

bool _hasDuplicatePartyBoss(
  List<PartySchedule> schedules,
  String bossName, {
  String? exceptId,
}) {
  final normalizedBossName = bossName.trim();
  return schedules.any(
    (schedule) =>
        schedule.id != exceptId &&
        schedule.bossName.trim() == normalizedBossName,
  );
}

bool _isPartyScheduleClearedBySnapshots(
  PartySchedule schedule,
  Map<String, SchedulerSnapshot> snapshots,
) {
  final bossName = _normalizePartyBossValue(schedule.bossName);
  final difficulty = _normalizePartyBossValue(schedule.difficulty);
  if (bossName.isEmpty || snapshots.isEmpty) {
    return false;
  }

  for (final snapshot in snapshots.values) {
    for (final item in snapshot.bossItems) {
      if (!item.done) {
        continue;
      }
      final itemBossName = _normalizePartyBossValue(item.title);
      final itemDifficulty = _normalizePartyBossValue(item.difficulty);
      if (itemBossName == bossName && itemDifficulty == difficulty) {
        return true;
      }
    }
  }
  return false;
}

String _normalizePartyBossValue(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
}

int _partyDisplayHour(int hour) {
  final displayHour = hour % 12;
  return displayHour == 0 ? 12 : displayHour;
}

int _partyHourTo24Hour(int displayHour, bool isPm) {
  final normalizedHour = displayHour % 12;
  return isPm ? normalizedHour + 12 : normalizedHour;
}

int? _parsePartyTimeUnit(String value, int min, int max) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < min || parsed > max) {
    return null;
  }
  return parsed;
}

List<String> _frequentPartyMembers(
  List<PartySchedule> schedules,
  List<NexonCharacterSummary> ownCharacters,
) {
  final ownCharacterNames = ownCharacters
      .map((character) => character.characterName.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
  final counts = <String, int>{};
  for (final schedule in schedules) {
    for (final member in schedule.members) {
      final trimmed = member.trim();
      if (trimmed.isEmpty || ownCharacterNames.contains(trimmed)) {
        continue;
      }
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  final sorted = counts.entries.where((entry) => entry.value >= 3).toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) {
        return countCompare;
      }
      return a.key.compareTo(b.key);
    });
  return sorted.map((entry) => entry.key).toList();
}

List<String> _normalizePartyMembers(
  String text,
  List<NexonCharacterSummary> ownCharacters,
) {
  final ownCharacterNames = ownCharacters
      .map((character) => character.characterName.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
  final members = <String>[];
  for (final rawMember in text.split(',')) {
    final member = rawMember.trim();
    if (member.isEmpty ||
        ownCharacterNames.contains(member) ||
        members.contains(member)) {
      continue;
    }
    members.add(member);
  }
  return members;
}

void _appendPartyMember(
  TextEditingController controller,
  String member,
  List<NexonCharacterSummary> ownCharacters,
) {
  final members = _normalizePartyMembers(
    controller.text,
    ownCharacters,
  );
  if (!members.contains(member)) {
    members.add(member);
  }
  controller.text = members.join(', ');
  controller.selection =
      TextSelection.collapsed(offset: controller.text.length);
}

Future<int?> _pickMonthlyPartyDay(BuildContext context, int selectedDay) {
  return showDialog<int>(
    context: context,
    builder: (context) {
      var draftDay = selectedDay.clamp(1, 31);
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.all(28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '월간 날짜 선택',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: 31,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.25,
                      ),
                      itemBuilder: (context, index) {
                        final day = index + 1;
                        final selected = draftDay == day;
                        return OutlinedButton(
                          onPressed: () {
                            setDialogState(() {
                              draftDay = day;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: selected
                                ? AppColors.navAccent.withValues(alpha: 0.15)
                                : AppColors.surface,
                            foregroundColor:
                                selected ? AppColors.navAccent : AppColors.text,
                            side: BorderSide(
                              color: selected
                                  ? AppColors.navBorder
                                  : AppColors.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            '$day',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, draftDay),
                          child: const Text('선택'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _PartySchedulePanel extends StatelessWidget {
  const _PartySchedulePanel({
    required this.schedules,
    required this.characters,
    required this.dashboardSnapshots,
    required this.onSave,
    required this.onDelete,
  });

  final List<PartySchedule> schedules;
  final List<NexonCharacterSummary> characters;
  final Map<String, SchedulerSnapshot> dashboardSnapshots;
  final Future<void> Function(PartySchedule schedule) onSave;
  final Future<void> Function(PartySchedule schedule) onDelete;

  @override
  Widget build(BuildContext context) {
    final displayedSchedules = _sortedPartySchedules();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '고정 파티 보스 일정을 등록하고 시간에 맞춰 알림을 받아요.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _PrimaryActionButton(
              icon: Icons.add_rounded,
              label: '일정 추가',
              onPressed: () => _openPartyDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: schedules.isEmpty
              ? const _DashboardEmptyState(
                  message: '등록된 파티 일정이 없습니다.\n일정 추가 버튼으로 주간 보스 파티를 등록해보세요.',
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 215,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: displayedSchedules.length,
                  itemBuilder: (context, index) {
                    final schedule = displayedSchedules[index];
                    return _PartyScheduleCard(
                      schedule: schedule,
                      isCleared: _isPartyScheduleClearedBySnapshots(
                        schedule,
                        dashboardSnapshots,
                      ),
                      onEdit: () => _openPartyDialog(context, schedule),
                      onDelete: () => unawaited(
                        _confirmDeleteSchedule(context, schedule),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<PartySchedule> _sortedPartySchedules() {
    final sorted = [...schedules];
    sorted.sort((a, b) {
      final aCleared = _isPartyScheduleClearedBySnapshots(
        a,
        dashboardSnapshots,
      );
      final bCleared = _isPartyScheduleClearedBySnapshots(
        b,
        dashboardSnapshots,
      );
      if (aCleared != bCleared) {
        return aCleared ? 1 : -1;
      }
      return _comparePartySchedules(a, b);
    });
    return sorted;
  }

  Future<void> _confirmDeleteSchedule(
    BuildContext context,
    PartySchedule schedule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('파티 일정 삭제'),
          content: Text('${schedule.bossName} 파티 일정을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onDelete(schedule);
    }
  }

  Future<void> _openPartyDialog(
    BuildContext context, [
    PartySchedule? schedule,
  ]) async {
    final memberController = TextEditingController(
      text: schedule?.members.join(', ') ?? '',
    );
    final frequentMembers = _frequentPartyMembers(schedules, characters);
    var showMemberSuggestions = false;
    var selectedBoss =
        _partyBossDifficultyOptions.containsKey(schedule?.bossName)
            ? schedule!.bossName
            : _partyBossDifficultyOptions.keys.first;
    var selectedRepeatType = _defaultPartyRepeatType(selectedBoss);
    var difficultyOptions = _partyBossDifficultyOptions[selectedBoss]!;
    var selectedDifficulty = difficultyOptions.contains(schedule?.difficulty)
        ? schedule!.difficulty
        : difficultyOptions.last;
    var selectedWeekday = schedule?.weekday ?? DateTime.tuesday;
    var selectedMonthDay = schedule?.monthDay ?? DateTime.now().day;
    var selectedIsPm = (schedule?.hour ?? 21) >= 12;
    String? validationMessage;
    final hourController = TextEditingController(
      text: _partyDisplayHour(schedule?.hour ?? 21).toString(),
    );
    final minuteController = TextEditingController(
      text: (schedule?.minute ?? 0).toString().padLeft(2, '0'),
    );

    final result = await showDialog<PartySchedule>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        schedule == null ? '파티 일정 추가' : '파티 일정 수정',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: memberController,
                        onTap: () {
                          setDialogState(() {
                            showMemberSuggestions = true;
                          });
                        },
                        onChanged: (_) {
                          if (validationMessage == null) {
                            return;
                          }
                          setDialogState(() {
                            validationMessage = null;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: '파티원',
                          hintText: '말못함채금임, 유렌괜찬',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (showMemberSuggestions &&
                          frequentMembers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          '자주 함께한 파티원',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final member in frequentMembers.take(12))
                              ActionChip(
                                label: Text(member),
                                onPressed: () {
                                  setDialogState(() {
                                    _appendPartyMember(
                                      memberController,
                                      member,
                                      characters,
                                    );
                                    validationMessage = null;
                                  });
                                },
                                backgroundColor: AppColors.navAccent.withValues(
                                  alpha: 0.1,
                                ),
                                side: const BorderSide(
                                  color: AppColors.navBorder,
                                ),
                                labelStyle: const TextStyle(
                                  color: AppColors.navAccent,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _PartyBossSelector(
                        bossName: selectedBoss,
                        difficulties: difficultyOptions,
                        selectedDifficulty: selectedDifficulty,
                        onTap: () async {
                          final pickedBoss = await _pickPartyBoss(
                            dialogContext,
                            selectedBoss,
                          );
                          if (pickedBoss == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedBoss = pickedBoss;
                            validationMessage = null;
                            selectedRepeatType =
                                _defaultPartyRepeatType(selectedBoss);
                            difficultyOptions =
                                _partyBossDifficultyOptions[selectedBoss]!;
                            selectedDifficulty =
                                difficultyOptions.contains(selectedDifficulty)
                                    ? selectedDifficulty
                                    : difficultyOptions.last;
                          });
                        },
                        onDifficultyChanged: (difficulty) {
                          setDialogState(() {
                            selectedDifficulty = difficulty;
                            validationMessage = null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.navBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '일정 선택',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '반복 주기: ${_partyRepeatTypeLabel(selectedRepeatType)}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_isMonthlyPartyBoss(selectedBoss))
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final pickedDay = await _pickMonthlyPartyDay(
                                    dialogContext,
                                    selectedMonthDay,
                                  );
                                  if (pickedDay == null) {
                                    return;
                                  }
                                  setDialogState(() {
                                    selectedMonthDay = pickedDay;
                                  });
                                },
                                icon: const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 18,
                                ),
                                label: Text('매월 $selectedMonthDay일'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  foregroundColor: AppColors.navAccent,
                                  side: const BorderSide(
                                    color: AppColors.navBorder,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final weekday in const [
                                    DateTime.monday,
                                    DateTime.tuesday,
                                    DateTime.wednesday,
                                    DateTime.thursday,
                                    DateTime.friday,
                                    DateTime.saturday,
                                    DateTime.sunday,
                                  ])
                                    ChoiceChip(
                                      label: Text(
                                        _partyWeekdayShortLabel(weekday),
                                      ),
                                      selected: selectedWeekday == weekday,
                                      showCheckmark: false,
                                      onSelected: (_) {
                                        setDialogState(() {
                                          selectedWeekday = weekday;
                                        });
                                      },
                                      selectedColor:
                                          AppColors.navAccent.withValues(
                                        alpha: 0.15,
                                      ),
                                      side: BorderSide(
                                        color: selectedWeekday == weekday
                                            ? AppColors.navBorder
                                            : AppColors.border,
                                      ),
                                      labelStyle: TextStyle(
                                        color: selectedWeekday == weekday
                                            ? AppColors.navAccent
                                            : AppColors.text,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                      value: false,
                                      label: Text('오전'),
                                    ),
                                    ButtonSegment(
                                      value: true,
                                      label: Text('오후'),
                                    ),
                                  ],
                                  selected: {selectedIsPm},
                                  showSelectedIcon: false,
                                  style: ButtonStyle(
                                    foregroundColor:
                                        WidgetStateProperty.resolveWith<Color>(
                                            (states) {
                                      return states.contains(
                                        WidgetState.selected,
                                      )
                                          ? Colors.white
                                          : AppColors.text;
                                    }),
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith<Color>(
                                            (states) {
                                      return states.contains(
                                        WidgetState.selected,
                                      )
                                          ? AppColors.navAccent
                                          : AppColors.surface;
                                    }),
                                    side: const WidgetStatePropertyAll(
                                      BorderSide(color: AppColors.navBorder),
                                    ),
                                  ),
                                  onSelectionChanged: (selection) {
                                    setDialogState(() {
                                      selectedIsPm = selection.first;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: hourController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 2,
                                    decoration: const InputDecoration(
                                      labelText: '시',
                                      hintText: '9',
                                      counterText: '',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (_) {
                                      setDialogState(() {
                                        validationMessage = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: minuteController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 2,
                                    decoration: const InputDecoration(
                                      labelText: '분',
                                      hintText: '00',
                                      counterText: '',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (_) {
                                      setDialogState(() {
                                        validationMessage = null;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          validationMessage!,
                          style: const TextStyle(
                            color: AppColors.navAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: () {
                              final maxPartyMembers = _partyBossMaxMembers(
                                selectedBoss,
                                selectedDifficulty,
                              );
                              final maxInputMembers = maxPartyMembers - 1;
                              final members = _normalizePartyMembers(
                                memberController.text,
                                characters,
                              );
                              if (members.length > maxInputMembers) {
                                setDialogState(() {
                                  validationMessage =
                                      '$selectedBoss ${selectedDifficulty.toUpperCase()} 파티는 본인 포함 최대 $maxPartyMembers명까지 가능해요.';
                                });
                                return;
                              }
                              final displayHour = _parsePartyTimeUnit(
                                hourController.text,
                                1,
                                12,
                              );
                              if (displayHour == null) {
                                setDialogState(() {
                                  validationMessage = '시간은 1부터 12 사이로 입력해주세요.';
                                });
                                return;
                              }
                              final hour = _partyHourTo24Hour(
                                displayHour,
                                selectedIsPm,
                              );
                              final minute = _parsePartyTimeUnit(
                                minuteController.text,
                                0,
                                59,
                              );
                              if (minute == null) {
                                setDialogState(() {
                                  validationMessage = '분은 0부터 59 사이로 입력해주세요.';
                                });
                                return;
                              }
                              if (_hasDuplicatePartyBoss(
                                schedules,
                                selectedBoss,
                                exceptId: schedule?.id,
                              )) {
                                setDialogState(() {
                                  validationMessage =
                                      '$selectedBoss 파티 일정은 이미 등록되어 있어요.';
                                });
                                return;
                              }
                              Navigator.pop(
                                dialogContext,
                                PartySchedule(
                                  id: schedule?.id ??
                                      DateTime.now()
                                          .microsecondsSinceEpoch
                                          .toString(),
                                  members: members,
                                  bossName: selectedBoss,
                                  difficulty: selectedDifficulty,
                                  repeatType: selectedRepeatType,
                                  weekday: selectedWeekday,
                                  monthDay: selectedMonthDay,
                                  hour: hour,
                                  minute: minute,
                                  cleared: schedule?.cleared ?? false,
                                ),
                              );
                            },
                            child: const Text('저장'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    memberController.dispose();
    hourController.dispose();
    minuteController.dispose();

    if (result != null) {
      await onSave(result);
    }
  }
}

Future<String?> _pickPartyBoss(BuildContext context, String selectedBoss) {
  final bosses = _partyBossSelectionOptions();
  final size = MediaQuery.sizeOf(context);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 72, vertical: 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: size.height * 0.68,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '보스 선택',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: bosses.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, index) {
                      final boss = bosses[index];
                      return _PartyBossPickerCard(
                        bossName: boss,
                        onTap: () => Navigator.pop(dialogContext, boss),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PartyBossSelector extends StatelessWidget {
  const _PartyBossSelector({
    required this.bossName,
    required this.difficulties,
    required this.selectedDifficulty,
    required this.onTap,
    required this.onDifficultyChanged,
  });

  final String bossName;
  final List<String> difficulties;
  final String selectedDifficulty;
  final VoidCallback onTap;
  final ValueChanged<String> onDifficultyChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '보스',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _partyBossImageAsset(bossName),
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 88,
                    height: 88,
                    color: AppColors.softBorder,
                    alignment: Alignment.center,
                    child: Text(
                      bossName.characters.first,
                      style: const TextStyle(
                        color: AppColors.navAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _BossDifficultyBadge(difficulty: selectedDifficulty),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bossName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final difficulty in difficulties) ...[
                          Expanded(
                            child: _PartyDifficultyChoice(
                              difficulty: difficulty,
                              selected: difficulty == selectedDifficulty,
                              onTap: () => onDifficultyChanged(difficulty),
                            ),
                          ),
                          if (difficulty != difficulties.last)
                            const SizedBox(width: 5),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartyDifficultyChoice extends StatelessWidget {
  const _PartyDifficultyChoice({
    required this.difficulty,
    required this.selected,
    required this.onTap,
  });

  final String difficulty;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.navAccent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.transparent),
        ),
        child: Center(child: _BossDifficultyBadge(difficulty: difficulty)),
      ),
    );
  }
}

class _PartyBossPickerCard extends StatelessWidget {
  const _PartyBossPickerCard({
    required this.bossName,
    required this.onTap,
  });

  final String bossName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF414A52),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF727B84),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset(
                    _partyBossImageAsset(bossName),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.softBorder,
                      alignment: Alignment.center,
                      child: Text(
                        bossName.characters.first,
                        style: const TextStyle(
                          color: AppColors.navAccent,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                bossName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartyScheduleCard extends StatelessWidget {
  const _PartyScheduleCard({
    required this.schedule,
    required this.isCleared,
    required this.onEdit,
    required this.onDelete,
  });

  final PartySchedule schedule;
  final bool isCleared;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final memberText =
        schedule.members.isEmpty ? '파티원 없음' : schedule.members.join(' · ');
    final now = DateTime.now();
    final overdue =
        !isCleared && schedule.currentScheduleFrom(now).isBefore(now);
    final contentColor = isCleared ? Colors.white : AppColors.text;
    final mutedColor = isCleared ? Colors.white70 : AppColors.muted;
    final accentColor = isCleared ? Colors.white : AppColors.navAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCleared ? const Color(0xFF7A818A) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: overdue ? AppColors.navAccent : AppColors.navBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BossIconImage(
                bossName: schedule.bossName,
                size: 38,
                fallbackTextColor: contentColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BossDifficultyBadge(difficulty: schedule.difficulty),
                    const SizedBox(height: 5),
                    Text(
                      schedule.bossName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PartyScheduleIconButton(
                icon: Icons.edit_rounded,
                tooltip: '수정',
                onPressed: onEdit,
                foregroundColor: isCleared ? AppColors.text : contentColor,
                backgroundColor: isCleared ? Colors.white : AppColors.surface,
              ),
              const SizedBox(width: 4),
              _PartyScheduleIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: '삭제',
                onPressed: onDelete,
                foregroundColor: isCleared ? AppColors.text : contentColor,
                backgroundColor: isCleared ? Colors.white : AppColors.surface,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PartyCardTextBlock(
            label: '파티원',
            value: memberText,
            labelColor: mutedColor,
            valueColor: contentColor,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: accentColor, size: 16),
              const SizedBox(width: 6),
              Text(
                _partyRepeatTypeLabel(schedule.repeatType),
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '· ${_partyScheduleText(schedule)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _PartyStatusChip(isCleared: isCleared),
        ],
      ),
    );
  }
}

class _PartyScheduleIconButton extends StatelessWidget {
  const _PartyScheduleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: foregroundColor, size: 20),
          ),
        ),
      ),
    );
  }
}

class _PartyCardTextBlock extends StatelessWidget {
  const _PartyCardTextBlock({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PartyStatusChip extends StatelessWidget {
  const _PartyStatusChip({required this.isCleared});

  final bool isCleared;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isCleared ? AppColors.completionTag : AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isCleared ? AppColors.border : AppColors.navBorder,
        ),
      ),
      child: Text(
        isCleared ? '완료' : '아직 처치 전',
        style: TextStyle(
          color: isCleared ? AppColors.muted : AppColors.navAccent,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _CharacterSelectPanel extends StatelessWidget {
  const _CharacterSelectPanel({
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.isLoading,
    required this.errorMessage,
    required this.onAddCharacter,
    required this.onSelectCharacter,
    required this.onDeleteCharacter,
    required this.onMoveCharacter,
    required this.notificationDisabledOcids,
    required this.onToggleCharacterNotification,
  });

  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onAddCharacter;
  final ValueChanged<NexonCharacterSummary> onSelectCharacter;
  final ValueChanged<NexonCharacterSummary> onDeleteCharacter;
  final void Function(NexonCharacterSummary character, int targetIndex)
      onMoveCharacter;
  final Set<String> notificationDisabledOcids;
  final ValueChanged<NexonCharacterSummary> onToggleCharacterNotification;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1100 ? 5 : 4;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errorMessage != null) ...[
              _InlineError(message: errorMessage!),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: _ReorderableCharacterGrid(
                    selectedCharacter: selectedCharacter,
                    selectedCharacters: selectedCharacters,
                    crossAxisCount: crossAxisCount,
                    isLoading: isLoading,
                    notificationDisabledOcids: notificationDisabledOcids,
                    onAddCharacter: onAddCharacter,
                    onSelectCharacter: onSelectCharacter,
                    onDeleteCharacter: onDeleteCharacter,
                    onMoveCharacter: onMoveCharacter,
                    onToggleCharacterNotification:
                        onToggleCharacterNotification,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReorderableCharacterGrid extends StatefulWidget {
  const _ReorderableCharacterGrid({
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.crossAxisCount,
    required this.isLoading,
    required this.notificationDisabledOcids,
    required this.onAddCharacter,
    required this.onSelectCharacter,
    required this.onDeleteCharacter,
    required this.onMoveCharacter,
    required this.onToggleCharacterNotification,
  });

  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final int crossAxisCount;
  final bool isLoading;
  final Set<String> notificationDisabledOcids;
  final VoidCallback onAddCharacter;
  final ValueChanged<NexonCharacterSummary> onSelectCharacter;
  final ValueChanged<NexonCharacterSummary> onDeleteCharacter;
  final void Function(NexonCharacterSummary character, int targetIndex)
      onMoveCharacter;
  final ValueChanged<NexonCharacterSummary> onToggleCharacterNotification;

  @override
  State<_ReorderableCharacterGrid> createState() =>
      _ReorderableCharacterGridState();
}

class _ReorderableCharacterGridState extends State<_ReorderableCharacterGrid> {
  NexonCharacterSummary? _draggingCharacter;
  int? _previewTargetIndex;

  @override
  void didUpdateWidget(covariant _ReorderableCharacterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingCharacter != null &&
        !widget.selectedCharacters.any(
          (character) => _isSameCharacter(character, _draggingCharacter),
        )) {
      _clearPreview();
    }
  }

  List<NexonCharacterSummary> get _previewCharacters {
    final draggingCharacter = _draggingCharacter;
    final targetIndex = _previewTargetIndex;
    if (draggingCharacter == null || targetIndex == null) {
      return widget.selectedCharacters;
    }

    final sourceIndex = widget.selectedCharacters.indexWhere(
      (character) => _isSameCharacter(character, draggingCharacter),
    );
    if (sourceIndex < 0) {
      return widget.selectedCharacters;
    }

    final nextCharacters = [...widget.selectedCharacters];
    final movedCharacter = nextCharacters.removeAt(sourceIndex);
    final normalizedTargetIndex = targetIndex.clamp(0, nextCharacters.length);
    nextCharacters.insert(normalizedTargetIndex, movedCharacter);
    return nextCharacters;
  }

  void _previewMove(NexonCharacterSummary character, int targetIndex) {
    if (!mounted || targetIndex < 0) {
      return;
    }
    final draggingCharacter = _draggingCharacter;
    if (draggingCharacter != null &&
        _isSameCharacter(draggingCharacter, character) &&
        _previewTargetIndex == targetIndex) {
      return;
    }
    setState(() {
      _draggingCharacter = character;
      _previewTargetIndex = targetIndex;
    });
  }

  void _clearPreview() {
    if (!mounted) {
      return;
    }
    setState(() {
      _draggingCharacter = null;
      _previewTargetIndex = null;
    });
  }

  void _commitMove(NexonCharacterSummary draggedCharacter, int targetIndex) {
    if (targetIndex < 0) {
      _clearPreview();
      return;
    }
    _clearPreview();
    widget.onMoveCharacter(draggedCharacter, targetIndex);
  }

  void _finishDrag(NexonCharacterSummary draggedCharacter) {
    final targetIndex = _previewTargetIndex;
    final draggingCharacter = _draggingCharacter;
    if (targetIndex == null ||
        draggingCharacter == null ||
        !_isSameCharacter(draggingCharacter, draggedCharacter)) {
      _clearPreview();
      return;
    }

    _commitMove(draggedCharacter, targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    const spacing = 18.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = (width - spacing * (widget.crossAxisCount - 1)) /
            widget.crossAxisCount;
        final cardHeight = cardWidth / 0.9;
        final displayedCharacters = _previewCharacters;
        final itemCount = displayedCharacters.length + 1;
        final rowCount = (itemCount / widget.crossAxisCount).ceil();
        final totalHeight =
            rowCount * cardHeight + (rowCount > 1 ? rowCount - 1 : 0) * spacing;

        return SingleChildScrollView(
          child: SizedBox(
            height: totalHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final entry in displayedCharacters.indexed)
                  _AnimatedCharacterGridItem(
                    key: ValueKey('character-${entry.$2.ocid}'),
                    index: entry.$1,
                    crossAxisCount: widget.crossAxisCount,
                    width: cardWidth,
                    height: cardHeight,
                    spacing: spacing,
                    child: _DraggableCharacterCard(
                      character: entry.$2,
                      selected: _isSameCharacter(
                        entry.$2,
                        widget.selectedCharacter,
                      ),
                      notificationEnabled:
                          !widget.notificationDisabledOcids.contains(
                        entry.$2.ocid,
                      ),
                      onTap: () => widget.onSelectCharacter(entry.$2),
                      onDelete: () => widget.onDeleteCharacter(entry.$2),
                      onDragStarted: () => _previewMove(
                        entry.$2,
                        widget.selectedCharacters.indexWhere(
                          (character) => _isSameCharacter(character, entry.$2),
                        ),
                      ),
                      onDragEnded: () => _finishDrag(entry.$2),
                      onDragCanceled: _clearPreview,
                      onPreviewMove: (draggedCharacter) => _previewMove(
                        draggedCharacter,
                        displayedCharacters.indexWhere(
                          (character) => _isSameCharacter(character, entry.$2),
                        ),
                      ),
                      onToggleNotification: () =>
                          widget.onToggleCharacterNotification(entry.$2),
                    ),
                  ),
                _AnimatedCharacterGridItem(
                  key: const ValueKey('add-character-card'),
                  index: displayedCharacters.length,
                  crossAxisCount: widget.crossAxisCount,
                  width: cardWidth,
                  height: cardHeight,
                  spacing: spacing,
                  child: _AddCharacterCard(
                    loading: widget.isLoading,
                    onTap: widget.isLoading ? null : widget.onAddCharacter,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedCharacterGridItem extends StatelessWidget {
  const _AnimatedCharacterGridItem({
    super.key,
    required this.index,
    required this.crossAxisCount,
    required this.width,
    required this.height,
    required this.spacing,
    required this.child,
  });

  final int index;
  final int crossAxisCount;
  final double width;
  final double height;
  final double spacing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final row = index ~/ crossAxisCount;
    final column = index % crossAxisCount;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: column * (width + spacing),
      top: row * (height + spacing),
      width: width,
      height: height,
      child: child,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1D6CC)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB85F47),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _LockedFeaturePanel extends StatelessWidget {
  const _LockedFeaturePanel({
    required this.section,
    required this.selectedCharacter,
    required this.schedulerSnapshot,
    required this.noticeItems,
    required this.sundayEvent,
    required this.schedulerLoading,
    required this.noticeLoading,
    required this.schedulerErrorMessage,
    required this.noticeErrorMessage,
    required this.onSelectSection,
  });

  final AppSection section;
  final NexonCharacterSummary? selectedCharacter;
  final SchedulerSnapshot? schedulerSnapshot;
  final List<NoticeItemSummary> noticeItems;
  final NoticeItemSummary? sundayEvent;
  final bool schedulerLoading;
  final bool noticeLoading;
  final String? schedulerErrorMessage;
  final String? noticeErrorMessage;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    if (selectedCharacter == null) {
      return const _BlockedPanel();
    }

    if (section != AppSection.scheduler) {
      return switch (section) {
        AppSection.events => _EventOverviewPanel(
            items: noticeItems
                .where((item) => item.noticeType == 'event')
                .toList(),
            loading: noticeLoading,
            errorMessage: noticeErrorMessage,
            onOpenSunday: () => onSelectSection(AppSection.sunday),
          ),
        AppSection.notices => _NoticeOverviewPanel(
            items: noticeItems
                .where((item) => item.noticeType != 'event')
                .toList(),
            loading: noticeLoading,
            errorMessage: noticeErrorMessage,
          ),
        AppSection.sunday => _SundayOverviewPanel(event: sundayEvent),
        AppSection.dashboard ||
        AppSection.character ||
        AppSection.party ||
        AppSection.scheduler ||
        AppSection.settings =>
          const SizedBox.shrink(),
      };
    }

    return _SchedulerOverviewPanel(
      snapshot: schedulerSnapshot,
      loading: schedulerLoading,
      errorMessage: schedulerErrorMessage,
    );
  }
}

class _SchedulerOverviewPanel extends StatelessWidget {
  const _SchedulerOverviewPanel({
    required this.snapshot,
    required this.loading,
    required this.errorMessage,
  });

  final SchedulerSnapshot? snapshot;
  final bool loading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (errorMessage != null) {
      return _InlineError(message: errorMessage!);
    }

    final data = snapshot;
    if (data == null) {
      return const _BlockedPanel();
    }
    final dailyItems = _groupDailyQuestItems(data.dailyItems);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final left = Column(
          children: [
            _SchedulerCard(
              title: '일일 콘텐츠',
              items: dailyItems,
              emptyMessage: '오늘 접속 기록이 아직 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
            ),
            const SizedBox(height: 20),
            _SchedulerCard(
              title: '주간 콘텐츠',
              items: data.weeklyItems,
              emptyMessage: '이번주에 완료한 주간 콘텐츠가 없습니다.\n게임에 접속하여 주간 퀘스트를 완료 해주세요.',
            ),
          ],
        );
        final right = Column(
          children: [
            _BossSchedulerCard(title: '보스 콘텐츠', items: data.bossItems),
          ],
        );

        if (compact) {
          return SingleChildScrollView(
            child: Column(
              children: [
                _SchedulerCard(
                  title: '일일 콘텐츠',
                  items: dailyItems,
                  emptyMessage: '오늘 접속 기록이 아직 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
                ),
                const SizedBox(height: 20),
                _SchedulerCard(
                  title: '주간 콘텐츠',
                  items: data.weeklyItems,
                  emptyMessage:
                      '이번주에 완료한 주간 콘텐츠가 없습니다.\n게임에 접속하여 주간 퀘스트를 완료 해주세요.',
                ),
                const SizedBox(height: 20),
                _BossSchedulerCard(title: '보스 콘텐츠', items: data.bossItems),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 20),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }
}

List<SchedulerItemSummary> _groupDailyQuestItems(
  List<SchedulerItemSummary> items,
) {
  const arcaneRiverRegions = [
    '소멸의 여로',
    '츄츄 아일랜드',
    '레헬른',
    '아르카나',
    '모라스',
    '에스페라',
    '셀라스',
    '문브릿지',
    '고통의 미궁',
    '리멘',
  ];
  const grandisRegions = [
    '세르니움',
    '호텔 아르크스',
    '오디움',
    '도원경',
    '아르테리아',
    '카르시온',
    '탈라하트',
  ];

  final remainingItems = <SchedulerItemSummary>[];
  final arcaneRiverQuests = <SchedulerItemSummary>[];
  final grandisQuests = <SchedulerItemSummary>[];

  for (final item in items) {
    if (!item.title.contains('[일일 퀘스트]')) {
      remainingItems.add(item);
    } else if (arcaneRiverRegions.any(item.title.contains)) {
      arcaneRiverQuests.add(item);
    } else if (grandisRegions.any(item.title.contains)) {
      grandisQuests.add(item);
    } else {
      remainingItems.add(item);
    }
  }

  return [
    ...remainingItems,
    if (arcaneRiverQuests.isNotEmpty)
      _dailyQuestGroupItem('아케인리버 일일퀘스트', arcaneRiverQuests),
    if (grandisQuests.isNotEmpty)
      _dailyQuestGroupItem('그란디스 일일퀘스트', grandisQuests),
  ];
}

SchedulerItemSummary _dailyQuestGroupItem(
  String title,
  List<SchedulerItemSummary> quests,
) {
  final completedCount = quests.where((quest) => quest.done).length;
  final totalCount = quests.length;

  return SchedulerItemSummary(
    title: title,
    meta: '$completedCount / $totalCount',
    difficulty: '',
    cycle: '',
    done: completedCount == totalCount,
    currentCount: completedCount,
    maxCount: totalCount,
  );
}

class _SchedulerCard extends StatelessWidget {
  const _SchedulerCard({
    required this.title,
    required this.items,
    this.emptyMessage = '아직 조회된 숙제 정보가 없어요.\n게임 접속 후 잠시 뒤 다시 확인해주세요.',
  });

  final String title;
  final List<SchedulerItemSummary> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: items.isEmpty
                ? Text(
                    emptyMessage,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  )
                : Column(
                    children: items
                        .map((item) => _SchedulerItemRow(item: item))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BossSchedulerCard extends StatelessWidget {
  const _BossSchedulerCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<SchedulerItemSummary> items;

  @override
  Widget build(BuildContext context) {
    final groupedItems = {
      'DAILY': items.where(_isDailyBoss).toList(),
      'WEEKLY': items.where(_isWeeklyBoss).toList(),
      'MONTHLY': items.where(_isMonthlyBoss).toList(),
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: items.isEmpty
                ? const Text(
                    '아직 이번주에 처치한 보스가 없습니다.\n게임에 접속하여 보스를 처치해주세요.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  )
                : Column(
                    children: groupedItems.entries
                        .where((entry) => entry.value.isNotEmpty)
                        .map(
                          (entry) => _BossCycleSection(
                            title: entry.key,
                            items: entry.value,
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  static bool _isDailyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('daily') || cycle.contains('day');
  }

  static bool _isWeeklyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('weekly') || cycle.contains('week');
  }

  static bool _isMonthlyBoss(SchedulerItemSummary item) {
    final cycle = item.cycle.toLowerCase();
    return cycle.contains('monthly') || cycle.contains('month');
  }
}

class _BossCycleSection extends StatelessWidget {
  const _BossCycleSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<SchedulerItemSummary> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFA7B0B7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ...items.map((item) => _SchedulerItemRow(item: item)),
        ],
      ),
    );
  }
}

class _SchedulerItemRow extends StatelessWidget {
  const _SchedulerItemRow({required this.item});

  final SchedulerItemSummary item;

  @override
  Widget build(BuildContext context) {
    final color = item.done ? const Color(0xFFFFFFFF) : const Color(0xFF111111);
    final background = item.done ? const Color(0xFF7A818A) : AppColors.surface;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Row(
        children: [
          if (item.difficulty.isNotEmpty) ...[
            _BossIconImage(
              bossName: item.title,
              size: 30,
              fallbackTextColor: color,
            ),
            const SizedBox(width: 10),
          ],
          if (item.difficulty.isNotEmpty) ...[
            _BossDifficultyBadge(difficulty: item.difficulty),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (item.meta.isNotEmpty)
            Text(
              item.meta,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _BossDifficultyBadge extends StatelessWidget {
  const _BossDifficultyBadge({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final label = difficulty.toUpperCase();
    final normalized = difficulty.toLowerCase();
    final isChaos = normalized.contains('chaos');
    final isExtreme = normalized.contains('extreme');
    const chaosGold = Color(0xFFD9B75B);
    const extremeRed = Color(0xFFD84E66);
    final background = isExtreme
        ? const Color(0xFF2D252B)
        : normalized.contains('hard')
            ? const Color(0xFF965271)
            : normalized.contains('normal')
                ? const Color(0xFF436F86)
                : const Color(0xFF3E4147);
    final borderColor = isExtreme
        ? extremeRed
        : isChaos
            ? chaosGold
            : null;
    final textShadowColor = isExtreme
        ? extremeRed
        : isChaos
            ? chaosGold
            : null;

    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            shadows: textShadowColor == null
                ? null
                : [
                    Shadow(
                      color: textShadowColor,
                      offset: const Offset(0, 0),
                      blurRadius: 1,
                    ),
                  ]),
      ),
    );
  }
}

class _BossIconImage extends StatelessWidget {
  const _BossIconImage({
    required this.bossName,
    required this.size,
    this.fallbackTextColor = AppColors.text,
  });

  final String bossName;
  final double size;
  final Color fallbackTextColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        _partyBossImageAsset(bossName),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selected,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.softBorder),
            ),
            child: Text(
              bossName.characters.isEmpty ? '?' : bossName.characters.first,
              style: TextStyle(
                color: fallbackTextColor,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EventOverviewPanel extends StatelessWidget {
  const _EventOverviewPanel({
    required this.items,
    required this.loading,
    required this.errorMessage,
    required this.onOpenSunday,
  });

  final List<NoticeItemSummary> items;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onOpenSunday;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (errorMessage != null) {
      return _InlineError(message: errorMessage!);
    }

    if (items.isEmpty) {
      return const _EmptyDataPanel(message: '진행중인 이벤트가 없어요.');
    }

    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 1180 ? 3 : 2,
      childAspectRatio: 1.06,
      crossAxisSpacing: 24,
      mainAxisSpacing: 30,
      children: items
          .map((item) => _InfoCard(
                title: item.title,
                meta: item.eventPeriodText.isEmpty
                    ? item.label
                    : item.eventPeriodText,
                thumbnail: item.thumbnail,
                link: item.link,
                onTap: _isSundayMapleEvent(item) ? onOpenSunday : null,
              ))
          .toList(),
    );
  }
}

class _NoticeOverviewPanel extends StatefulWidget {
  const _NoticeOverviewPanel({
    required this.items,
    required this.loading,
    required this.errorMessage,
  });

  final List<NoticeItemSummary> items;
  final bool loading;
  final String? errorMessage;

  @override
  State<_NoticeOverviewPanel> createState() => _NoticeOverviewPanelState();
}

enum NoticeCategory {
  all('전체', null),
  notice('공지', 'notice'),
  maintenance('점검', 'maintenance'),
  update('업데이트', 'update'),
  cashshop('캐시샵', 'cashshop');

  const NoticeCategory(this.label, this.type);

  final String label;
  final String? type;
}

class _NoticeOverviewPanelState extends State<_NoticeOverviewPanel> {
  var selectedCategory = NoticeCategory.all;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (widget.errorMessage != null) {
      return _InlineError(message: widget.errorMessage!);
    }

    final filteredItems = selectedCategory.type == null
        ? widget.items
        : widget.items
            .where((item) => item.displayType == selectedCategory.type)
            .toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _NoticeTabBar(
            selectedCategory: selectedCategory,
            onChanged: (category) {
              setState(() {
                selectedCategory = category;
              });
            },
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(
                    child: Text(
                      '공지사항이 없어요.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : selectedCategory == NoticeCategory.cashshop
                    ? _CashshopCardGrid(items: filteredItems)
                    : ListView(
                        children: filteredItems
                            .map(
                              (item) => _NoticeListRow(
                                tag: item.label,
                                title: item.title,
                                date: item.dateText,
                                link: item.link,
                              ),
                            )
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CashshopCardGrid extends StatelessWidget {
  const _CashshopCardGrid({required this.items});

  final List<NoticeItemSummary> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;

        return GridView.count(
          padding: const EdgeInsets.all(22),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.55,
          crossAxisSpacing: 24,
          mainAxisSpacing: 26,
          children: items
              .map(
                (item) => _CashshopCard(
                  title: item.title,
                  meta: item.cashshopPeriodText,
                  thumbnail: item.thumbnail,
                  link: item.link,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _CashshopCard extends StatelessWidget {
  const _CashshopCard({
    required this.title,
    required this.meta,
    required this.thumbnail,
    required this.link,
  });

  final String title;
  final String meta;
  final String thumbnail;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: AspectRatio(
              aspectRatio: 10 / 3,
              child: _LinkTapArea(
                link: link,
                child: _EventThumbnail(thumbnail: thumbnail),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _LinkTapArea(
                  link: link,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                meta,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDataPanel extends StatelessWidget {
  const _EmptyDataPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.softBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SundayOverviewPanel extends StatelessWidget {
  const _SundayOverviewPanel({required this.event});

  final NoticeItemSummary? event;

  @override
  Widget build(BuildContext context) {
    final sundayEvent = event;

    if (sundayEvent != null) {
      if (sundayEvent.contentImageUrls.isNotEmpty) {
        return _SundayContentPanel(event: sundayEvent);
      }

      if (sundayEvent.thumbnail.isEmpty) {
        return const _EmptyDataPanel(
          message: '이번주 썬데이 메이플 공지가 아직 없습니다',
        );
      }

      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _InfoCard(
            title: sundayEvent.title,
            meta: sundayEvent.eventPeriodText,
            thumbnail: sundayEvent.thumbnail,
            link: sundayEvent.link,
          ),
        ),
      );
    }

    return const _EmptyDataPanel(
      message: '아직 저장된 이번주 썬데이 정보가 없어요.\n썬데이 메이플 이벤트가 등록되면 자동으로 업데이트됩니다.',
    );
  }
}

class _SundayContentPanel extends StatelessWidget {
  const _SundayContentPanel({required this.event});

  final NoticeItemSummary event;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: event.contentImageUrls.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final imageUrl = event.contentImageUrls[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _LinkTapArea(
              link: event.link,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _InfoCard(
                      title: event.title,
                      meta: event.eventPeriodText,
                      thumbnail: event.thumbnail,
                      link: event.link,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _sectionLabel(AppSection section, List<NoticeItemSummary> noticeItems) {
  if (section == AppSection.sunday) {
    return _findSpecialSundayEvent(noticeItems) == null ? '지난 썬데이' : '이번주 썬데이';
  }
  return section.label;
}

NoticeItemSummary? _findSpecialSundayEvent(List<NoticeItemSummary> items) {
  for (final item in items) {
    if (_isSundayMapleEvent(item)) {
      return item;
    }
  }
  return null;
}

bool _isSundayMapleEvent(NoticeItemSummary item) {
  return item.noticeType == 'event' &&
      (item.title == '스페셜 썬데이 메이플' || item.title == '썬데이 메이플');
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.meta,
    required this.thumbnail,
    required this.link,
    this.onTap,
  });

  final String title;
  final String meta;
  final String thumbnail;
  final String link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 124,
            child: _LinkTapArea(
              link: link,
              onTap: onTap,
              child: _EventThumbnail(thumbnail: thumbnail),
            ),
          ),
          SizedBox(
            height: 96,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _LinkTapArea(
                  link: link,
                  onTap: onTap,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                meta,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventThumbnail extends StatelessWidget {
  const _EventThumbnail({required this.thumbnail});

  final String thumbnail;

  @override
  Widget build(BuildContext context) {
    if (thumbnail.isEmpty) {
      return Container(
        color: const Color(0xFFF0F2F6),
        alignment: Alignment.center,
        child: const Text(
          'EVENT',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.surface,
      child: Image.network(
        thumbnail,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFFF0F2F6),
            alignment: Alignment.center,
            child: const Text(
              'EVENT',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<List<NoticeItemSummary>> _mergeCurrentNoticeItemsWithEventCache(
  List<NoticeItemSummary> fetchedItems,
  EventNoticeCache eventCache,
) async {
  final now = DateTime.now();
  final fetchedEvents =
      fetchedItems.where((item) => item.noticeType == 'event');
  final cachedEvents = await eventCache.load();
  final eventsByKey = <String, NoticeItemSummary>{
    for (final event in cachedEvents)
      if (!_isEventEnded(event, now)) event.notificationKey: event,
  };

  for (final event in fetchedEvents) {
    if (!_isEventEnded(event, now)) {
      eventsByKey[event.notificationKey] = event;
    }
  }

  final mergedItems = <NoticeItemSummary>[];
  final emittedKeys = <String>{};
  for (final item in fetchedItems) {
    if (item.noticeType == 'event') {
      final event = eventsByKey[item.notificationKey];
      if (event != null && emittedKeys.add(event.notificationKey)) {
        mergedItems.add(event);
      }
      continue;
    }
    mergedItems.add(item);
  }

  for (final event in eventsByKey.values) {
    if (emittedKeys.add(event.notificationKey)) {
      mergedItems.add(event);
    }
  }

  await eventCache.save(eventsByKey.values.toList());
  return mergedItems;
}

bool _isEventEnded(NoticeItemSummary event, DateTime now) {
  final endDate = _noticeDateOnly(event.eventEndAt);
  if (endDate == null) {
    return false;
  }
  final today = DateTime(now.year, now.month, now.day);
  return endDate.isBefore(today);
}

bool _isSnapshotEventEnded(Map<String, String> snapshot, DateTime now) {
  final endDate = _noticeDateOnly(snapshot['eventEndAt'] ?? '');
  if (endDate == null) {
    return false;
  }
  final today = DateTime(now.year, now.month, now.day);
  return endDate.isBefore(today);
}

DateTime? _noticeDateOnly(String value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(value);
  if (match == null) {
    return null;
  }
  final parts = match.group(0)!.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

class _LinkTapArea extends StatelessWidget {
  const _LinkTapArea({
    required this.link,
    required this.child,
    this.onTap,
  });

  final String link;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final handler =
        onTap ?? (link.trim().isEmpty ? null : () => _openExternalUrl(link));
    if (handler == null) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handler,
        child: child,
      ),
    );
  }
}

Future<void> _openExternalUrl(String link) async {
  final url = link.trim();
  if (url.isEmpty) {
    return;
  }

  await Process.start(
    'rundll32.exe',
    ['url.dll,FileProtocolHandler', url],
  );
}

class _NoticeTabBar extends StatelessWidget {
  const _NoticeTabBar({
    required this.selectedCategory,
    required this.onChanged,
  });

  final NoticeCategory selectedCategory;
  final ValueChanged<NoticeCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: NoticeCategory.values
          .map(
            (category) => _NoticeTab(
              label: category.label,
              active: selectedCategory == category,
              onTap: () => onChanged(category),
            ),
          )
          .toList(),
    );
  }
}

class _NoticeTab extends StatelessWidget {
  const _NoticeTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 4, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeListRow extends StatelessWidget {
  const _NoticeListRow({
    required this.tag,
    required this.title,
    required this.date,
    required this.link,
  });

  final String tag;
  final String title;
  final String date;
  final String link;

  @override
  Widget build(BuildContext context) {
    final tagColor = switch (tag) {
      '점검' => const Color(0xFF55B3BF),
      '업데이트' => const Color(0xFFFFEEFF),
      _ => AppColors.primary,
    };
    final tagBorderColor = switch (tag) {
      '업데이트' => const Color(0xFFFF9EF4),
      _ => tagColor,
    };
    final tagTextColor = switch (tag) {
      '업데이트' => const Color(0xFFE24AD7),
      _ => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tagBorderColor),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: tagTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _LinkTapArea(
              link: link,
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Text(
            date,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: AppColors.disabled, size: 28),
          SizedBox(height: 12),
          Text(
            '캐릭터 선택이 필요해요.',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '왼쪽의 캐릭터 추가를 눌러 알림 대상 캐릭터를 먼저 선택해주세요.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraggableCharacterCard extends StatelessWidget {
  const _DraggableCharacterCard({
    required this.character,
    required this.selected,
    required this.notificationEnabled,
    required this.onTap,
    required this.onDelete,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDragCanceled,
    required this.onPreviewMove,
    required this.onToggleNotification,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final bool notificationEnabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final VoidCallback onDragCanceled;
  final ValueChanged<NexonCharacterSummary> onPreviewMove;
  final VoidCallback onToggleNotification;

  @override
  Widget build(BuildContext context) {
    final card = _CharacterCard(
      character: character,
      selected: selected,
      notificationEnabled: notificationEnabled,
      onTap: onTap,
      onDelete: onDelete,
      onToggleNotification: onToggleNotification,
    );

    return DragTarget<NexonCharacterSummary>(
      onWillAcceptWithDetails: (details) {
        if (_isSameCharacter(details.data, character)) {
          return false;
        }
        onPreviewMove(details.data);
        return true;
      },
      onAcceptWithDetails: (_) {},
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return LongPressDraggable<NexonCharacterSummary>(
          data: character,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnded(),
          onDraggableCanceled: (_, __) => onDragCanceled(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 190, height: 220, child: card),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: isHovering
                  ? [
                      BoxShadow(
                        color: AppColors.navAccent.withValues(alpha: 0.2),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: card,
          ),
        );
      },
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.selected,
    required this.notificationEnabled,
    required this.onTap,
    required this.onDelete,
    required this.onToggleNotification,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final bool notificationEnabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleNotification;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF4EC) : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: 2,
            color: selected ? AppColors.navBorder : AppColors.softBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _CharacterImage(character: character, radius: 12),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 42,
                    child: _CharacterNotificationBadge(
                      enabled: notificationEnabled,
                      onPressed: onToggleNotification,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _CharacterCardMenu(
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayCharacterName(character),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.navAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '선택됨',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              _characterDescription(character),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterNotificationBadge extends StatelessWidget {
  const _CharacterNotificationBadge({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? '알림 켜짐' : '알림 꺼짐',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xEBFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: enabled ? AppColors.navBorder : AppColors.border,
              ),
            ),
            child: Icon(
              enabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: enabled ? AppColors.navAccent : AppColors.muted,
              size: 17,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterCardMenu extends StatelessWidget {
  const _CharacterCardMenu({
    required this.onDelete,
  });

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '캐릭터 관리',
      color: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'delete',
          child: Text('삭제'),
        ),
      ],
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xEBFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: AppColors.text,
          size: 18,
        ),
      ),
    );
  }
}

class _AddCharacterCard extends StatelessWidget {
  const _AddCharacterCard({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.navBorder, width: 2),
        ),
        child: Center(
          child: loading
              ? const CircularProgressIndicator(color: AppColors.navAccent)
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+',
                      style: TextStyle(
                        color: AppColors.navAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '캐릭터 추가',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CharacterPickerDialog extends StatefulWidget {
  const _CharacterPickerDialog({
    required this.characters,
    required this.selectedCharacter,
    required this.selectedCharacters,
    required this.loadCharacterBasic,
    required this.cacheCharacterBasics,
  });

  final List<NexonCharacterSummary> characters;
  final NexonCharacterSummary? selectedCharacter;
  final List<NexonCharacterSummary> selectedCharacters;
  final Future<NexonCharacterSummary> Function(NexonCharacterSummary character)
      loadCharacterBasic;
  final Future<void> Function(Iterable<NexonCharacterSummary> characters)
      cacheCharacterBasics;

  @override
  State<_CharacterPickerDialog> createState() => _CharacterPickerDialogState();
}

class _CharacterPickerDialogState extends State<_CharacterPickerDialog> {
  late List<NexonCharacterSummary> characters;

  @override
  void initState() {
    super.initState();
    characters = [...widget.characters];
    unawaited(_loadMissingCharacterImages());
  }

  Future<void> _loadMissingCharacterImages() async {
    const batchSize = 4;
    final missingImageCharacters = characters
        .where((character) => character.characterImage.isEmpty)
        .toList();
    for (var start = 0;
        start < missingImageCharacters.length;
        start += batchSize) {
      final end = start + batchSize > missingImageCharacters.length
          ? missingImageCharacters.length
          : start + batchSize;
      final batch = missingImageCharacters.sublist(start, end);
      final details = await Future.wait(
        batch.map(widget.loadCharacterBasic),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        for (final detail in details) {
          final index = characters.indexWhere(
            (character) => character.ocid == detail.ocid,
          );
          if (index != -1) {
            characters[index] = characters[index].merge(detail);
          }
        }
      });
      await widget.cacheCharacterBasics(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: dialogSize.height * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '캐릭터 선택',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    '불러온 캐릭터가 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = constraints.maxWidth >= 740
                          ? 4
                          : constraints.maxWidth >= 520
                              ? 3
                              : 2;
                      return GridView.builder(
                        itemCount: characters.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columnCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemBuilder: (context, index) {
                          final character = characters[index];
                          final selected = _isSameCharacter(
                            character,
                            widget.selectedCharacter,
                          );
                          final added = widget.selectedCharacters.any(
                            (selectedCharacter) =>
                                _isSameCharacter(character, selectedCharacter),
                          );

                          return _CharacterPickerCard(
                            character: character,
                            selected: selected,
                            added: added,
                            onTap: () => Navigator.of(context).pop(character),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterPickerCard extends StatelessWidget {
  const _CharacterPickerCard({
    required this.character,
    required this.selected,
    required this.added,
    required this.onTap,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF4EC) : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? AppColors.navBorder : AppColors.softBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _CharacterImage(character: character, radius: 8),
                      ),
                    ),
                    if (added)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.navAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _displayCharacterName(character),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _characterDescription(character),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterImage extends StatelessWidget {
  const _CharacterImage({
    required this.character,
    required this.radius,
  });

  final NexonCharacterSummary character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = character.characterImage;
    final image = imageUrl.isEmpty
        ? _CharacterImageFallback(character: character)
        : Image.network(
            imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) =>
                _CharacterImageFallback(character: character),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Transform.scale(
              scale: 1.45,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterImageFallback extends StatelessWidget {
  const _CharacterImageFallback({required this.character});

  final NexonCharacterSummary character;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F2F6),
      alignment: Alignment.center,
      child: Text(
        character.characterName.isEmpty
            ? '?'
            : character.characterName.characters.first,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WorldImage extends StatelessWidget {
  const _WorldImage({
    required this.character,
    required this.radius,
  });

  final NexonCharacterSummary character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final assetPath = _worldImageAsset(character.worldName);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: const Color(0xFFFFFBF2),
        child: assetPath.isEmpty
            ? _CharacterImageFallback(character: character)
            : Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _CharacterImageFallback(character: character),
                ),
              ),
      ),
    );
  }
}

String _worldImageAsset(String worldName) {
  final normalized = worldName.replaceAll(' ', '');
  const worlds = [
    '스카니아',
    '베라',
    '루나',
    '제니스',
    '크로아',
    '유니온',
    '엘리시움',
    '이노시스',
    '레드',
    '오로라',
    '아케인',
    '노바',
    '챌린저스',
    '에오스',
    '헬리오스',
  ];

  for (final world in worlds) {
    if (normalized.contains(world)) {
      return 'assets/images/worlds/$world.png';
    }
  }
  return '';
}

String _displayCharacterName(NexonCharacterSummary character) {
  return character.characterName.isEmpty ? '이름 없음' : character.characterName;
}

String _characterDescription(NexonCharacterSummary character) {
  return [
    character.worldName,
    character.characterClass,
    if (character.characterLevel != null) 'Lv.${character.characterLevel}',
  ].where((value) => value.isNotEmpty).join(' · ');
}

bool _isSameCharacter(
  NexonCharacterSummary character,
  NexonCharacterSummary? other,
) {
  if (other == null) {
    return false;
  }

  if (character.ocid.isNotEmpty && other.ocid.isNotEmpty) {
    return character.ocid == other.ocid;
  }

  return character.characterName == other.characterName &&
      character.worldName == other.worldName;
}
