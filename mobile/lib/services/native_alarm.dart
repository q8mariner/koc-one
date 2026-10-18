// Bridge to the native Android alarm layer (tool/MainActivity.kt → android MainActivity).
import 'package:flutter/services.dart';

class NativeAlarm {
  static const _ch = MethodChannel('koc/alarm');
  static String channelSuffix = 'std';

  static Future<T?> _call<T>(String m, [Map<String, dynamic>? args]) async {
    try {
      return await _ch.invokeMethod<T>(m, args);
    } catch (_) {
      return null;
    }
  }

  /// {dnd, overlay, fullScreen}
  static Future<Map<String, bool>> status() async {
    final r = await _call<Map>('status');
    return {
      'dnd': r?['dnd'] == true,
      'overlay': r?['overlay'] == true,
      'fullScreen': r?['fullScreen'] != false,
    };
  }

  static Future<bool> allGranted() async => !(await status()).values.contains(false);

  static Future<void> ensureChannels() async => channelSuffix = await _call<String>('ensureChannels') ?? 'std';
  static Future<void> openDnd() => _call('openDnd');
  static Future<void> openOverlay() => _call('openOverlay');
  static Future<void> openFullScreen() => _call('openFullScreen');
  static Future<void> start(String kind, {bool loop = true}) => _call('start', {'kind': kind, 'loop': loop});
  static Future<void> stop() => _call('stop');
  static Future<void> bringToFront() => _call('bringToFront');
}
