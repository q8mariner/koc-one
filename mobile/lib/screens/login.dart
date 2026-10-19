import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/applock.dart';
import '../ui.dart';
import '../i18n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;
  String? _bioEmail; // saved sign-in for face / fingerprint

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    final email = await AppLock.I.savedEmail();
    if (email == null || !await AppLock.I.available()) return;
    if (mounted) setState(() { _bioEmail = email; if (_email.text.isEmpty) _email.text = email; });
  }

  Future<void> _bioLogin() async {
    setState(() { _busy = true; _err = null; });
    final err = await AppLock.I.signInWithBiometrics();
    if (!mounted) return;
    setState(() { _busy = false; _err = err; });
    if (err != null) _checkBio();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
      await AppLock.I.afterPasswordLogin(_email.text.trim(), _pass.text);
    } on AuthException {
      setState(() => _err = tr('تعذّر الدخول. تحقق من البريد وكلمة المرور المستلمة من فريق ORT.', 'Sign-in failed. Check the email and password you received from ORT.'));
    } catch (_) {
      setState(() => _err = tr('لا يوجد اتصال بالشبكة.', 'No network connection.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.navy,
      body: Stack(children: [
        const Positioned.fill(child: Stripes()),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Wordmark(size: 44, color: Colors.white),
                  const Spacer(),
                  TextButton(
                    onPressed: Lang.I.toggle,
                    style: TextButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                    child: Text(Lang.I.isEn ? 'العربية' : 'English'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(tr('سلامتك أولًا — الإنذار والحصر وبلاغات 160 في تطبيق واحد', 'Your safety first — alarms, muster and 160 reports in one app'),
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(alignment: AlignmentDirectional.centerStart, child: Tag(tr('تسجيل الدخول', 'Sign in'))),
                    const SizedBox(height: 8),
                    Text(tr('بالحساب الذي أصدره لك فريق ORT', 'With the account ORT issued to you'), style: const TextStyle(color: C.muted)),
                    const SizedBox(height: 16),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: tr('البريد الإلكتروني', 'Email'))),
                    const SizedBox(height: 12),
                    TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: tr('كلمة المرور', 'Password')), onSubmitted: (_) => _login()),
                    if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: C.bad))),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _busy ? null : _login, style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)), child: Text(_busy ? tr('جارٍ الدخول…', 'Signing in…') : tr('دخول', 'Sign in'))),
                    if (_bioEmail != null) ...[
                      const SizedBox(height: 14),
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(tr('أو', 'or'), style: const TextStyle(color: C.muted))),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _bioLogin,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14), foregroundColor: C.navy, side: const BorderSide(color: C.navy, width: 1.5)),
                        icon: const Icon(Icons.fingerprint, size: 26),
                        label: Text(tr('الدخول بالوجه أو البصمة', 'Sign in with face or fingerprint'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 4),
                      Text(_bioEmail!, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(color: C.muted, fontSize: 12)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
