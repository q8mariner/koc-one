// Main shell: My ID · HR · Notifications · PM · ORT · Settings. Covered by the lock screen when face unlock is on
// (alarms and calls are pushed above it, so they are never blocked).
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/applock.dart';
import '../ui.dart';
import 'home.dart';
import 'hr.dart';
import 'id.dart';
import 'lock.dart';
import 'log.dart';
import 'pm.dart';
import 'settings.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static int _lastTab = 0; // kept when the language switch rebuilds the app
  int _tab = _lastTab;

  @override
  void initState() {
    super.initState();
    AppLock.I.load();
  }

  @override
  Widget build(BuildContext context) {
    final shell = Scaffold(
      // IndexedStack keeps every page alive: HomeScreen starts the safety service even while another tab is shown.
      body: IndexedStack(index: _tab, children: const [IdScreen(), HrScreen(), LogScreen(), PmScreen(), HomeScreen(), SettingsScreen()]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
        // six tabs: slightly smaller labels so every name fits on one line
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 66,
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 11, height: 1.1, color: s.contains(WidgetState.selected) ? C.navy : C.muted,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500)),
          ),
          child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE3EAF8),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = _lastTab = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.badge_outlined), selectedIcon: const Icon(Icons.badge, color: C.navy), label: tr('هويتي', 'My ID')),
            const NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work, color: C.navy), label: 'HR'),
            NavigationDestination(icon: const Icon(Icons.notifications_none), selectedIcon: const Icon(Icons.notifications, color: C.navy), label: tr('إشعارات', 'Notifications')),
            const NavigationDestination(icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail, color: C.navy), label: 'PM'),
            const NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield, color: C.navy), label: 'ORT'),
            NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings, color: C.navy), label: tr('الإعدادات', 'Settings')),
          ],
        ),
        ),
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: AppLock.I,
      // the shell stays mounted under the lock so the safety service keeps running
      builder: (_, locked, child) => Stack(children: [child!, if (locked) const Positioned.fill(child: LockScreen())]),
      child: shell,
    );
  }
}
