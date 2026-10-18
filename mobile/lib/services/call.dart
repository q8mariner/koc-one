// Callee side of an ORT voice call (WebRTC audio, Supabase Realtime broadcast signalling).
// Protocol: callee → 'ready' · ORT → 'offer' · callee → 'answer' · both → 'ice' · either → 'hangup'.
// ICE servers (STUN + TURN relay) come from the ice-servers Edge Function so calls connect behind carrier NAT.
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'native_alarm.dart';
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
  Timer? _connectTimeout;

  CallSession(this.sb, this.callId, this.onState);

  Map<String, dynamic> _body(Map<String, dynamic> m) =>
      m['payload'] is Map ? Map<String, dynamic>.from(m['payload'] as Map) : m;

  Future<List<Map<String, dynamic>>> _iceServers() async {
    try {
      final r = await sb.functions.invoke('ice-servers', body: {});
      final d = r.data;
      if (d is Map && d['iceServers'] is List) {
        return (d['iceServers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return iceServers;
  }

  Future<void> accept() async {
    await NativeAlarm.stopRinging();
    await Notify.cancelCall(callId);
    onState('connecting');
    // switch the phone into call mode before media starts (loudspeaker, full call volume)
    await NativeAlarm.callAudioStart();
    final servers = await _iceServers();
    _mic = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': false,
    });
    _pc = await createPeerConnection({'iceServers': servers, 'sdpSemantics': 'unified-plan'});
    for (final t in _mic!.getAudioTracks()) {
      t.enabled = true;
      await _pc!.addTrack(t, _mic!);
    }
    _pc!.onTrack = (e) {
      // make sure the remote voice is played
      e.track.enabled = true;
      Helper.setSpeakerphoneOn(true);
    };
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _send('ice', {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectTimeout?.cancel();
        NativeAlarm.callAudioStart();
        Helper.setSpeakerphoneOn(true);
        onState('connected');
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        end();
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
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (!_closed) {
        end();
        onState('failed');
      }
    });
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
    await NativeAlarm.stopRinging();
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
    _connectTimeout?.cancel();
    await NativeAlarm.stopRinging();
    if (notify) _send('hangup', {});
    try {
      await _pc?.close();
    } catch (_) {}
    for (final t in _mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    if (_ch != null) await sb.removeChannel(_ch!);
    await NativeAlarm.callAudioStop();
    try {
      await sb.from('calls').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId);
    } catch (_) {}
    onState('ended');
  }
}
