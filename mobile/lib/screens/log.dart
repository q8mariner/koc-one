// Area log: every time the employee entered or left a sector, zone or building, grouped by day.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../services/live.dart';
import '../ui.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final live = LiveService.I;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    live.addListener(_onLive);
    _load();
  }

  @override
  void dispose() {
    live.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    if (live.transitions != _seen) {
      _seen = live.transitions;
      Future.delayed(const Duration(milliseconds: 600), _load); // let the insert land
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await Supabase.instance.client
          .from('geofence_events')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(300);
      if (mounted) setState(() { _rows = List<Map<String, dynamic>>.from(r); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return tr('اليوم', 'Today');
    if (day == today.subtract(const Duration(days: 1))) return tr('أمس', 'Yesterday');
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  String _typeLabel(String t) => switch (t) {
        'sector' => tr('قطاع', 'Sector'),
        'zone' => 'Zone',
        'building' => tr('مبنى', 'Building'),
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    // group by day
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final d = DateTime.tryParse('${r['created_at']}')?.toLocal();
      if (d == null) continue;
      groups.putIfAbsent(_day(d), () => []).add({...r, '_t': d});
    }
    final todayEntries = _rows.where((r) {
      final d = DateTime.tryParse('${r['created_at']}')?.toLocal();
      final n = DateTime.now();
      return d != null && d.year == n.year && d.month == n.month && d.day == n.day && r['event'] == 'enter';
    }).length;

    return Scaffold(
      appBar: AppBar(title: Text(tr('إشعارات', 'Notifications'), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          // current position + today summary
          Row(children: [
            Expanded(child: _tile(C.navy, Icons.place_outlined, tr('موقعك الآن', 'You are in'), live.areaLabel())),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: _tile(C.ok, Icons.login, tr('دخول اليوم', 'Entries today'), '$todayEntries')),
          ]),
          const SizedBox(height: 4),
          Text(tr('يُسجَّل الدخول والخروج تلقائيًا عند عبور حدود GPS فقط — لا تتبّع مستمر.', 'Entries and exits are logged automatically at GPS boundaries only — no continuous tracking.'),
              style: const TextStyle(color: C.muted, fontSize: 12)),
          if (_loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OneCard(child: Text(tr('لا توجد حركة مسجلة بعد. يظهر هنا كل دخول وخروج من القطاعات والـ Zones والمباني.', 'No movements yet. Every entry and exit from sectors, zones and buildings appears here.'), style: const TextStyle(color: C.muted))),
            ),
          for (final g in groups.entries) ...[
            SectionTitle(g.key),
            OneCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < g.value.length; i++) _entry(g.value[i], last: i == g.value.length - 1),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _tile(Color c, IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      );

  Widget _entry(Map<String, dynamic> r, {required bool last}) {
    final enter = r['event'] == 'enter';
    final t = r['_t'] as DateTime;
    final type = r['area_type'] as String;
    final name = live.areaName(type, r['area_id'] as String?) ?? tr('منطقة محذوفة', 'Deleted area');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: C.line))),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: enter ? const Color(0xFFE6F4EC) : const Color(0xFFEEF1F6),
          child: Icon(enter ? Icons.login : Icons.logout, size: 18, color: enter ? C.ok : C.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg)),
            Text('${enter ? tr('دخول', 'Entered') : tr('خروج', 'Left')} · ${_typeLabel(type)}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
        Text('${_two(t.hour)}:${_two(t.minute)}', style: const TextStyle(fontWeight: FontWeight.w700, color: C.navy, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }
}
