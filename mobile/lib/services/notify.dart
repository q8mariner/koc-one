// Notification channels: one per civil-defence signal (own tone, alarm audio usage, full-screen),
// plus boundary messages and incoming calls.
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n.dart';
import 'native_alarm.dart';

typedef TapHandler = void Function(String? payload);

class Notify {
  static final plugin = FlutterLocalNotificationsPlugin();
  static TapHandler? onTap;

  static const _channels = <String, (String, String?)>{
    'signal1': ('Signal 1 · الإشارة 1', 'signal1'),
    'signal2': ('Signal 2 · الإشارة 2', 'signal2'),
    'signal3': ('Signal 3 · الإشارة 3', 'signal3'),
    'koc_msg': ('Alerts · التنبيهات', null),
    'koc_call': ('ORT calls · مكالمات ORT', null),
  };

  static Future<void> init() async {
    await plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_one')),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // Signal channels (alarm tone, DND bypass) are created natively; only messages & calls here.
    for (final key in ['koc_msg', 'koc_call']) {
      await android?.createNotificationChannel(AndroidNotificationChannel(
        key,
        _channels[key]!.$1,
        description: _channels[key]!.$1,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: key == 'koc_call' ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      ));
    }
    await NativeAlarm.ensureChannels();
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
    final isSignal = kind.startsWith('signal');
    final channel = isSignal ? 'koc_${kind}_${NativeAlarm.channelSuffix}' : 'koc_msg';
    await plugin.show(
      _id(alarmId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          (_channels[kind] ?? _channels['koc_msg']!).$1,
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
        tr('مكالمة من ', 'Call from ') + caller,
        tr('اضغط للرد — مركز 160', 'Tap to answer — 160 centre'),
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
