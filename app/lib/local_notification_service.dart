import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapHandler = void Function(String? payload);

class LocalNotificationService {
  LocalNotificationService._();

  static final instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _initialized = false;
  NotificationTapHandler? _onNotificationTap;

  void setOnNotificationTap(NotificationTapHandler handler) {
    _onNotificationTap = handler;
  }

  Future<String?> initialize() async {
    if (_initialized) {
      return null;
    }

    await _plugin.initialize(
      const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: '메이플 숙제알리미',
          appUserModelId: 'com.rladbcks.mapleTaskReminder',
          guid: 'c38f2ca6-8c2a-47a8-bfa8-f4c5d1e2d7bc',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        _onNotificationTap?.call(response.payload);
      },
    );
    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      return launchDetails?.notificationResponse?.payload;
    }
    return null;
  }

  Future<void> showTestNotification() async {
    await showNotification(
      id: 1,
      title: '메이플 숙제알리미',
      body: '알림이 정상적으로 작동합니다.',
      payload: 'section:scheduler',
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
        ),
      ),
      payload: payload,
    );
  }
}
