// Settings: language, password, face / fingerprint unlock, sign out.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/applock.dart';
import '../services/live.dart';
import '../ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cur = TextEditingController(), _new = TextEditingController(), _new2 = TextEditingController();
  bool _pwOpen = false, _pwBusy = false, _bioAvail = false, _bioBusy = false, _hasSaved = false;
  String? _pwMsg;
  bool _pwOk = false;

  @override
  void initState() {
    super.initState();
    AppLock.I.available().then((v) { if (mounted) setState(() => _bioAvail = v); });
    AppLock.I.savedEmail().then((e) { if (mounted) setState(() => _hasSaved = e != null); });
  }

  @override
  void dispose() {
    _cur.dispose(); _new.dispose(); _new2.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _changePassword() async {
    final sb = Supabase.instance.client;
    final email = sb.auth.currentUser?.email;
    setState(() { _pwMsg = null; _pwOk = false; });
    if (_new.text.length < 8) return setState(() => _pwMsg = tr('كلمة المرور الجديدة 8 أحرف على الأقل.', 'The new password needs at least 8 characters.'));
    if (_new.text != _new2.text) return setState(() => _pwMsg = tr('كلمتا المرور غير متطابقتين.', 'The passwords don’t match.'));
    if (_new.text == _cur.text) return setState(() => _pwMsg = tr('اختر كلمة مرور مختلفة عن الحالية.', 'Choose a password different from the current one.'));
    setState(() => _pwBusy = true);
    try {
      // confirm the current password first
      await sb.auth.signInWithPassword(email: email!, password: _cur.text);
    } catch (_) {
      setState(() { _pwBusy = false; _pwMsg = tr('كلمة المرور الحالية غير صحيحة.', 'The current password is wrong.'); });
      return;
    }
    try {
      await sb.auth.updateUser(UserAttributes(password: _new.text));
      await AppLock.I.passwordChanged(_new.text);
      _cur.clear(); _new.clear(); _new2.clear();
      setState(() { _pwBusy = false; _pwOk = true; _pwOpen = false; _pwMsg = tr('تم تغيير كلمة المرور.', 'Password changed.'); });
    } catch (e) {
      setState(() { _pwBusy = false; _pwMsg = tr('تعذّر التغيير: ', 'Couldn’t change it: ') + (e is AuthException ? e.message : '$e'); });
    }
  }

  Future<void> _toggleBio(bool on) async {
    String? password;
    if (on) {
      final ctl = TextEditingController();
      password = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('تفعيل الدخول بالوجه أو البصمة', 'Turn on face / fingerprint sign-in')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('أدخل كلمة المرور مرة واحدة. تُحفظ مشفّرة على هذا الهاتف ولا تُستخدم إلا بعد التحقق من وجهك أو بصمتك.', 'Enter your password once. It is stored encrypted on this phone and used only after your face / fingerprint is verified.'), style: const TextStyle(color: C.muted)),
            const SizedBox(height: 12),
            TextField(controller: ctl, obscureText: true, autofocus: true, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: tr('كلمة المرور', 'Password'), border: const OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(tr('متابعة', 'Continue'))),
          ],
        ),
      );
      if (password == null) return;
    }
    setState(() => _bioBusy = true);
    final err = await AppLock.I.setEnabled(on, password: password);
    if (!mounted) return;
    setState(() => _bioBusy = false);
    if (err == null) _hasSaved = on;
    if (err != null) _snack(err);
    else _snack(on ? tr('فُعّل: ادخل بالوجه أو البصمة من صفحة تسجيل الدخول، ويُطلب أيضًا عند فتح التطبيق.', 'On: sign in with face / fingerprint from the login screen; it is also asked when the app opens.') : tr('أُلغي الدخول بالوجه والبصمة.', 'Face / fingerprint sign-in turned off.'));
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('تسجيل الخروج؟', 'Sign out?')),
        content: Text(tr('لن تصلك الإنذارات على هذا الهاتف حتى تسجّل الدخول مرة أخرى.', 'You won’t receive alarms on this phone until you sign in again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.bad), onPressed: () => Navigator.pop(c, true), child: Text(tr('خروج', 'Sign out'))),
        ],
      ),
    );
    if (ok != true) return;
    await LiveService.I.stop();
    AppLock.I.reset();
    await Supabase.instance.client.auth.signOut();
  }

  Widget _pw(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, obscureText: true, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(tr('الإعدادات', 'Settings'), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        // language
        SectionTitle(tr('اللغة', 'Language')),
        OneCard(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ar', label: Text('العربية')), ButtonSegment(value: 'en', label: Text('English'))],
            selected: {Lang.I.value},
            showSelectedIcon: false,
            onSelectionChanged: (v) { if (v.first != Lang.I.value) Lang.I.toggle(); },
          ),
        ),

        // password
        SectionTitle(tr('كلمة المرور', 'Password')),
        OneCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.lock_outline, color: C.navy),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('تغيير كلمة المرور', 'Change password'), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(email, style: const TextStyle(color: C.muted, fontSize: 12)),
              ])),
              TextButton(onPressed: () => setState(() { _pwOpen = !_pwOpen; _pwMsg = null; }), child: Text(_pwOpen ? tr('إلغاء', 'Cancel') : tr('تغيير', 'Change'))),
            ]),
            if (_pwOpen) ...[
              const SizedBox(height: 12),
              _pw(_cur, tr('كلمة المرور الحالية', 'Current password')),
              _pw(_new, tr('كلمة المرور الجديدة (8 أحرف على الأقل)', 'New password (8+ characters)')),
              _pw(_new2, tr('تأكيد كلمة المرور الجديدة', 'Confirm new password')),
              FilledButton(onPressed: _pwBusy ? null : _changePassword, child: Text(_pwBusy ? tr('جارٍ الحفظ…', 'Saving…') : tr('حفظ كلمة المرور', 'Save password'))),
            ],
            if (_pwMsg != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_pwMsg!, style: TextStyle(color: _pwOk ? C.ok : C.bad, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        // biometrics
        SectionTitle(tr('الدخول بالوجه', 'Face unlock')),
        OneCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SwitchListTile(
            value: AppLock.I.enabled && _hasSaved, // turned on before the login button existed → turn on again
            onChanged: (!_bioAvail || _bioBusy) ? null : _toggleBio,
            secondary: const Icon(Icons.face_retouching_natural, color: C.navy),
            title: Text(tr('الدخول بالوجه أو البصمة', 'Sign in with face or fingerprint'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_bioAvail
                ? tr('زر الدخول بالوجه أو البصمة في صفحة تسجيل الدخول، ويُطلب أيضًا عند فتح التطبيق وبعد دقيقة في الخلفية. الإنذارات والمكالمات تظهر دائمًا دون قفل.', 'A face / fingerprint button on the login screen; also asked when the app opens and after a minute in the background. Alarms and calls always show without the lock.')
                : tr('هذا الهاتف لا يدعم الوجه أو البصمة، أو لم تُسجَّل بصمة/وجه في إعدادات الهاتف.', 'This phone has no face / fingerprint set up.')),
          ),
        ),

        // sign out
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: C.bad, side: const BorderSide(color: C.bad), padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: Text(tr('تسجيل الخروج من التطبيق', 'Sign out of the app'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}
