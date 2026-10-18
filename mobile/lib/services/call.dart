// Callee side of an ORT voice call (WebRTC audio, Supabase Realtime broadcast signalling).
// Protocol: callee → 'ready' · ORT → 'offer' · callee → 'answer' · both → 'ice' · either → 'hangup'.
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'notify.dart';

class CallSession {
  final String callId;
  final SupabaseClient sb;
  final void Function(String state) onState;
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  RealtimeChannel? _ch;
  final List<RTCIceCandidate> _pending = [];
  bool _remoteSet = false, _closed = false;

  CallSession(this.sb, this.callId, this.onState);

  Map<String, dynamic> _body(Map<String, dynamic> m) =>
      m['payload'] is Map ? Map<String, dynamic>.from(m['payload'] as Map) : m;

  Future<void> accept() async {
    await Notify.cancelCall(callId);
    onState('connecting');
    _mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _pc = await createPeerConnection({'iceServers': iceServers});
    for (final t in _mic!.getAudioTracks()) {
      await _pc!.addTrack(t, _mic!);
    }
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _send('ice', {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onState('connected');
        Helper.setSpeakerphoneOn(true);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onState('failed');
      }
    };

    final ready = Completer<void>();
    _ch = sb.channel('call-$callId')
      ..onBroadcast(event: 'offer', callback: (m) => _onOffer(_body(m)))
      ..onBroadcast(event: 'ice', callback: (m) => _onIce(_body(m)))
      ..onBroadcast(event: 'hangup', callback: (_) => end(notify: false));
    _ch!.subscribe((status, err) {
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    await sb.from('calls').update({'status': 'accepted'}).eq('id', callId);
    _send('ready', {});
  }

  Future<void> _onOffer(Map<String, dynamic> o) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(o['sdp'], o['type']));
    _remoteSet = true;
    for (final c in _pending) {
      await _pc!.addCandidate(c);
    }
    _pending.clear();
    final answer = await _pc!.createAnswer({});
    _send('answer', {'sdp': answer.sdp, 'type': answer.type});
    await _pc!.setLocalDescription(answer);
  }

  Future<void> _onIce(Map<String, dynamic> c) async {
    final cand = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
    if (!_remoteSet) {
      _pending.add(cand);
    } else {
      await _pc?.addCandidate(cand);
    }
  }

  void _send(String event, Map<String, dynamic> payload) {
    _ch?.sendBroadcastMessage(event: event, payload: payload);
  }

  Future<void> reject() async {
    await Notify.cancelCall(callId);
    await sb.from('calls').update({'status': 'rejected', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId);
    onState('rejected');
  }

  void mute(bool on) {
    for (final t in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !on;
    }
  }

  Future<void> end({bool notify = true}) async {
    if (_closed) return;
    _closed = true;
    if (notify) _send('hangup', {});
    try {
      await _pc?.close();
    } catch (_) {}
    for (final t in _mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    if (_ch != null) await sb.removeChannel(_ch!);
    try {
      await sb.from('calls').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId);
    } catch (_) {}
    onState('ended');
  }
}
