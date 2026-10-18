// Full-screen alarm, designed after the proposal's alarm screens (Annex F).
// The tone plays natively on the alarm stream (see NativeAlarm). The screen cannot be dismissed
// until the employee records a status; if they leave the app it returns every 15 seconds.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/live.dart';
import '../i18n.dart';
import '../ui.dart';

class AlarmScreen extends StatefulWidget {
  final Map<String, dynamic> alarm;
  const AlarmScreen({super.key, required this.alarm});
  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _Look {
  final Color bg, panel, accent;
  final IconData icon;
  final String eyebrow, tone;
  const _Look(this.bg, this.panel, this.accent, this.icon, this.eyebrow, this.tone);
}

const _looks = {
  'signal1': _Look(C.sig1, Color(0xFF9E1F1F), Color(0xFF5C1111), Icons.warning_amber_rounded, 'SIGNAL 1 · EMERGENCY', 'broken'),
  'signal2': _Look(C.sig2, Color(0xFF1E2026), C.sig1, Icons.login_rounded, 'SIGNAL 2 · EVACUATION', 'wailing'),
  'signal3': _Look(C.sig3, Color(0xFF247D48), C.sig3, Icons.check_circle_outline_rounded, 'SIGNAL 3 · ALL CLEAR', 'steady'),
};

class _AlarmScreenState extends State<AlarmScreen> {
  final live = LiveService.I;
  Map<String, dynamic> get a => widget.alarm;
  String get kind => a['kind'] as String;

  @override
  void initState() {
    super.initState();
    live.addListener(_refresh);
  }

  @override
  void dispose() {
    live.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _answered {
    final st = live.myStatus[a['id']];
    return st != null && st != 'received';
  }

  Future<void> _set(String status) async {
    await live.ack(a['id'], status);
    if (!mounted) return;
    if (status == 'safe' && Navigator.canPop(context)) Navigator.pop(context);
  }

  String _clock(dynamic t) {
    final d = DateTime.tryParse('$t')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final look = _looks[kind] ?? const _Look(C.navy, C.navyD, C.navy, Icons.campaign, 'ALERT', '');
    final mine = live.myStatus[a['id']];
    final steps = alarmBody(a)
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    final muster = live.musterPoint();
    if (kind == 'signal2' && muster != null && !steps.any((s) => s.contains(muster))) steps.add(tr('توجّه إلى نقطة التجمع: ', 'Go to muster point: ') + muster);

    return PopScope(
      canPop: _answered,
      child: Scaffold(
        backgroundColor: look.bg,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
            Row(children: [
              if (a['drill'] == true) Tag(tr('تمرين · DRILL', 'DRILL'), color: Colors.black26),
              const Spacer(),
              if (_answered) IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
            const SizedBox(height: 12),
            // icon with halo
            Center(
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12)),
                alignment: Alignment.center,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .22)),
                  child: Icon(look.icon, color: Colors.white, size: 42),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(look.eyebrow, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white70, letterSpacing: 2.5, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(alarmTitle(a), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.25)),
            const SizedBox(height: 6),
            Text('${live.areaLabel()} · ${_clock(a['created_at'])}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ToneMark(kind: kind),
              const SizedBox(width: 8),
              Text(_toneLabel(look.tone), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 20),
            // numbered steps
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: look.panel, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Text('${i + 1}', style: TextStyle(color: look.bg, fontWeight: FontWeight.w800, fontSize: 12))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(steps[i], style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.45))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            if (kind == 'signal3')
              _btn(tr('العودة إلى العمل', 'Back to work'), Colors.white, C.sig3, Icons.check_circle_outline, () => _set('safe'))
            else ...[
              Text(_answered ? tr('سُجّلت حالتك: ', 'Status recorded: ') + statusLabelOf(mine) + tr(' — يمكنك تحديثها', ' — you can update it') : tr('اختر حالتك الآن — تصل فورًا لمسؤول الإخلاء و ORT', 'Choose your status now — it goes straight to the fire warden and ORT'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _btn(kind == 'signal1' ? tr('أنا بخير', 'I’m OK') : tr('أنا بأمان', 'I’m safe'), Colors.white, C.ok, Icons.check_circle_outline, () => _set('safe'), selected: mine == 'safe')),
                const SizedBox(width: 10),
                Expanded(child: _btn(tr('أحتاج مساعدة', 'I need help'), look.accent, Colors.white, Icons.warning_amber_rounded, () => _set('need_help'), selected: mine == 'need_help')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _outline(tr('مصاب', 'Injured'), Icons.medical_services_outlined, () => _set('injured'), mine == 'injured')),
                const SizedBox(width: 10),
                Expanded(child: _outline(tr('محتجز داخل المبنى', 'Trapped inside'), Icons.door_front_door_outlined, () => _set('trapped'), mine == 'trapped')),
              ]),
            ],
            const SizedBox(height: 14),
            Text(tr('التنبيه يتجاوز الوضع الصامت · يصل لكل من بالموقع · موقعك يُشارك أثناء الحادث فقط', 'Overrides silent mode · reaches everyone on site · your location is shared during the incident only'),
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }


  static String _toneLabel(String k) => switch (k) {
        'broken' => tr('نغمة متقطّعة', 'Broken tone'),
        'wailing' => tr('نغمة متموّجة', 'Wailing tone'),
        'steady' => tr('نغمة متصلة ثابتة', 'Steady tone'),
        _ => '',
      };

  Widget _btn(String t, Color bg, Color fg, IconData icon, VoidCallback onTap, {bool selected = false}) => FilledButton.icon(
        onPressed: onTap,
        icon: Icon(selected ? Icons.check : icon, size: 20),
        label: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(56),
          side: selected ? const BorderSide(color: C.yellow, width: 3) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _outline(String t, IconData icon, VoidCallback onTap, bool selected) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(selected ? Icons.check : icon, size: 18),
        label: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: selected ? C.yellow : Colors.white54, width: selected ? 3 : 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}

/// Small visual of the tone: dashes (broken), wave (wailing) or a steady line.
class _ToneMark extends StatelessWidget {
  final String kind;
  const _ToneMark({required this.kind});
  @override
  Widget build(BuildContext context) => SizedBox(width: 64, height: 14, child: CustomPaint(painter: _TonePainter(kind)));
}

class _TonePainter extends CustomPainter {
  final String kind;
  _TonePainter(this.kind);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = s.height / 2;
    if (kind == 'signal1') {
      for (var x = 2.0; x < s.width; x += 22) {
        canvas.drawLine(Offset(x, y), Offset(x + 14, y), p);
      }
    } else if (kind == 'signal2') {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= s.width; x += 2) {
        path.lineTo(x, y + 5 * math.sin(x / s.width * 4 * math.pi));
      }
      canvas.drawPath(path, p);
    } else {
      canvas.drawLine(Offset(2, y), Offset(s.width - 2, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _TonePainter old) => old.kind != kind;
}
