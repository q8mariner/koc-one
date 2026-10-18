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

final navKey = GlobalKey<NavigatorState>();

const navy = Color(0xFF0B1220);
const panel = Color(0xFF111A2E);
const sky = Color(0xFF38BDF8);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  await Notify.init();
  Notify.onTap = _routePayload;
  runApp(const KocOneApp());
}

bool _alarmOpen = false;

void openAlarm(Map<String, dynamic> a) {
  final nav = navKey.currentState;
  if (nav == null) return;
  if (_alarmOpen) nav.popUntil((r) => r.settings.name != '/alarm');
  _alarmOpen = true;
  nav.push(MaterialPageRoute(settings: const RouteSettings(name: '/alarm'), builder: (_) => AlarmScreen(alarm: a))).then((_) => _alarmOpen = false);
}

void openCall(Map<String, dynamic> c) {
  navKey.currentState?.push(MaterialPageRoute(builder: (_) => IncomingCallScreen(call: c)));
}

Future<void> _routePayload(String? payload) async {
  if (payload == null || Supabase.instance.client.auth.currentUser == null) return;
  final sb = Supabase.instance.client;
  if (payload.startsWith('alarm:')) {
    final a = await sb.from('alarms').select().eq('id', payload.substring(6)).maybeSingle();
    if (a != null && a['kind'] != 'message' && a['kind'] != 'signal3') openAlarm(a);
  } else if (payload.startsWith('call:')) {
    final c = await sb.from('calls').select().eq('id', payload.substring(5)).maybeSingle();
    if (c != null && c['status'] == 'ringing') openCall(c);
  }
}

class KocOneApp extends StatelessWidget {
  const KocOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: sky, brightness: Brightness.dark, surface: panel);
    return MaterialApp(
      title: 'KOC ONE',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: navy,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: navy, centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: panel),
      ),
      home: const AuthGate(),
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
    LiveService.I.onAllClear = (_) {
      if (_alarmOpen) navKey.currentState?.popUntil((r) => r.settings.name != '/alarm');
    };
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
