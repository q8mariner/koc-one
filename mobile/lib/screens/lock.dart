// Lock screen shown over the app (not over alarms or calls) when face / fingerprint unlock is on.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/applock.dart';
import '../services/live.dart';
import '../ui.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    final ok = await AppLock.I.unlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  Future<void> _signOut() async {
    await LiveService.I.stop();
    AppLock.I.reset();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final name = LiveService.I.me?['full_name'] as String?;
    return Scaffold(
      backgroundColor: C.navy,
      body: Stack(children: [
        const Positioned.fill(child: Opacity(opacity: .25, child: Stripes())),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Wordmark(size: 40, color: Colors.white),
                const SizedBox(height: 28),
                const Icon(Icons.face_retouching_natural, color: Colors.white, size: 64),
                const SizedBox(height: 14),
                if (name != null) Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(tr('التطبيق مقفل — الإنذارات والمكالمات تصلك دائمًا', 'App locked — alarms and calls still reach you'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                if (_failed) ...[
                  const SizedBox(height: 10),
                  Text(tr('لم يتم التحقق. حاول مرة أخرى.', 'Not verified. Try again.'), style: const TextStyle(color: C.yellow, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.yellow, foregroundColor: C.navyD, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _try,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(tr('فتح بالوجه أو البصمة', 'Unlock with face or fingerprint'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                TextButton(onPressed: _signOut, child: Text(tr('تسجيل الخروج والدخول بكلمة المرور', 'Sign out and use the password'), style: const TextStyle(color: Colors.white))),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
