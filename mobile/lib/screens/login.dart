import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  color: const Color(0xFF38BDF8),
                  child: const Text('KOC', style: TextStyle(color: Color(0xFF04263A), fontWeight: FontWeight.w800, fontSize: 22)),
                ),
                const SizedBox(width: 6),
                const Text('ONE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 2)),
              ]),
              const SizedBox(height: 12),
              const Text('استدامة شركة نفط الكويت تبدأ من سلامة كوادرها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('سجّل الدخول بالحساب الذي أصدره لك فريق ORT', style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 28),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
              const SizedBox(height: 12),
              TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة المرور'), onSubmitted: (_) => _login()),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _login, style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)), child: Text(_busy ? 'جارٍ الدخول…' : 'دخول')),
            ]),
          ),
        ),
      ),
    );
  }
}
