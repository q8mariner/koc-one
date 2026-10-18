import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui.dart';

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

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
    } on AuthException {
      setState(() => _err = 'تعذّر الدخول. تحقق من البريد وكلمة المرور المستلمة من فريق ORT.');
    } catch (_) {
      setState(() => _err = 'لا يوجد اتصال بالشبكة.');
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
                const Wordmark(size: 44, color: Colors.white),
                const SizedBox(height: 8),
                const Text('سلامتك أولًا — الإنذار والحصر وبلاغات 160 في تطبيق واحد',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Align(alignment: AlignmentDirectional.centerStart, child: Tag('تسجيل الدخول')),
                    const SizedBox(height: 8),
                    const Text('بالحساب الذي أصدره لك فريق ORT', style: TextStyle(color: C.muted)),
                    const SizedBox(height: 16),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
                    const SizedBox(height: 12),
                    TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة المرور'), onSubmitted: (_) => _login()),
                    if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: C.bad))),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _busy ? null : _login, style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)), child: Text(_busy ? 'جارٍ الدخول…' : 'دخول')),
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
