import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/live.dart';
import '../services/native_alarm.dart';
import '../services/notify.dart';
import 'alarm.dart';
import 'report.dart';

const kindColor = {
  'signal1': Color(0xFFF59E0B),
  'signal2': Color(0xFFEF4444),
  'signal3': Color(0xFF22C55E),
  'message': Color(0xFF38BDF8),
};
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
    Widget row(String title, String sub, bool done, Future<void> Function() open) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(done ? Icons.check_circle : Icons.error, color: done ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
          trailing: done ? null : FilledButton(onPressed: open, child: const Text('تفعيل')),
        );
    return Card(
      color: const Color(0xFF3B2F05),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أكمل تجهيز الإنذار ليخترق كل أوضاع الهاتف', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          row('تجاوز «عدم الإزعاج»', 'يُسمع الإنذار حتى في وضع عدم الإزعاج', _native['dnd']!, NativeAlarm.openDnd),
          row('الظهور فوق التطبيقات', 'يقطع الإنذار أي تطبيق مفتوح ويظهر فوقه', _native['overlay']!, NativeAlarm.openOverlay),
          row('إشعارات ملء الشاشة', 'يُضيء الشاشة ويظهر فوق قفلها', _native['fullScreen']!, NativeAlarm.openFullScreen),
        ]),
      ),
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
        title: const Text('KOC ONE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        actions: [
          PopupMenuButton<String>(
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
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_startErr != null) _banner(_startErr!, const Color(0xFF3A1216), action: TextButton(onPressed: () { setState(() => _startErr = null); _boot(); }, child: const Text('إعادة'))),
          if (!_permsOk)
            _banner('الإنذارات تحتاج إذن الإشعارات والموقع (يُفضّل «السماح طوال الوقت») لتصلك والهاتف مقفل.', const Color(0xFF3B2F05),
                action: TextButton(onPressed: openAppSettings, child: const Text('الإعدادات'))),
          if (_native.values.contains(false)) _alarmSetup(),
          for (final a in myActive)
            Card(
              color: kindColor[a['kind']]!.withValues(alpha: .18),
              shape: RoundedRectangleBorder(side: BorderSide(color: kindColor[a['kind']]!, width: 1.5), borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(Icons.campaign, color: kindColor[a['kind']]),
                title: Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('حالتك: ${statusLabel[live.myStatus[a['id']]] ?? 'لم تُسجّل'} — اضغط لتحديثها'),
                onTap: () => Navigator.push(context, MaterialPageRoute(settings: const RouteSettings(name: '/alarm'), builder: (_) => AlarmScreen(alarm: a))),
              ),
            ),
          // Where am I
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me?['full_name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('رقم ${me?['employee_no'] ?? '—'} · فصيلة الدم ${me?['blood_type'] ?? '—'}', style: const TextStyle(color: Colors.white60)),
                const Divider(height: 24),
                Row(children: [
                  Icon(live.where.insideAny ? Icons.shield : Icons.location_off, color: live.where.insideAny ? const Color(0xFF22C55E) : Colors.white38),
                  const SizedBox(width: 8),
                  Expanded(child: Text(live.areaLabel(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  if (cls != null && cls != 'unclassified') Chip(label: Text(cls.toUpperCase().replaceAll('ZONE', 'Zone ')), backgroundColor: const Color(0xFF3A1D06)),
                ]),
                if (live.musterPoint() != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('نقطة التجمع: ${live.musterPoint()}')),
                const SizedBox(height: 4),
                Text(live.gpsState, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _bigButton(Icons.report, 'بلاغ إلى 160', 'مع صور مشفرة', const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _bigButton(Icons.phone_in_talk, 'اتصال 160', 'مركز الطوارئ', const Color(0xFFEF4444), _call160)),
          ]),
          const SizedBox(height: 10),
          _bigButton(Icons.sos, 'أحتاج مساعدة الآن', 'يرسل موقعك إلى ORT فورًا', const Color(0xFFDC2626), () {
            if (myActive.isNotEmpty) {
              live.ack(myActive.first['id'], 'need_help');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سُجّلت حالتك: يحتاج مساعدة — سيتواصل معك الفريق')));
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen(initialType: 'sos')));
            }
          }),
          const SizedBox(height: 20),
          const Text('الإنذارات والتنبيهات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          if (live.inbox.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد إنذارات. ستصلك هنا إنذارات المنطقة التي تتواجد داخل حدودها.', style: TextStyle(color: Colors.white54))),
          for (final a in live.inbox)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 6, backgroundColor: kindColor[a['kind']] ?? Colors.grey),
              title: Text(a['title'] ?? ''),
              subtitle: Text('${kindLabel[a['kind']] ?? ''}${a['drill'] == true ? ' · تمرين' : ''}${live.myStatus[a['id']] != null ? ' · ${statusLabel[live.myStatus[a['id']]]}' : ''}'),
              trailing: Text(_time(a['created_at']), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => showModalBottomSheet(context: context, builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Text('${a['title']}\n\n${a['body'] ?? ''}', style: const TextStyle(fontSize: 16)))),
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

  Widget _banner(String text, Color bg, {Widget? action}) => Card(
        color: bg,
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text(text)), if (action != null) action])),
      );

  Widget _bigButton(IconData icon, String title, String sub, Color c, VoidCallback onTap) => Material(
        color: c.withValues(alpha: .15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.withValues(alpha: .6))),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: c, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
            ]),
          ),
        ),
      );
}
