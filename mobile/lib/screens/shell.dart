// Main shell: bottom navigation as in the proposal — My ID · Area log · Now.
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../ui.dart';
import 'home.dart';
import 'id.dart';
import 'log.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every page alive: HomeScreen starts the safety service even while the ID is shown.
      body: IndexedStack(index: _tab, children: const [IdScreen(), LogScreen(), HomeScreen()]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE3EAF8),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.badge_outlined), selectedIcon: const Icon(Icons.badge, color: C.navy), label: tr('هويتي', 'My ID')),
            NavigationDestination(icon: const Icon(Icons.history), selectedIcon: const Icon(Icons.history, color: C.navy), label: tr('سجل المناطق', 'Area log')),
            NavigationDestination(icon: const Icon(Icons.notifications_none), selectedIcon: const Icon(Icons.notifications, color: C.navy), label: tr('الآن', 'Now')),
          ],
        ),
      ),
    );
  }
}
