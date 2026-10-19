// ONE ORT — the ORT dashboard as an Android app. The pages are the web dashboard itself (same look,
// always up to date); this shell adds what a website can't: face / fingerprint sign-in and lock,
// Android permissions for calls / location / photos, and notifications while the app is in the background.
// The page talks to it through window.OneNative (see native() in dashboard/app.js).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const dashboardUrl = 'https://q8mariner.github.io/koc-one/?app=1';
const navy = Color(0xFF2B4C9B), navyD = Color(0xFF1F3A7A), yellow = Color(0xFFF5C518), bg = Color(0xFFF3F6FB);

final notes = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: navyD, statusBarIconBrightness: Brightness.light, systemNavigationBarColor: Colors.white, systemNavigationBarIconBrightness: Brightness.dark));
  // never let notifications setup stop the console from opening
  try {
    await notes.initialize(const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_one')));
    await notes.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
        const AndroidNotificationChannel('ort_events', 'ORT events · أحداث ORT', importance: Importance.max, playSound: true, enableVibration: true));
  } catch (e) {
    debugPrint('notifications unavailable: $e');
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, title: 'ONE ORT', home: Console()));
}

class Console extends StatefulWidget {
  const Console({super.key});
  @override
  State<Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<Console> with WidgetsBindingObserver {
  late final WebViewController c;
  final _auth = LocalAuthentication();
  final _vault = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  bool _loading = true, _error = false, _locked = false, _authBusy = false, _foreground = true, _lockFailed = false;
  bool _bioEnabled = false;
  DateTime? _pausedAt;
  int _noteId = 0;
  bool _ar = true; // texts of this shell follow the page language (sent by the page)

  String t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = WebViewController(onPermissionRequest: (req) async {
      if (req.types.contains(WebViewPermissionResourceType.microphone)) await Permission.microphone.request();
      if (req.types.contains(WebViewPermissionResourceType.camera)) await Permission.camera.request();
      await req.grant();
    });
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bg)
      ..addJavaScriptChannel('OneNative', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() { _loading = true; _error = false; }),
        onPageFinished: (_) => setState(() => _loading = false),
        // only the page itself failing means "offline" (a map tile or font failing does not)
        onWebResourceError: (e) { if (e.isForMainFrame == true) setState(() { _error = true; _loading = false; }); },
      ));
    final p = c.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false); // call audio plays without a tap
      p.setGeolocationPermissionsPromptCallbacks(onShowPrompt: (_) async {
        final ok = (await Permission.location.request()).isGranted;
        return GeolocationPermissionsResponse(allow: ok, retain: true);
      });
      p.setOnShowFileSelector(_pickFile); // employee ID photo upload
    }
    c.loadRequest(Uri.parse(dashboardUrl));
    // the splash never stays more than 12 s even if the page never reports "finished"
    Future.delayed(const Duration(seconds: 12), () { if (mounted && _loading) setState(() => _loading = false); });
    _start();
  }

  Future<void> _start() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _bioEnabled = sp.getBool('bio') ?? false;
      _ar = (sp.getString('lang') ?? 'ar') == 'ar';
    } catch (_) {}
    if (_bioEnabled) {
      setState(() => _locked = true);
      _unlock();
    }
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed;
    if (_authBusy) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (_bioEnabled && at != null && DateTime.now().difference(at).inSeconds >= 60) {
        setState(() { _locked = true; _lockFailed = false; });
        _unlock();
      }
      notes.cancelAll();
    }
  }

  // ── biometrics ──
  Future<bool> _bioAvailable() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.canCheckBiometrics || (await _auth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate() async {
    if (_authBusy) return false;
    _authBusy = true;
    try {
      return await _auth.authenticate(
        localizedReason: t('افتح ONE ORT بالوجه أو البصمة', 'Unlock ONE ORT with your face or fingerprint'),
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    } finally {
      _authBusy = false;
      _pausedAt = null;
    }
  }

  Future<void> _unlock() async {
    final ok = await _authenticate();
    if (mounted) setState(() { _locked = !ok; _lockFailed = !ok; });
  }

  Future<void> _setBio(bool on) async {
    _bioEnabled = on;
    (await SharedPreferences.getInstance()).setBool('bio', on);
  }

  // ── permissions ──
  Future<Map<String, bool>> _perms() async => {
        'notif': await Permission.notification.isGranted,
        'mic': await Permission.microphone.isGranted,
        'loc': await Permission.location.isGranted,
        'cam': await Permission.camera.isGranted,
      };

  Future<void> _requestPerm(String name) async {
    final p = {'notif': Permission.notification, 'mic': Permission.microphone, 'loc': Permission.location, 'cam': Permission.camera}[name];
    if (p == null) return;
    final st = await p.request();
    if (!st.isGranted) await openAppSettings();
  }

  // ── <input type=file> in the page ──
  Future<List<String>> _pickFile(FileSelectorParams params) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera, color: navy), title: Text(t('التقاط صورة', 'Take a photo')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library, color: navy), title: Text(t('اختيار من الصور', 'Choose from photos')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return [];
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 88);
      return x == null ? [] : [Uri.file(x.path).toString()];
    } catch (_) {
      return [];
    }
  }

  // ── messages from the page: {id, cmd, args} → window.__oneReply(id, result) ──
  Future<void> _onMessage(JavaScriptMessage m) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(m.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final args = (msg['args'] as Map?)?.cast<String, dynamic>() ?? {};
    Object? res;
    try {
      res = await _handle(msg['cmd'] as String? ?? '', args);
    } catch (e) {
      res = {'ok': false, 'error': '$e'};
    }
    await c.runJavaScript('window.__oneReply && window.__oneReply(${jsonEncode(msg['id'])}, ${jsonEncode(res)})');
  }

  Future<Object?> _handle(String cmd, Map<String, dynamic> a) async {
    switch (cmd) {
      case 'info':
        if (a['lang'] is String) _ar = a['lang'] == 'ar';
        return {'app': 'ort', 'bio': await _bioAvailable(), 'bioSaved': _bioEnabled ? await _vault.read(key: 'email') : null, 'bioEnabled': _bioEnabled, 'perms': await _perms()};
      case 'lang':
        _ar = a['lang'] == 'ar';
        (await SharedPreferences.getInstance()).setString('lang', _ar ? 'ar' : 'en');
        return {'ok': true};
      case 'perms':
        return await _perms();
      case 'permRequest':
        await _requestPerm('${a['name']}');
        return await _perms();
      case 'bioEnable':
        if (!await _authenticate()) return {'ok': false, 'error': t('لم يتم التحقق من الوجه أو البصمة — لم يُفعَّل.', 'Face / fingerprint not verified — not turned on.')};
        await _vault.write(key: 'email', value: '${a['email']}');
        await _vault.write(key: 'pass', value: '${a['password']}');
        await _setBio(true);
        return {'ok': true};
      case 'bioDisable':
        await _vault.deleteAll();
        await _setBio(false);
        return {'ok': true};
      case 'bioLogin':
        if (!_bioEnabled) return {'error': t('الدخول بالبصمة غير مفعّل.', 'Fingerprint sign-in is off.')};
        if (!await _authenticate()) return {'error': t('لم يتم التحقق من الوجه أو البصمة.', 'Face / fingerprint not verified.')};
        return {'email': await _vault.read(key: 'email'), 'password': await _vault.read(key: 'pass')};
      case 'passwordLogin':
      case 'passwordChanged':
        if (_bioEnabled) {
          await _vault.write(key: 'email', value: '${a['email']}');
          await _vault.write(key: 'pass', value: '${a['password']}');
        }
        return {'ok': true};
      case 'notify':
        if (!_foreground) {
          await notes.show(++_noteId, '${a['title']}', '${a['body']}', const NotificationDetails(
            android: AndroidNotificationDetails('ort_events', 'ORT events · أحداث ORT', importance: Importance.max, priority: Priority.max, icon: '@drawable/ic_stat_one', color: navy),
          ));
        }
        return {'ok': true};
    }
    return null;
  }

  Future<bool> _back() async {
    if (await c.canGoBack()) {
      await c.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _back()) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: navyD,
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            Positioned.fill(child: Container(color: bg, child: WebViewWidget(controller: c))),
            if (_loading && !_error) const Positioned.fill(child: _Splash()),
            if (_error) Positioned.fill(child: _Offline(text: t('تعذّر الاتصال. تحقق من الشبكة.', 'Can’t connect. Check the network.'), retry: t('إعادة المحاولة', 'Retry'), onRetry: () => c.reload())),
            if (_locked) Positioned.fill(child: _Lock(
              title: t('التطبيق مقفل', 'App locked'),
              button: t('فتح بالوجه أو البصمة', 'Unlock with face or fingerprint'),
              failed: _lockFailed ? t('لم يتم التحقق. حاول مرة أخرى.', 'Not verified. Try again.') : null,
              onUnlock: _unlock,
            )),
          ]),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final double size;
  const _Wordmark({this.size = 40});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '/', style: TextStyle(color: yellow, fontSize: size, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
          TextSpan(text: 'ONE', style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1)),
        ])),
      );
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Container(
        color: navyD,
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Wordmark(size: 44),
            SizedBox(height: 6),
            Text('ORT · ECC-160', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
            SizedBox(height: 26),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: yellow, strokeWidth: 3)),
          ]),
        ),
      );
}

class _Offline extends StatelessWidget {
  final String text, retry;
  final VoidCallback onRetry;
  const _Offline({required this.text, required this.retry, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        color: navyD,
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _Wordmark(),
            const SizedBox(height: 20),
            const Icon(Icons.wifi_off, color: Colors.white70, size: 46),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 18),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: navyD), onPressed: onRetry, child: Text(retry)),
          ]),
        ),
      );
}

class _Lock extends StatelessWidget {
  final String title, button;
  final String? failed;
  final VoidCallback onUnlock;
  const _Lock({required this.title, required this.button, required this.failed, required this.onUnlock});
  @override
  Widget build(BuildContext context) => Material(
        color: navyD,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _Wordmark(),
              const SizedBox(height: 6),
              const Text('ORT · ECC-160', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 28),
              const Icon(Icons.fingerprint, color: Colors.white, size: 64),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              if (failed != null) ...[
                const SizedBox(height: 8),
                Text(failed!, style: const TextStyle(color: yellow, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: navyD, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(button, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      );
}
