import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/call.dart';
import '../services/native_alarm.dart';
import '../i18n.dart';
import '../ui.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> call;
  const IncomingCallScreen({super.key, required this.call});
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late final CallSession _s = CallSession(Supabase.instance.client, widget.call['id'], _onState);
  String _state = 'ringing';
  bool _muted = false;
  Timer? _timer;
  int _secs = 0;

  static Map<String, String> get _labels => {
        'ringing': tr('مكالمة صوتية واردة', 'Incoming voice call'),
        'connecting': tr('جارٍ الاتصال…', 'Connecting…'),
        'connected': tr('متصل', 'Connected'),
        'failed': tr('تعذّر الاتصال', 'Couldn’t connect'),
        'ended': tr('انتهت المكالمة', 'Call ended'),
        'rejected': tr('رُفضت المكالمة', 'Call declined'),
      };

  Timer? _watch;

  @override
  void initState() {
    super.initState();
    NativeAlarm.startRinging(widget.call['id'] as String);
    // ORT may hang up or the call may time out before the employee answers → close the screen
    _watch = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_state != 'ringing') return;
      try {
        final r = await Supabase.instance.client.from('calls').select('status').eq('id', widget.call['id']).maybeSingle();
        if (r == null || r['status'] != 'ringing') {
          await NativeAlarm.stopRinging();
          _onState('ended');
        }
      } catch (_) {}
    });
  }

  void _onState(String s) {
    if (!mounted) return;
    setState(() => _state = s);
    if (s == 'connected') {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _secs++));
    }
    if (s == 'ended' || s == 'rejected' || s == 'failed') {
      _timer?.cancel();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch?.cancel();
    NativeAlarm.stopRinging();
    if (_state == 'connected' || _state == 'connecting') _s.end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _state == 'ringing';
    final mm = (_secs ~/ 60).toString().padLeft(2, '0'), ss = (_secs % 60).toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: C.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const CircleAvatar(radius: 52, backgroundColor: C.yellow, child: Icon(Icons.support_agent, size: 56, color: C.navy)),
            const SizedBox(height: 20),
            Text(widget.call['caller_name'] ?? 'ORT · 160', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Text(_state == 'connected' ? '$mm:$ss' : _labels[_state] ?? _state, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const Spacer(),
            if (ringing)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(Icons.call_end, const Color(0xFFEF4444), tr('رفض', 'Decline'), () => _s.reject()),
                _round(Icons.call, const Color(0xFF22C55E), tr('رد', 'Answer'), () => _s.accept().catchError((_) => _onState('failed'))),
              ])
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(_muted ? Icons.mic_off : Icons.mic, Colors.white24, _muted ? tr('إلغاء الكتم', 'Unmute') : tr('كتم', 'Mute'), () {
                  setState(() => _muted = !_muted);
                  _s.mute(_muted);
                }),
                _round(Icons.call_end, const Color(0xFFEF4444), tr('إنهاء', 'Hang up'), () => _s.end()),
              ]),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _round(IconData i, Color c, String label, VoidCallback onTap) => Column(children: [
        FloatingActionButton.large(heroTag: label, backgroundColor: c, onPressed: onTap, child: Icon(i, color: Colors.white)),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ]);
}
