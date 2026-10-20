import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MarineApp());
}

class MarineApp extends StatelessWidget {
  const MarineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Marine Operations',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
          scaffoldBackgroundColor: kBlue,
          useMaterial3: true,
        ),
        home: const Shell(),
      );
}

enum Section { home, weather, operations, contacts, news, duty }

const sectionIcons = {
  Section.home: Icons.home_rounded,
  Section.weather: Icons.cloud_rounded,
  Section.operations: Icons.view_stream_rounded,
  Section.contacts: Icons.support_agent_rounded,
  Section.news: Icons.tv_rounded,
  Section.duty: Icons.calendar_month_rounded,
};

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Section current = Section.home;
  bool menuOpen = false;
  int refreshTick = 0;

  void go(Section s) => setState(() {
        current = s;
        menuOpen = false;
        refreshTick++;
      });

  Widget _page() {
    switch (current) {
      case Section.home:
        return HomePage(key: ValueKey('h$refreshTick'), go: go);
      case Section.weather:
        return WeatherPage(key: ValueKey('w$refreshTick'));
      case Section.operations:
        return OperationsPage(key: ValueKey('o$refreshTick'));
      case Section.contacts:
        return ContactsPage(key: ValueKey('c$refreshTick'));
      case Section.news:
        return NewsPage(key: ValueKey('n$refreshTick'));
      case Section.duty:
        return DutyPage(key: ValueKey('d$refreshTick'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return PopScope(
      canPop: current == Section.home && !menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (menuOpen) {
          setState(() => menuOpen = false);
        } else {
          go(Section.home);
        }
      },
      child: Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: Background()),
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _page()),
          ),
          if (menuOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => menuOpen = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: const Color(0x22000040)),
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 16 + bottomPad,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, alignment: Alignment.bottomCenter, child: c),
              child: menuOpen ? _menu() : _fab(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fab() => GestureDetector(
        key: const ValueKey('fab'),
        onTap: () => setState(() => menuOpen = true),
        child: Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFE9EDF5),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Icon(sectionIcons[current], color: kBlue, size: 38),
        ),
      );

  Widget _menu() {
    Widget item(Section s) => InkWell(
          onTap: () => go(s),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
            child: s == Section.contacts
                ? const _Badge24()
                : Icon(sectionIcons[s], color: current == s ? kBlueDeep : kBlue, size: 38),
          ),
        );
    return Container(
      key: const ValueKey('menu'),
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF5),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ClipOval(child: Image.asset('assets/logo.png', width: 52, height: 52, fit: BoxFit.cover)),
        ),
        for (final s in Section.values) item(s),
        InkWell(
          onTap: () => setState(() => menuOpen = false),
          customBorder: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.close_rounded, color: kBlue, size: 40),
          ),
        ),
      ]),
    );
  }
}

class _Badge24 extends StatelessWidget {
  const _Badge24();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: Stack(children: [
          const Positioned(left: 0, bottom: 0, child: Icon(Icons.phone_in_talk_rounded, color: kBlue, size: 30)),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: kBlue, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE9EDF5), width: 2)),
              alignment: Alignment.center,
              child: const Text('24',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      );
}

class Background extends StatelessWidget {
  const Background({super.key});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        Image.asset('assets/bg.jpg', fit: BoxFit.cover),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC1F5FFF), Color(0xE61F5FFF), Color(0xF21A55F0)],
            ),
          ),
        ),
      ]);
}
