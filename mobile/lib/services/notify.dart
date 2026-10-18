// Notification channels: one per civil-defence signal (own tone, alarm audio usage, full-screen),
// plus boundary messages and incoming calls.
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef TapHandler = void Function(String? payload);

class Notify {
  static final plugin = FlutterLocalNotificationsPlugin();
  static TapHandler? onTap;

  static const _channels = <String, (String, String?)>{
    'signal1': ('الإشارة 1 · طوارئ', 'signal1'),
    'signal2': ('الإشارة 2 · إخلاء', 'signal2'),
    'signal3': ('الإشارة 3 · زوال الخطر', 'signal3'),
    'koc_msg': ('رسائل وتنبيهات الحدود', null),
    'koc_call': ('مكالمات ORT', null),
  };

  static Future<void> init() async {
    await plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final e in _channels.entries) {
      final isSignal = e.value.$2 != null;
      await android?.createNotificationChannel(AndroidNotificationChannel(
        e.key,
        e.value.$1,
        description: e.value.$1,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: isSignal ? RawResourceAndroidNotificationSound(e.value.$2!) : null,
        audioAttributesUsage: isSignal || e.key == 'koc_call' ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      ));
    }
  }

  static Future<String?> launchPayload() async {
    final d = await plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
  }

  static Future<void> requestPermissions() async {
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  static int _id(String s) => s.hashCode & 0x7fffffff;

  static Future<void> alarm(String alarmId, String kind, String title, String body) async {
    final channel = _channels.containsKey(kind) ? kind : 'koc_msg';
    final isSignal = kind.startsWith('signal');
    await plugin.show(
      _id(alarmId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          _channels[channel]!.$1,
          importance: Importance.max,
          priority: Priority.max,
          category: isSignal ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.message,
          fullScreenIntent: isSignal && kind != 'signal3',
          audioAttributesUsage: isSignal ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
          styleInformation: BigTextStyleInformation(body),
          ongoing: isSignal && kind != 'signal3',
          autoCancel: true,
          // FLAG_INSISTENT: repeat the tone until the employee responds
          additionalFlags: isSignal && kind != 'signal3' ? Int32List.fromList(<int>[4]) : null,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: 'alarm:$alarmId',
    );
  }

  static Future<void> cancelAlarm(String alarmId) => plugin.cancel(_id(alarmId));

  static Future<void> message(String key, String title, String body) => plugin.show(
        _id(key),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails('koc_msg', _channels['koc_msg']!.$1,
              importance: Importance.high, priority: Priority.high, styleInformation: BigTextStyleInformation(body)),
        ),
        payload: 'msg:$key',
      );

  static Future<void> incomingCall(String callId, String caller) => plugin.show(
        _id(callId),
        'مكالمة من $caller',
        'اضغط للرد — مركز 160',
        NotificationDetails(
          android: AndroidNotificationDetails('koc_call', _channels['koc_call']!.$1,
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.call,
              fullScreenIntent: true,
              ongoing: true,
              additionalFlags: Int32List.fromList(<int>[4]),
              timeoutAfter: 45000),
        ),
        payload: 'call:$callId',
      );

  static Future<void> cancelCall(String callId) => plugin.cancel(_id(callId));
}
