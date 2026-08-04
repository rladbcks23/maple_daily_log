import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class AppLifecycleService {
  AppLifecycleService({
    required Size mainWindowSize,
    MethodChannel? nativeWindowChannel,
    int singleInstancePort = 48721,
  })  : _mainWindowSize = mainWindowSize,
        _nativeWindowChannel = nativeWindowChannel ??
            const MethodChannel('maple_task_reminder/window'),
        _singleInstancePort = singleInstancePort;

  final Size _mainWindowSize;
  final MethodChannel _nativeWindowChannel;
  final int _singleInstancePort;
  final _showRequests = StreamController<void>.broadcast();

  ServerSocket? _singleInstanceSocket;
  var _isExitingMainApplication = false;
  var _isHidingMainWindowToTray = false;
  var _isShowingMainWindowFromTray = false;

  Stream<void> get showRequests => _showRequests.stream;

  Future<void> prepareMainWindowControls() async {
    await lockCurrentWindowSize(_mainWindowSize);
    if (!Platform.isWindows) {
      await windowManager.setPreventClose(true);
    }
  }

  Future<void> lockCurrentWindowSize(Size size) async {
    await windowManager.setSize(size);
    await windowManager.setMinimumSize(size);
    await windowManager.setMaximumSize(size);
    await windowManager.setResizable(false);
  }

  Future<void> hideMainWindowToTray() async {
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

  Future<void> showMainWindowFromTray() async {
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
    } finally {
      _isShowingMainWindowFromTray = false;
    }
  }

  Future<void> exitMainApplication() async {
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

  Future<bool> ensureSingleMainInstance() async {
    try {
      _singleInstanceSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _singleInstancePort,
        shared: false,
      );
      _listenForSingleInstanceSignals(_singleInstanceSocket!);
      return true;
    } on SocketException {
      await _notifyExistingMainInstance();
      return false;
    }
  }

  void _listenForSingleInstanceSignals(ServerSocket serverSocket) {
    serverSocket.listen((client) {
      unawaited(() async {
        try {
          final command = (await utf8.decoder.bind(client).join()).trim();
          if (command == _singleInstanceShowCommand) {
            _showRequests.add(null);
          }
        } catch (error) {
          debugPrint('Failed to process single-instance signal: $error');
        } finally {
          await client.close();
        }
      }());
    });
  }

  Future<void> _notifyExistingMainInstance() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _singleInstancePort,
        timeout: const Duration(milliseconds: 800),
      );
      socket.write(_singleInstanceShowCommand);
      await socket.flush();
      await socket.close();
    } catch (_) {
      // Existing instance may still be starting up; fail closed to avoid
      // opening a second long-running tray process.
    }
  }

  static const _singleInstanceShowCommand = 'show';
}
