// Face / fingerprint lock. When enabled, the app asks for the phone's biometrics (or its screen PIN)
// on opening and after 60 s in the background. Alarms and ORT calls always open on top of the lock.
// It also signs in from the login screen: the email + password are kept encrypted on the phone
// (Android Keystore) and are released only after a face / fingerprint check.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final _vault = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _kEmail = 'one.bio.email', _kPass = 'one.bio.pass', _kUid = 'one.bio.uid';
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

  // ── saved sign-in for the login screen ──
  Future<String?> savedEmail() async {
    try {
      return await _vault.read(key: _kEmail);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLogin(String email, String password) async {
    final uid = _uid;
    await _vault.write(key: _kEmail, value: email);
    await _vault.write(key: _kPass, value: password);
    if (uid != null) await _vault.write(key: _kUid, value: uid);
  }

  Future<void> _clearLogin() async {
    try {
      await _vault.delete(key: _kEmail);
      await _vault.delete(key: _kPass);
      await _vault.delete(key: _kUid);
    } catch (_) {}
  }

  /// Login screen: face / fingerprint → saved email + password → sign in. Returns an error text or null.
  Future<String?> signInWithBiometrics() async {
    if (!await authenticate()) return tr('لم يتم التحقق من الوجه أو البصمة.', 'Face / fingerprint not verified.');
    final email = await _vault.read(key: _kEmail), pass = await _vault.read(key: _kPass);
    if (email == null || pass == null) return tr('لا يوجد دخول محفوظ. ادخل بكلمة المرور.', 'No saved sign-in. Use your password.');
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: pass);
      return null;
    } on AuthException {
      await _clearLogin(); // password changed elsewhere
      return tr('تغيّرت كلمة المرور. ادخل بكلمة المرور الجديدة ثم فعّل البصمة من جديد.', 'The password changed. Sign in with the new password, then turn the fingerprint on again.');
    } catch (_) {
      return tr('لا يوجد اتصال بالشبكة.', 'No network connection.');
    }
  }

  /// After a password sign-in: if this account uses face / fingerprint, refresh the saved password.
  Future<void> afterPasswordLogin(String email, String password) async {
    final uid = _uid;
    if (uid == null) return;
    var on = false;
    try {
      on = (await SharedPreferences.getInstance()).getBool('one.biolock.$uid') ?? false;
    } catch (_) {}
    if (on) {
      try { await _saveLogin(email, password); } catch (_) {}
    }
  }

  /// Turn on: confirm the password (it is saved for the login screen) and a face / fingerprint check.
  /// Returns an error text, or null on success.
  Future<String?> setEnabled(bool on, {String? password}) async {
    if (on) {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null || password == null || password.isEmpty) return tr('أدخل كلمة المرور.', 'Enter your password.');
      try {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      } on AuthException {
        return tr('كلمة المرور غير صحيحة.', 'Wrong password.');
      } catch (_) {
        return tr('لا يوجد اتصال بالشبكة.', 'No network connection.');
      }
      if (!await authenticate()) return tr('لم يتم التحقق من الوجه أو البصمة — لم يُفعَّل.', 'Face / fingerprint not verified — not turned on.');
      try {
        await _saveLogin(email, password);
      } catch (_) {
        return tr('تعذّر الحفظ الآمن على هذا الهاتف.', 'Couldn’t store it securely on this phone.');
      }
    } else {
      await _clearLogin();
    }
    enabled = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
    if (!on) value = false;
    return null;
  }

  /// Saved password needs replacing after a password change in Settings.
  Future<void> passwordChanged(String password) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (enabled && email != null) {
      try { await _saveLogin(email, password); } catch (_) {}
    }
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
