import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _initialized = false;

  Future<void> showTestNotification() async {
    await showNotification(
      id: 1,
      title: '메이플 숙제알리미',
      body: '알림이 정상적으로 작동합니다.',
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await _plugin.initialize(
        const InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: '메이플 숙제알리미',
            appUserModelId: 'com.rladbcks.mapleTaskReminder',
            guid: 'c38f2ca6-8c2a-47a8-bfa8-f4c5d1e2d7bc',
          ),
        ),
      );
      _initialized = true;
    }

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
        ),
      ),
    );
  }
}
