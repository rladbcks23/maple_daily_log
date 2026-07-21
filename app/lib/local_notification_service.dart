import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _initialized = false;

  Future<void> showTestNotification() async {
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
      1,
      '메이플 숙제알리미',
      '알림이 정상적으로 작동합니다.',
      const NotificationDetails(
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
        ),
      ),
    );
  }
}
