import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/live.dart';
import '../services/native_alarm.dart';
import '../services/notify.dart';
import '../ui.dart';
import 'alarm.dart';
import 'report.dart';

const kindColor = {'signal1': C.sig1, 'signal2': C.sig2, 'signal3': C.sig3, 'message': C.navy};
const kindLabel = {'signal1': 'الإشارة 1 · طوارئ', 'signal2': 'الإشارة 2 · إخلاء', 'signal3': 'الإشارة 3 · زوال الخطر', 'message': 'تنبيه'};
const statusLabel = {'received': 'استُلم', 'safe': 'آمن', 'need_help': 'يحتاج مساعدة', 'injured': 'مصاب', 'trapped': 'محتجز'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final live = LiveService.I;
  bool _permsOk = true;
  Map<String, bool> _native = const {'dnd': true, 'overlay': true, 'fullScreen': true};
  String? _startErr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    live.addListener(_refresh);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    live.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkPerms();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    await _askPerms();
    try {
      await live.start();
    } catch (e) {
      setState(() => _startErr = 'تعذّر الاتصال بالخادم. تحقق من الشبكة ثم أعد المحاولة.');
    }
  }

  Future<void> _askPerms() async {
    await Notify.requestPermissions();
    await [Permission.location, Permission.microphone, Permission.camera].request();
    if (await Permission.location.isGranted) await Permission.locationAlways.request();
    await _checkPerms();
  }

  Future<void> _checkPerms() async {
    final ok = await Permission.notification.isGranted && await Permission.location.isGranted;
    final native = await NativeAlarm.status();
    await NativeAlarm.ensureChannels(); // re-create channels with DND bypass once access is granted
    if (mounted) {
      setState(() {
        _permsOk = ok;
        _native = native;
      });
    }
  }

  Widget _alarmSetup() {
    Widget row(String title, String sub, bool done, Future<void> Function() open) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? C.ok : C.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg)),
                Text(sub, style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            if (!done) FilledButton(onPressed: open, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('تفعيل')),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.yellow, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('أكمل تجهيز الإنذار ليخترق كل أوضاع الهاتف', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF6B5200))),
        row('تجاوز «عدم الإزعاج»', 'يُسمع الإنذار حتى في وضع عدم الإزعاج', _native['dnd']!, NativeAlarm.openDnd),
        row('الظهور فوق التطبيقات', 'يقطع الإنذار أي تطبيق مفتوح ويظهر فوقه', _native['overlay']!, NativeAlarm.openOverlay),
        row('إشعارات ملء الشاشة', 'يُضيء الشاشة ويظهر فوق قفلها', _native['fullScreen']!, NativeAlarm.openFullScreen),
      ]),
    );
  }

  Future<void> _logout() async {
    await live.stop();
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _call160() async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: ecc160Number));
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح الاتصال — اطلب 160 يدويًا')));
  }

  @override
  Widget build(BuildContext context) {
    final me = live.me;
    final myActive = live.activeAlarms.where((a) => live.inbox.any((i) => i['id'] == a['id'])).toList();
    final cls = live.zoneClass();
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(size: 26),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: C.navy),
            onSelected: (v) => v == 'out' ? _logout() : _askPerms(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'perm', child: Text('مراجعة الأذونات')),
              PopupMenuItem(value: 'out', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _checkPerms(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (_startErr != null) _banner(_startErr!, C.bad, action: TextButton(onPressed: () { setState(() => _startErr = null); _boot(); }, child: const Text('إعادة'))),
          if (!_permsOk)
            _banner('الإنذارات تحتاج إذن الإشعارات والموقع («السماح طوال الوقت») لتصلك والهاتف مقفل.', C.warn,
                action: TextButton(onPressed: openAppSettings, child: const Text('الإعدادات'))),
          if (_native.values.contains(false)) _alarmSetup(),

          // Active alarms
          for (final a in myActive)
            OneCard(
              color: kindColor[a['kind']],
              onTap: () => Navigator.push(context, MaterialPageRoute(settings: const RouteSettings(name: '/alarm'), builder: (_) => AlarmScreen(alarm: a))),
              child: Row(children: [
                const Icon(Icons.campaign, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('حالتك: ${statusLabel[live.myStatus[a['id']]] ?? 'لم تُسجّل'} — اضغط لتحديثها', style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                const Icon(Icons.chevron_left, color: Colors.white),
              ]),
            ),

          // Identity + location (the "digital ID" card)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              const Positioned.fill(child: Opacity(opacity: .35, child: Stripes())),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(me?['full_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
                    if (me?['blood_type'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: C.bad, borderRadius: BorderRadius.circular(20)),
                        child: Text('${me?['blood_type']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                  Text('الرقم الوظيفي ${me?['employee_no'] ?? '—'}', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(live.where.insideAny ? Icons.shield : Icons.location_off, color: live.where.insideAny ? C.ok : C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(live.areaLabel(), style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg)),
                          if (live.musterPoint() != null) Text('نقطة التجمع: ${live.musterPoint()}', style: const TextStyle(color: C.muted, fontSize: 12)),
                          Text(live.gpsState, style: const TextStyle(color: C.muted, fontSize: 11)),
                        ]),
                      ),
                      if (cls != null && cls != 'unclassified')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFDE6D3), borderRadius: BorderRadius.circular(10)),
                          child: Text(cls.toUpperCase().replaceAll('ZONE', 'Zone '), style: const TextStyle(color: Color(0xFFA4501A), fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),

          // Actions
          Row(children: [
            Expanded(child: _action(Icons.report_gmailerrorred, 'بلاغ إلى 160', 'مع صور مشفرة', C.warn, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _action(Icons.phone_in_talk, 'اتصال 160', 'موقعك يُرسل تلقائيًا', C.bad, _call160)),
          ]),
          const SizedBox(height: 10),
          OneCard(
            color: C.bad,
            onTap: () {
              if (myActive.isNotEmpty) {
                live.ack(myActive.first['id'], 'need_help');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سُجّلت حالتك: يحتاج مساعدة — سيتواصل معك الفريق')));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen(initialType: 'sos')));
              }
            },
            child: const Row(children: [
              Icon(Icons.sos, color: Colors.white, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('أحتاج مساعدة الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('يرسل حالتك وموقعك إلى ORT فورًا', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),

          const SectionTitle('الإنذارات والتنبيهات'),
          if (live.inbox.isEmpty)
            const OneCard(child: Text('لا توجد إنذارات. تصلك هنا إنذارات المنطقة التي تتواجد داخل حدودها.', style: TextStyle(color: C.muted))),
          for (final a in live.inbox)
            OneCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Text('${a['title']}\n\n${a['body'] ?? ''}', style: const TextStyle(fontSize: 16))),
              ),
              child: Row(children: [
                Container(width: 10, height: 40, decoration: BoxDecoration(color: kindColor[a['kind']] ?? C.muted, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg)),
                    Text('${kindLabel[a['kind']] ?? ''}${a['drill'] == true ? ' · تمرين' : ''}${live.myStatus[a['id']] != null ? ' · ${statusLabel[live.myStatus[a['id']]]}' : ''}',
                        style: const TextStyle(color: C.muted, fontSize: 12)),
                  ]),
                ),
                Text(_time(a['created_at']), style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
        ]),
      ),
    );
  }

  static String _time(dynamic t) {
    final d = DateTime.tryParse('$t')?.toLocal();
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _banner(String text, Color c, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .5))),
        child: Row(children: [Expanded(child: Text(text, style: const TextStyle(color: C.fg))), if (action != null) action]),
      );

  Widget _action(IconData icon, String title, String sub, Color c, VoidCallback onTap) => OneCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 22, backgroundColor: c.withValues(alpha: .12), child: Icon(icon, color: c)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.navy)),
          Text(sub, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );
}
