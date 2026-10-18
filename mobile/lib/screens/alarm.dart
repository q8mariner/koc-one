// Full-screen alarm: the site tone loops on the alarm audio stream until the employee records a status.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/live.dart';

class AlarmScreen extends StatefulWidget {
  final Map<String, dynamic> alarm;
  const AlarmScreen({super.key, required this.alarm});
  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final _player = AudioPlayer();
  bool _sounding = false;

  Map<String, dynamic> get a => widget.alarm;
  String get kind => a['kind'] as String;

  static const _colors = {'signal1': Color(0xFFB45309), 'signal2': Color(0xFFB91C1C), 'signal3': Color(0xFF15803D)};
  static const _tones = {'signal1': 'تقطّع · خطر محتمل', 'signal2': 'متموّج · وقع الخطر', 'signal3': 'متصل · انتهى الخطر'};

  @override
  void initState() {
    super.initState();
    final st = LiveService.I.myStatus[a['id']];
    if (st == null || st == 'received') _startSound();
  }

  Future<void> _startSound() async {
    if (!kind.startsWith('signal')) return;
    try {
      await _player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));
      await _player.setReleaseMode(kind == 'signal3' ? ReleaseMode.release : ReleaseMode.loop);
      await _player.play(AssetSource('sounds/$kind.wav'), volume: 1.0);
      setState(() => _sounding = true);
    } catch (_) {}
  }

  Future<void> _stopSound() async {
    await _player.stop();
    if (mounted) setState(() => _sounding = false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _set(String status) async {
    await _stopSound();
    await LiveService.I.ack(a['id'], status);
    if (!mounted) return;
    if (status == 'safe') Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final live = LiveService.I;
    final c = _colors[kind] ?? const Color(0xFF0E7490);
    final mine = live.myStatus[a['id']];
    final steps = ((a['body'] as String?) ?? '').split('\n').where((s) => s.trim().isNotEmpty).toList();
    final muster = live.musterPoint();
    return Scaffold(
      backgroundColor: c,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Text(a['drill'] == true ? 'تمرين · DRILL' : 'KOC ONE · ECC-160', style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700, color: Colors.white70)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 8),
          Text(a['title'] ?? '', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 6),
          Text('${live.areaLabel()}${_tones[kind] != null ? ' · نغمة ${_tones[kind]}' : ''}', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          for (final s in steps)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
              child: Text(s, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          if (muster != null && kind == 'signal2')
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(10)),
              child: Text('نقطة التجمع: $muster', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 16),
          if (kind == 'signal3')
            _btn('حسنًا — عودة إلى العمل', Colors.white, Colors.black, () => _set('safe'))
          else ...[
            Text(mine == null || mine == 'received' ? 'ما حالتك الآن؟ تصل إجابتك فورًا لمسؤول الإخلاء و ORT' : 'سُجّلت حالتك: ${_label(mine)} — يمكنك تحديثها',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _btn('أُخليت — أنا آمن', const Color(0xFF22C55E), Colors.black, () => _set('safe'), selected: mine == 'safe'),
            _btn('أحتاج مساعدة', const Color(0xFFFB923C), Colors.black, () => _set('need_help'), selected: mine == 'need_help'),
            _btn('مصاب — أحتاج إسعافًا', Colors.white, const Color(0xFFB91C1C), () => _set('injured'), selected: mine == 'injured'),
            _btn('محتجز داخل المبنى', Colors.black, Colors.white, () => _set('trapped'), selected: mine == 'trapped'),
          ],
          if (_sounding) TextButton.icon(onPressed: _stopSound, icon: const Icon(Icons.volume_off, color: Colors.white), label: const Text('إيقاف الصوت', style: TextStyle(color: Colors.white))),
          const SizedBox(height: 8),
          const Text('موقعك يُشارك مع فرق الاستجابة أثناء الحادث فقط حتى «زوال الخطر».', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }

  static String _label(String? s) => const {'safe': 'آمن', 'need_help': 'يحتاج مساعدة', 'injured': 'مصاب', 'trapped': 'محتجز'}[s] ?? '';

  Widget _btn(String t, Color bg, Color fg, VoidCallback onTap, {bool selected = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            padding: const EdgeInsets.all(18),
            side: selected ? const BorderSide(color: Colors.white, width: 3) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(selected ? '✓  $t' : t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      );
}
