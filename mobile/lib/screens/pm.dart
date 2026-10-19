// PM (postmaster): news, events, circulars, offers and announcements published by the dashboard.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../ui.dart';

class PostKind {
  final String ar, en;
  final IconData icon;
  final Color color;
  const PostKind(this.ar, this.en, this.icon, this.color);
  String get name => tr(ar, en);
}

const postKinds = <String, PostKind>{
  'news': PostKind('أخبار', 'News', Icons.newspaper, C.navy),
  'event': PostKind('فعاليات', 'Events', Icons.event, Color(0xFF0E7490)),
  'circular': PostKind('تعاميم', 'Circulars', Icons.campaign_outlined, Color(0xFFB45309)),
  'offer': PostKind('عروض', 'Offers', Icons.local_offer_outlined, C.ok),
  'announcement': PostKind('إعلانات', 'Announcements', Icons.info_outline, Color(0xFF6D28D9)),
};

String _t(Map p, String f) {
  final en = p['${f}_en'] as String?;
  return Lang.I.isEn && en != null && en.trim().isNotEmpty ? en : (p[f] as String? ?? '');
}

String _date(dynamic iso, {bool time = false}) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  const arM = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  const enM = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final s = '${d.day} ${tr(arM[d.month - 1], enM[d.month - 1])}';
  if (!time) return s;
  final h = d.hour.toString().padLeft(2, '0'), m = d.minute.toString().padLeft(2, '0');
  return '$s · $h:$m';
}

class PmScreen extends StatefulWidget {
  const PmScreen({super.key});
  @override
  State<PmScreen> createState() => _PmScreenState();
}

class _PmScreenState extends State<PmScreen> {
  final sb = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  String _kind = 'all';
  bool _loading = true;
  String? _err;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = sb.channel('pm-posts').onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'posts', callback: (_) => _load()).subscribe();
  }

  @override
  void dispose() {
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await sb.from('posts').select().order('pinned', ascending: false).order('created_at', ascending: false).limit(100);
      if (mounted) setState(() { _posts = List<Map<String, dynamic>>.from(r); _loading = false; _err = null; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _err = tr('تعذّر تحميل المنشورات. اسحب للتحديث.', 'Couldn’t load posts. Pull to refresh.'); });
    }
  }

  void _open(Map<String, dynamic> p) => Navigator.push(context, MaterialPageRoute(builder: (_) => PostScreen(post: p)));

  Widget _eventBox(Map p, Color color) {
    final d = DateTime.tryParse('${p['event_at']}')?.toLocal();
    if (d == null) return const SizedBox.shrink();
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text('${d.day}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1.1)),
        Text(_date(p['event_at']).split(' ').last, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final k = postKinds[p['kind']] ?? postKinds['news']!;
    final isEvent = p['kind'] == 'event' && p['event_at'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(p),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: k.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(k.icon, size: 16, color: k.color),
                          const SizedBox(width: 6),
                          Text(k.name, style: TextStyle(color: k.color, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          if (p['pinned'] == true) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.push_pin, size: 14, color: C.warn),
                          ],
                          const Spacer(),
                          Text(_date(p['created_at']), style: const TextStyle(color: C.muted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_t(p, 'title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: C.fg, height: 1.35)),
                        const SizedBox(height: 4),
                        Text(_t(p, 'body'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, height: 1.45)),
                        if (isEvent && (p['location'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.place_outlined, size: 15, color: C.muted),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${p['location']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5))),
                          ]),
                        ],
                      ]),
                    ),
                    if (isEvent) ...[const SizedBox(width: 12), _eventBox(p, k.color)],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _kind == 'all' ? _posts : _posts.where((p) => p['kind'] == _kind).toList();
    return Scaffold(
      appBar: AppBar(title: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('PM', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        Text(tr('· النشرة', '· Postmaster'), style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 15)),
      ])),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SizedBox(
            height: 38,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in [('all', tr('الكل', 'All')), for (final k in postKinds.entries) (k.key, k.value.name)])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(e.$2),
                    selected: _kind == e.$1,
                    showCheckmark: false,
                    selectedColor: C.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _kind == e.$1 ? C.navy : C.line),
                    labelStyle: TextStyle(color: _kind == e.$1 ? Colors.white : C.navy, fontWeight: FontWeight.w700, fontSize: 13),
                    onSelected: (_) => setState(() => _kind = e.$1),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
          if (_err != null) OneCard(child: Text(_err!, style: const TextStyle(color: C.bad))),
          if (!_loading && _err == null && list.isEmpty)
            OneCard(child: Text(tr('لا توجد منشورات بعد.', 'No posts yet.'), style: const TextStyle(color: C.muted))),
          for (final p in list) _card(p),
        ]),
      ),
    );
  }
}

class PostScreen extends StatelessWidget {
  final Map<String, dynamic> post;
  const PostScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final k = postKinds[p['kind']] ?? postKinds['news']!;
    return Scaffold(
      appBar: AppBar(title: Text(k.name, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: k.color, borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(k.icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(k.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(_date(p['created_at']), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ]),
            const SizedBox(height: 12),
            Text(_t(p, 'title'), style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.35)),
          ]),
        ),
        if (p['event_at'] != null) ...[
          const SizedBox(height: 12),
          OneCard(
            child: Column(children: [
              Row(children: [
                Icon(Icons.schedule, color: k.color),
                const SizedBox(width: 10),
                Text(_date(p['event_at'], time: true), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              if ((p['location'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.place_outlined, color: k.color),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${p['location']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ],
            ]),
          ),
        ] else
          const SizedBox(height: 14),
        Text(_t(p, 'body'), style: const TextStyle(fontSize: 16, height: 1.7, color: C.fg)),
      ]),
    );
  }
}
