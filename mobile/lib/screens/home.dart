import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/live.dart';
import '../services/native_alarm.dart';
import '../services/notify.dart';
import '../i18n.dart';
import '../ui.dart';
import 'alarm.dart';
import 'report.dart';

const kindColor = {'signal1': C.sig1, 'signal2': C.sig2, 'signal3': C.sig3, 'message': C.navy};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final live = LiveService.I;
  bool _permsOk = true;
  Map<String, bool> _native = const {'dnd': true, 'overlay': true, 'fullScreen': true, 'battery': true};
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
      setState(() => _startErr = tr('تعذّر الاتصال بالخادم. تحقق من الشبكة ثم أعد المحاولة.', 'Couldn’t reach the server. Check the network and try again.'));
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
            if (!done) FilledButton(onPressed: open, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(tr('تفعيل', 'Enable'))),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.yellow, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('أكمل تجهيز الإنذار ليخترق كل أوضاع الهاتف', 'Finish alarm setup so it breaks through every phone mode'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF6B5200))),
        row(tr('تجاوز «عدم الإزعاج»', 'Override Do Not Disturb'), tr('يُسمع الإنذار حتى في وضع عدم الإزعاج', 'The alarm sounds even in Do Not Disturb'), _native['dnd']!, NativeAlarm.openDnd),
        row(tr('الظهور فوق التطبيقات', 'Display over other apps'), tr('يقطع الإنذار أي تطبيق مفتوح ويظهر فوقه', 'The alarm interrupts any open app and shows on top'), _native['overlay']!, NativeAlarm.openOverlay),
        row(tr('إشعارات ملء الشاشة', 'Full-screen notifications'), tr('يُضيء الشاشة ويظهر فوق قفلها', 'Turns the screen on and shows over the lock screen'), _native['fullScreen']!, NativeAlarm.openFullScreen),
        row(tr('العمل في الخلفية دون قيود البطارية', 'Run in background without battery limits'), tr('يصل الإنذار والتطبيق مغلق', 'Alarms arrive while the app is closed'), _native['battery'] ?? true, NativeAlarm.openBattery),
      ]),
    );
  }

  Future<void> _call160() async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: ecc160Number));
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تعذّر فتح الاتصال — اطلب 160 يدويًا', 'Couldn’t open the dialer — call 160 manually'))));
  }

  @override
  Widget build(BuildContext context) {
    final me = live.me;
    final myActive = live.activeAlarms.where((a) => live.inbox.any((i) => i['id'] == a['id'])).toList();
    final cls = live.zoneClass();
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(size: 26),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _checkPerms(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (_startErr != null) _banner(_startErr!, C.bad, action: TextButton(onPressed: () { setState(() => _startErr = null); _boot(); }, child: Text(tr('إعادة', 'Retry')))),
          if (!_permsOk)
            _banner(tr('الإنذارات تحتاج إذن الإشعارات والموقع («السماح طوال الوقت») لتصلك والهاتف مقفل.', 'Alarms need notification and location (“Allow all the time”) permission to reach you while the phone is locked.'), C.warn,
                action: TextButton(onPressed: openAppSettings, child: Text(tr('الإعدادات', 'Settings')))),
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
                    Text(alarmTitle(a), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(tr('حالتك: ', 'Your status: ') + (live.myStatus[a['id']] == null ? tr('لم تُسجّل', 'not recorded') : statusLabelOf(live.myStatus[a['id']])) + tr(' — اضغط لتحديثها', ' — tap to update'), style: const TextStyle(color: Colors.white70)),
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
                  Text('${tr('الرقم الوظيفي', 'Employee no.')} ${me?['employee_no'] ?? '—'}', style: const TextStyle(color: Colors.white70)),
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
                          if (live.musterPoint() != null) Text('${tr('نقطة التجمع', 'Muster point')}: ${live.musterPoint()}', style: const TextStyle(color: C.muted, fontSize: 12)),
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
            Expanded(child: _action(Icons.report_gmailerrorred, tr('بلاغ إلى 160', 'Report to 160'), tr('مع صور مشفرة', 'With encrypted photos'), C.warn, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _action(Icons.phone_in_talk, tr('اتصال 160', 'Call 160'), tr('موقعك يُرسل تلقائيًا', 'Your location is sent'), C.bad, _call160)),
          ]),
          const SizedBox(height: 10),
          OneCard(
            color: C.bad,
            onTap: () {
              if (myActive.isNotEmpty) {
                live.ack(myActive.first['id'], 'need_help');
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('سُجّلت حالتك: يحتاج مساعدة — سيتواصل معك الفريق', 'Status recorded: needs help — the team will contact you'))));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen(initialType: 'sos')));
              }
            },
            child: Row(children: [
              const Icon(Icons.sos, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('أحتاج مساعدة الآن', 'I need help now'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(tr('يرسل حالتك وموقعك إلى ORT فورًا', 'Sends your status and location to ORT at once'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),

          SectionTitle(tr('الإنذارات والتنبيهات', 'Alarms and alerts')),
          if (live.inbox.isEmpty)
            OneCard(child: Text(tr('لا توجد إنذارات. تصلك هنا إنذارات المنطقة التي تتواجد داخل حدودها.', 'No alarms. Alarms for the area you are inside will appear here.'), style: const TextStyle(color: C.muted))),
          for (final a in live.inbox)
            OneCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Text('${alarmTitle(a)}\n\n${alarmBody(a)}', style: const TextStyle(fontSize: 16))),
              ),
              child: Row(children: [
                Container(width: 10, height: 40, decoration: BoxDecoration(color: kindColor[a['kind']] ?? C.muted, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(alarmTitle(a), style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg)),
                    Text('${kindLabelOf(a['kind'])}${a['drill'] == true ? tr(' · تمرين', ' · drill') : ''}${live.myStatus[a['id']] != null ? ' · ${statusLabelOf(live.myStatus[a['id']])}' : ''}',
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
