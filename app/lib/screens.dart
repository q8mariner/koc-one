import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'main.dart' show Section;
import 'ui.dart';

const _pagePad = EdgeInsets.fromLTRB(18, 12, 18, 110);

// ───────────────────────────── Home ─────────────────────────────
class HomePage extends StatefulWidget {
  final void Function(Section) go;
  const HomePage({super.key, required this.go});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<dynamic>> f;
  @override
  void initState() {
    super.initState();
    f = _load();
  }

  Future<List<dynamic>> _load() => Future.wait([Repo.operations(), Repo.weather(), Repo.news()]);

  Future<void> _refresh() async {
    final nf = _load();
    setState(() { f = nf; });
    await nf;
  }

  @override
  Widget build(BuildContext context) => Loader<List<dynamic>>(
        future: f,
        onRetry: _refresh,
        builder: (d) {
          final ops = d[0] as List<OpsMonth>;
          final wx = d[1] as List<Weather>;
          final news = d[2] as List<News>;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(padding: const EdgeInsets.fromLTRB(0, 12, 0, 40), children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: OpsCard(ops, onTap: () => widget.go(Section.operations)),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: wx.isEmpty
                    ? const EmptyNote('No weather entered yet.')
                    : WeatherMini(wx.first, onTap: () => widget.go(Section.weather)),
              ),
              const SizedBox(height: 26),
              if (news.isNotEmpty) NewsCarousel(news),
            ]),
          );
        },
      );
}

class OpsCard extends StatelessWidget {
  final List<OpsMonth> ops;
  final VoidCallback? onTap;
  final double chartHeight;
  const OpsCard(this.ops, {super.key, this.onTap, this.chartHeight = 110});

  @override
  Widget build(BuildContext context) {
    final total = ops.fold<int>(0, (a, b) => a + b.count);
    final from = ops.isEmpty ? null : ops.first.month;
    return Glass(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
      child: Column(children: [
        const Text('Total Of Operations',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: kInk)),
        Text('$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk)),
        if (from != null)
          Text('From ${monthNames[from.month - 1]} ${from.year}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B6F80))),
        const SizedBox(height: 4),
        Sparkline(ops.map((e) => e.count.toDouble()).toList(), height: chartHeight),
      ]),
    );
  }
}

class WeatherMini extends StatelessWidget {
  final Weather w;
  final VoidCallback? onTap;
  const WeatherMini(this.w, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) => Glass(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            WeatherIcon(w.condition, size: 100),
            const SizedBox(width: 16),
            Text('${fmtNum(w.temp)}°C',
                style: const TextStyle(fontSize: 44, color: kInk, fontWeight: FontWeight.w300)),
          ]),
          const SizedBox(height: 10),
          WindRow(wind: w.wind, dir: w.windDir, humidity: w.humidity),
        ]),
      );
}

class NewsCarousel extends StatefulWidget {
  final List<News> news;
  const NewsCarousel(this.news, {super.key});
  @override
  State<NewsCarousel> createState() => _NewsCarouselState();
}

class _NewsCarouselState extends State<NewsCarousel> {
  final pc = PageController(viewportFraction: 0.9);
  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 250,
        child: PageView.builder(
          controller: pc,
          itemCount: widget.news.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: NewsCard(widget.news[i]),
          ),
        ),
      );
}

// ───────────────────────────── News ─────────────────────────────
class NewsCard extends StatelessWidget {
  final News n;
  final double height;
  const NewsCard(this.n, {super.key, this.height = 250});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsDetail(n))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: height,
            child: Stack(fit: StackFit.expand, children: [
              NetImage(n.image),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kInk)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(n.unit, style: const TextStyle(color: kCyan, fontSize: 13)),
                      const Spacer(),
                      Text(fmtDate(n.date), style: const TextStyle(color: Color(0xFFB8BCC8), fontSize: 12)),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}

class NetImage extends StatelessWidget {
  final String url;
  const NetImage(this.url, {super.key});
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return Container(color: const Color(0xFF8FB0F5));
    return Image.network(url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF8FB0F5),
            child: const Icon(Icons.directions_boat_filled_rounded, color: Colors.white70, size: 60)),
        loadingBuilder: (_, child, p) => p == null ? child : Container(color: const Color(0xFFA9C3F7)));
  }
}

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Future<List<News>> f = Repo.news();
  Future<void> _refresh() async {
    final nf = Repo.news();
    setState(() { f = nf; });
    await nf;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageTitle('News'),
        Expanded(
          child: Loader<List<News>>(
            future: f,
            onRetry: _refresh,
            builder: (list) => RefreshIndicator(
              onRefresh: _refresh,
              child: list.isEmpty
                  ? ListView(padding: _pagePad, children: const [EmptyNote('No news yet.')])
                  : ListView.separated(
                      padding: _pagePad,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (_, i) => NewsCard(list[i], height: 200),
                    ),
            ),
          ),
        ),
      ]);
}

