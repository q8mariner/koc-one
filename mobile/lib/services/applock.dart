// Face / fingerprint lock. When enabled, the app asks for the phone's biometrics (or its screen PIN)
// on opening and after 60 s in the background. Alarms and ORT calls always open on top of the lock.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';

class AppLock extends ValueNotifier<bool> with WidgetsBindingObserver {
  static final AppLock I = AppLock._();
  AppLock._() : super(false) {
    WidgetsBinding.instance.addObserver(this);
  }

  final _auth = LocalAuthentication();
  bool enabled = false;
  bool _busy = false;
  DateTime? _pausedAt;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  String get _key => 'one.biolock.$_uid';

  /// True when the app was opened with a saved session (not right after typing the password).
  bool coldSession = false;
  String? _loadedFor;

  /// Read the setting for the signed-in user once; lock right away if the app was just opened.
  Future<void> load() async {
    final uid = _uid;
    if (uid == null || uid == _loadedFor) return;
    _loadedFor = uid;
    enabled = false;
    try {
      enabled = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {}
    value = enabled && coldSession;
    coldSession = false;
  }

  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.canCheckBiometrics || (await _auth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Ask for face / fingerprint (the phone's PIN is accepted as a fallback).
  Future<bool> authenticate() async {
    if (_busy) return false;
    _busy = true;
    try {
      return await _auth.authenticate(
        localizedReason: tr('افتح ONE بالوجه أو البصمة', 'Unlock ONE with your face or fingerprint'),
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      _pausedAt = null; // the system prompt itself pauses the app
    }
  }

  Future<bool> unlock() async {
    final ok = await authenticate();
    if (ok) value = false;
    return ok;
  }

  Future<bool> setEnabled(bool on) async {
    if (on && !await authenticate()) return false; // prove it works before turning it on
    enabled = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
    if (!on) value = false;
    return true;
  }

  void reset() {
    enabled = false;
    _loadedFor = null;
    value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled || _busy) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && DateTime.now().difference(at).inSeconds >= 60) value = true;
    }
  }
}
