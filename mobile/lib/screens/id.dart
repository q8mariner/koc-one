// "My digital ID" — designed after the proposal (Annex B). All identity data and the official photo are
// managed by ORT from the dashboard; the employee can only view them. The QR code is a signed token that
// refreshes every 30 seconds, so a screenshot is useless.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/live.dart';
import '../ui.dart';

class IdScreen extends StatefulWidget {
  const IdScreen({super.key});
  @override
  State<IdScreen> createState() => _IdScreenState();
}

class _IdScreenState extends State<IdScreen> {
  final live = LiveService.I;
  String? _token;
  int _left = 0;
  bool _offline = false;
  Timer? _tick;
  Uint8List? _photo;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    live.addListener(_onLive);
    _refreshToken();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left <= 0) _refreshToken();
    });
    _loadPhoto();
  }

  @override
  void dispose() {
    _tick?.cancel();
    live.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    if (!mounted) return;
    if (live.me?['photo_path'] != _photoPath) _loadPhoto();
    setState(() {});
  }

  bool _fetching = false;
  Future<void> _refreshToken() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final r = await Supabase.instance.client.functions.invoke('id-token');
      final d = r.data;
      if (d is Map && d['token'] != null) {
        setState(() {
          _token = d['token'] as String;
          _left = (d['expires_in'] as num?)?.toInt() ?? 30;
          _offline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _offline = true; _left = 10; }); // retry in 10 s
    } finally {
      _fetching = false;
    }
  }

  Future<void> _loadPhoto() async {
    final path = live.me?['photo_path'] as String?;
    _photoPath = path;
    if (path == null) {
      if (mounted) setState(() => _photo = null);
      return;
    }
    try {
      final bytes = await Supabase.instance.client.storage.from('avatars').download(path);
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {}
  }

  static String _mask(String? civil) {
    if (civil == null || civil.length < 4) return civil ?? '—';
    return '${civil[0]}${'•' * (civil.length - 3)}${civil.substring(civil.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final me = live.me ?? const {};
    final email = Supabase.instance.client.auth.currentUser?.email ?? '—';
    final active = me['active'] != false;
    final where = live.areas.sector(live.where.sectorId)?['name'];
    final sub = [me['department'], where].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        // navy header band
        Container(height: 210, color: C.navy, child: const Opacity(opacity: .25, child: Stripes())),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              Text(tr('هويتي الرقمية', 'My digital ID'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              const Wordmark(size: 22, color: Colors.white),
            ]),
            const SizedBox(height: 18),
            // ID card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x22172C5E), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // official photo (uploaded by ORT)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 92,
                        height: 108,
                        color: const Color(0xFFDCE6F7),
                        child: _photo != null
                            ? Image.memory(_photo!, fit: BoxFit.cover)
                            : const Icon(Icons.person_outline, size: 54, color: C.navy),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(me['full_name'] ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: C.navy, height: 1.3)),
                        if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: C.muted, fontSize: 12.5)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _pill(active ? tr('● موظف فعّال', '● Active employee') : tr('● موقوف', '● Inactive'),
                              active ? const Color(0xFFE6F4EC) : const Color(0xFFFBDADA), active ? const Color(0xFF1F7A45) : C.bad),
                          if (me['blood_type'] != null) _pill('${me['blood_type']}', const Color(0xFFFBDADA), C.bad),
                        ]),
                      ]),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: C.line),
                _row(tr('الرقم الوظيفي', 'Employee no.'), me['employee_no'], mono: true),
                _row(tr('المسمى الوظيفي', 'Job title'), me['job_title']),
                _row(tr('رقم الهاتف', 'Phone'), me['phone'], ltr: true),
                _row(tr('البريد الإلكتروني', 'Email'), email, ltr: true),
                _row(tr('الرقم المدني', 'Civil ID'), _mask(me['civil_id'] as String?), ltr: true, last: true),
                // dynamic QR
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
                      child: _token == null
                          ? const SizedBox(width: 160, height: 160, child: Center(child: CircularProgressIndicator()))
                          : QrImageView(data: _token!, size: 160, padding: EdgeInsets.zero, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: C.navy), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: C.fg)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _offline
                          ? tr('غير متصل — يتعذّر تجديد الرمز', 'Offline — the code can’t refresh')
                          : tr('رمز ديناميكي يتجدد خلال $_left ث', 'Dynamic code refreshes in ${_left}s'),
                      style: TextStyle(color: _offline ? C.bad : C.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE9F0FB), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: C.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('اعرض الرمز عند نقطة الأمن أو نقطة التجمع · لقطة الشاشة لا تصلح للدخول', 'Show the code at a security or muster point · a screenshot won’t work'),
                      style: const TextStyle(color: C.navy, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Text(tr('بيانات الهوية والصورة الرسمية يديرها فريق ORT · تصل لمسؤول الإخلاء وفرق الاستجابة أثناء الحادث فقط', 'ID details and the official photo are managed by ORT · shared with the fire warden and responders during an incident only'),
                textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _row(String label, dynamic value, {bool mono = false, bool ltr = false, bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${value ?? ''}'.isEmpty ? '—' : '$value',
                textDirection: ltr ? TextDirection.ltr : null,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: C.fg, fontFeatures: mono ? const [FontFeature.tabularFigures()] : null),
              ),
            ),
          ),
        ]),
      );
}