class NewsDetail extends StatelessWidget {
  final News n;
  const NewsDetail(this.n, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(child: Container(color: kBlue)),
          SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white)),
                const Expanded(child: PageTitle('News')),
                const SizedBox(width: 48),
              ]),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 30), children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(height: 230, child: NetImage(n.image))),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(n.body,
                            style: const TextStyle(
                                fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w600, color: Color(0xFF33343B))),
                      ],
                      const SizedBox(height: 14),
                      Row(children: [
                        Text(n.unit, style: const TextStyle(color: kCyan, fontSize: 13)),
                        const Spacer(),
                        Text(fmtDate(n.date), style: const TextStyle(color: Color(0xFFB8BCC8), fontSize: 12)),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      );
}

// ───────────────────────────── Weather ─────────────────────────────
class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});
  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  late Future<List<Weather>> f = Repo.weather();
  final pc = PageController(viewportFraction: 0.92);
  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Loader<List<Weather>>(
        future: f,
        onRetry: () => setState(() { f = Repo.weather(); }),
        builder: (list) => list.isEmpty
            ? const Padding(padding: _pagePad, child: Center(child: EmptyNote('No weather entered yet.')))
            : PageView.builder(
                controller: pc,
                itemCount: list.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 24),
                  child: WeatherFull(list[i]),
                ),
              ),
      );
}

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return weekNames[d.weekday - 1];
}

class WeatherFull extends StatefulWidget {
  final Weather w;
  const WeatherFull(this.w, {super.key});
  @override
  State<WeatherFull> createState() => _WeatherFullState();
}

