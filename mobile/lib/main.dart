import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/alarm.dart';
import 'screens/call.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'services/live.dart';
import 'services/notify.dart';
import 'ui.dart';
import 'i18n.dart';

final navKey = GlobalKey<NavigatorState>();


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  await Lang.I.load();
  await Notify.init();
  Notify.onTap = _routePayload;
  runApp(const KocOneApp());
}

String? _openAlarmId; // alarm currently shown full-screen

void openAlarm(Map<String, dynamic> a) {
  final nav = navKey.currentState;
  if (nav == null) return;
  final id = a['id'] as String;
  if (_openAlarmId == id) return; // already showing
  if (_openAlarmId != null) nav.popUntil((r) => r.settings.name != '/alarm');
  _openAlarmId = id;
  nav.push(MaterialPageRoute(settings: const RouteSettings(name: '/alarm'), builder: (_) => AlarmScreen(alarm: a))).then((_) {
    if (_openAlarmId == id) _openAlarmId = null;
  });
}

/// Close the full-screen alarm only if it is showing this (now closed) alarm.
void closeAlarmScreen(String alarmId) {
  if (_openAlarmId == alarmId) navKey.currentState?.popUntil((r) => r.settings.name != '/alarm');
}

void openCall(Map<String, dynamic> c) {
  navKey.currentState?.push(MaterialPageRoute(builder: (_) => IncomingCallScreen(call: c)));
}

Future<void> _routePayload(String? payload) async {
  if (payload == null || Supabase.instance.client.auth.currentUser == null) return;
  final sb = Supabase.instance.client;
  if (payload.startsWith('alarm:')) {
    final a = await sb.from('alarms').select().eq('id', payload.substring(6)).maybeSingle();
    if (a != null && a['kind'] != 'message') openAlarm(a);
  } else if (payload.startsWith('call:')) {
    final c = await sb.from('calls').select().eq('id', payload.substring(5)).maybeSingle();
    if (c != null && c['status'] == 'ringing') openCall(c);
  }
}

class KocOneApp extends StatelessWidget {
  const KocOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Lang.I,
      builder: (context, lang, _) => MaterialApp(
      title: 'ONE',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: oneTheme(),
      home: AuthGate(key: ValueKey(lang)),
    ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    LiveService.I.onAlarm = openAlarm;
    LiveService.I.onIncomingCall = openCall;
    LiveService.I.onAllClear = closeAlarmScreen;
    Notify.launchPayload().then(_routePayload);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snap) {
        final session = Supabase.instance.client.auth.currentSession;
        return session == null ? const LoginScreen() : const HomeScreen();
      },
    );
  }
}