class _WeatherFullState extends State<WeatherFull> {
  late bool night = DateTime.now().hour >= 17 || DateTime.now().hour < 5;

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final hasDay = w.stateDay.isNotEmpty, hasNight = w.stateNight.isNotEmpty;
    final showNight = (night && hasNight) || !hasDay;
    return Glass(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: ListView(padding: EdgeInsets.zero, children: [
        Row(children: [
          WeatherIcon(w.condition, size: 130),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FittedBox(
                child: Text('${fmtNum(w.temp)}°C',
                    style: const TextStyle(fontSize: 58, color: kInk, fontWeight: FontWeight.w300)),
              ),
              Text(dayLabel(w.day), style: const TextStyle(fontSize: 40, color: kInk, fontWeight: FontWeight.w300)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        WindRow(wind: w.wind, dir: w.windDir, humidity: w.humidity),
        const SizedBox(height: 24),
        for (final t in w.tides)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Text(t.height == null ? '' : '${fmtNum(t.height)} m',
                    style: const TextStyle(fontSize: 18, color: kBlue, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Text(t.label, style: const TextStyle(fontSize: 18, color: kInk))),
              Text(t.time, style: const TextStyle(fontSize: 18, color: kBlue, fontWeight: FontWeight.w700)),
            ]),
          ),
        if (hasDay || hasNight) ...[
          const SizedBox(height: 22),
          const Text('Weather State', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kInk)),
          Text(showNight ? 'By Night' : 'By Day',
              style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
          Text(showNight ? w.stateNight : w.stateDay,
              style: const TextStyle(fontSize: 17, color: kInk, height: 1.3)),
          if (hasDay && hasNight)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => night = !showNight),
                child: Text(showNight ? 'By Day' : 'By Night',
                    style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        const SizedBox(height: 60),
      ]),
    );
  }
}

// ───────────────────────────── Operations ─────────────────────────────
class OperationsPage extends StatefulWidget {
  const OperationsPage({super.key});
  @override
  State<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends State<OperationsPage> {
  late Future<List<OpsMonth>> f = Repo.operations();
  Future<void> _refresh() async {
    final nf = Repo.operations();
    setState(() { f = nf; });
    await nf;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageTitle('Operations'),
        Expanded(
          child: Loader<List<OpsMonth>>(
            future: f,
            onRetry: _refresh,
            builder: (ops) {
              final mx = ops.isEmpty ? 1 : ops.map((e) => e.count).reduce((a, b) => a > b ? a : b);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(padding: _pagePad, children: [
                  OpsCard(ops, chartHeight: 140),
                  const SizedBox(height: 18),
                  Glass(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(children: [
                      for (final o in ops.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(children: [
                            SizedBox(
                              width: 92,
                              child: Text('${monthNames[o.month.month - 1].substring(0, 3)} ${o.month.year}',
                                  style: const TextStyle(fontSize: 15, color: kInk)),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: mx == 0 ? 0 : o.count / mx,
                                  minHeight: 10,
                                  color: kBlue,
                                  backgroundColor: const Color(0x331F5FFF),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: Text('${o.count}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 16, color: kBlue, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              );
            },
          ),
        ),
      ]);
}

// ───────────────────────────── 24h contacts ─────────────────────────────
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  late Future<List<Contact>> f = Repo.contacts();
  Future<void> _refresh() async {
    final nf = Repo.contacts();
    setState(() { f = nf; });
    await nf;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const PageTitle('24 Hours'),
        Expanded(
          child: Loader<List<Contact>>(
            future: f,
            onRetry: _refresh,
            builder: (list) => RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: _pagePad, children: [
                if (list.isEmpty) const EmptyNote('No contacts yet.'),
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => launchUrl(Uri(scheme: 'tel', path: c.phone.replaceAll(' ', ''))),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (c.role.isNotEmpty)
                                  Text(c.role, style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6F80))),
                                Text(c.name,
                                    style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
                                Text(c.phone, style: const TextStyle(fontSize: 14, color: kInk)),
                              ]),
                            ),
                            Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(color: kBlue, shape: BoxShape.circle),
                              child: const Icon(Icons.call_rounded, color: Colors.white),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]);
}

// ───────────────────────────── Duty calendar ─────────────────────────────
class DutyPage extends StatefulWidget {
  const DutyPage({super.key});
  @override
  State<DutyPage> createState() => _DutyPageState();
}

class _DutyPageState extends State<DutyPage> {
  late DateTime month;
  late DateTime selected;
  Map<String, Duty> duty = {};
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    selected = DateTime(n.year, n.month, n.day);
    month = DateTime(n.year, n.month);
    _load();
  }

  DateTime get gridStart {
    final first = DateTime(month.year, month.month, 1);
    return first.subtract(Duration(days: first.weekday % 7)); // weeks start on Sunday
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final start = gridStart;
      final d = await Repo.duty(start, start.add(const Duration(days: 41)));
      if (!mounted) return;
      setState(() {
        duty = d;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  void _shift(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final start = gridStart;
    final days = List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
    // drop the trailing week if it is entirely in the next month
    final shown = days[35].month != month.month ? days.sublist(0, 35) : days;
    final sel = duty[ymd(selected)];
    final now = DateTime.now();
    final title = monthNames[month.month - 1] + (month.year != now.year ? ' ${month.year}' : '');

    return Column(children: [
      GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) _shift(1);
          if (v > 200) _shift(-1);
        },
        child: Row(children: [
          IconButton(
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 32)),
          Expanded(child: PageTitle(title)),
          IconButton(
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 32)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 110), children: [
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) _shift(1);
              if (v > 200) _shift(-1);
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
              decoration: BoxDecoration(color: const Color(0x99B9D0FF), borderRadius: BorderRadius.circular(6)),
              child: Column(children: [
                Row(children: [
                  for (final l in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                    Expanded(
                        child: Text(l,
                            textAlign: TextAlign.center, style: const TextStyle(color: kBlue, fontSize: 13))),
                ]),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.05,
                  children: [for (final d in shown) _dayCell(d)],
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: Colors.white)))
          else if (failed)
            Center(
                child: TextButton(
                    onPressed: _load,
                    child: const Text('Could not load. Tap to retry', style: TextStyle(color: Colors.white))))
          else if (sel == null)
            const EmptyNote('No duty roster for this day.')
          else ...[
            _row(Row(children: [
              const Text('Morning Shift', style: TextStyle(fontSize: 12.5, color: kInk)),
              const SizedBox(width: 8),
              Text(sel.morning, style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('Night Shift', style: TextStyle(fontSize: 12.5, color: kInk)),
              const SizedBox(width: 8),
              Text(sel.night, style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
              const SizedBox(width: 24),
            ])),
            ..._people(sel),
          ],
        ]),
      ),
    ]);
  }

  List<Widget> _people(Duty d) {
    final m = d.people.where((p) => p.shift.toUpperCase() != 'N').toList();
    final n = d.people.where((p) => p.shift.toUpperCase() == 'N').toList();
    Widget person(DutyPerson p) => _row(Row(children: [
          SizedBox(width: 40, child: Text(p.role, style: const TextStyle(fontSize: 12, color: kInk))),
          Container(width: 1, height: 22, color: const Color(0xFFDDE3F0), margin: const EdgeInsets.only(right: 8)),
          Expanded(
            child: Text(p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, color: kBlue, fontWeight: FontWeight.w700)),
          ),
        ]));
    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        );
    return [
      if (m.isNotEmpty && n.isNotEmpty) label('Morning Shift ${d.morning}'),
      ...m.map(person),
      if (n.isNotEmpty) label('Night Shift ${d.night}'),
      ...n.map(person),
    ];
  }

  Widget _row(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
        child: child,
      );

  Widget _dayCell(DateTime d) {
    final inMonth = d.month == month.month;
    final isSel = d == selected;
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    return GestureDetector(
      onTap: () {
        setState(() => selected = d);
        if (!inMonth) {
          setState(() => month = DateTime(d.year, d.month));
          _load();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSel ? kBlue : (inMonth ? const Color(0xFFE6EBF5) : const Color(0x66E6EBF5)),
          borderRadius: BorderRadius.circular(5),
          border: isToday && !isSel ? Border.all(color: kBlue, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: Text(d.day.toString().padLeft(2, '0'),
            style: TextStyle(
                fontSize: 13,
                color: isSel ? Colors.white : (inMonth ? kBlue : Colors.white),
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}
