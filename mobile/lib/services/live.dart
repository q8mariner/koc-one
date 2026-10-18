// Live safety service: boundary detection (sector › zone › building), targeted alarms over Supabase
// Realtime, acknowledgments, and incoming ORT voice calls.
// Location runs as an Android foreground service (persistent notification) so alarms arrive while the
// phone is locked. Position is sent to the server only on boundary transitions and during an active alarm.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../geo.dart';
import '../i18n.dart';
import 'native_alarm.dart';
import 'notify.dart';

final sb = Supabase.instance.client;

class LiveService extends ChangeNotifier {
  static final LiveService I = LiveService._();
  LiveService._();

  Map<String, dynamic>? me;
  Areas areas = Areas([], [], []);
  Position3 where = const Position3(null, null, null);
  Position? pos;
  String gpsState = tr('جارٍ تحديد الموقع…', 'Locating…');

  final List<Map<String, dynamic>> inbox = []; // alarms/messages that reached me
  final Map<String, String> myStatus = {}; // alarmId → status
  final Set<String> _handled = {};
  List<Map<String, dynamic>> activeAlarms = [];

  /// Called by the UI layer when an alarm must be shown full-screen or a call is ringing.
  void Function(Map<String, dynamic> alarm)? onAlarm;
  void Function(Map<String, dynamic> call)? onIncomingCall;
  void Function(String alarmId)? onAllClear;

  StreamSubscription<Position>? _posSub;
  int transitions = 0; // bumps on every boundary crossing (the area log listens)
  bool _started = false;

  String get uid => sb.auth.currentUser!.id;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    me = await sb.from('profiles').select().eq('id', uid).single();
    await _loadAreas();
    await _loadHistory();
    _subscribe();
    await _startLocation();
    await sb.from('profiles').update({'online': true, 'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
    notifyListeners();
  }

  Future<void> stop() async {
    _started = false;
    await _posSub?.cancel();
    _poll?.cancel();
    await NativeAlarm.stop();
    for (final c in _channels) {
      await sb.removeChannel(c);
    }
    _channels.clear();
    try {
      await sb.from('profiles').update({'online': false}).eq('id', uid);
    } catch (_) {}
    inbox.clear();
    myStatus.clear();
    _handled.clear();
  }

  Future<void> _loadAreas() async {
    final r = await Future.wait([
      sb.from('sectors').select(),
      sb.from('zones').select(),
      sb.from('buildings').select(),
    ]);
    areas = Areas(List<Map<String, dynamic>>.from(r[0]), List<Map<String, dynamic>>.from(r[1]), List<Map<String, dynamic>>.from(r[2]));
  }

  Future<void> _loadHistory() async {
    final acks = await sb.from('alarm_acks').select('status, alarm_id, alarms(*)').eq('user_id', uid).order('updated_at', ascending: false).limit(30);
    for (final a in acks) {
      final al = a['alarms'];
      if (al is Map) {
        inbox.add(Map<String, dynamic>.from(al));
        myStatus[al['id']] = a['status'];
        _handled.add(al['id']);
      }
    }
    final act = await sb.from('alarms').select().eq('active', true).order('created_at', ascending: false);
    activeAlarms = List<Map<String, dynamic>>.from(act);
  }

  final List<RealtimeChannel> _channels = [];
  Timer? _poll;

  void _subscribe() {
    // Separate channels: a problem with one subscription can never block alarm delivery.
    _channels.add(_watch(sb.channel('alarms-$uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'alarms',
            callback: (p) => _onAlarm(Map<String, dynamic>.from(p.newRecord)))
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'alarms',
            callback: (p) => _onAlarmUpdate(Map<String, dynamic>.from(p.newRecord)))));
    _channels.add(_watch(sb.channel('calls-$uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'callee_id', value: uid),
            callback: (p) {
              final c = Map<String, dynamic>.from(p.newRecord);
              if (c['status'] != 'ringing') return;
              Notify.incomingCall(c['id'], c['caller_name'] ?? 'ORT · 160');
              onIncomingCall?.call(c);
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'callee_id', value: uid),
            callback: (p) {
              final c = p.newRecord;
              if (c['status'] != 'ringing') Notify.cancelCall(c['id']);
            })));
    _channels.add(_watch(sb.channel('me-$uid').onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'profiles',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: uid),
        callback: (p) {
          me = {...?me, ...Map<String, dynamic>.from(p.newRecord)};
          notifyListeners();
        })));
    _channels.add(_watch(sb.channel('areas-$uid')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'sectors', callback: (_) => _reloadAreas())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'zones', callback: (_) => _reloadAreas())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'buildings', callback: (_) => _reloadAreas())));
    // Safety net: re-check active alarms every 15 s in case a realtime event was missed
    // (network change, Doze, server reconnect).
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollAlarms();
      _insist();
    });
  }

  String? _soundingId; // alarm whose tone is playing

  /// Mandatory response: while an active evacuation/emergency alarm for me has no status,
  /// keep pulling the alarm screen to the front and keep the tone going.
  void _insist() {
    for (final a in activeAlarms) {
      final id = a['id'] as String;
      final st = myStatus[id];
      if (!_handled.contains(id) || a['kind'] == 'message' || a['kind'] == 'signal3') continue;
      if (st != null && st != 'received') continue;
      if (_soundingId != id) {
        _soundingId = id;
        NativeAlarm.start(a['kind'] as String);
      } else {
        NativeAlarm.bringToFront();
      }
      onAlarm?.call(a);
      return;
    }
  }

  RealtimeChannel _watch(RealtimeChannel ch) {
    ch.subscribe((status, err) {
      if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('realtime ${ch.topic}: $status $err');
        _pollAlarms();
      }
    });
    return ch;
  }

  void _onAlarmUpdate(Map<String, dynamic> a) {
    activeAlarms.removeWhere((x) => x['id'] == a['id']);
    if (a['active'] == true) activeAlarms.insert(0, a);
    if (a['active'] == false) {
      Notify.cancelAlarm(a['id']);
      if (_soundingId == a['id']) {
        _soundingId = null;
        NativeAlarm.stop();
      }
      onAllClear?.call(a['id']);
    }
    notifyListeners();
  }

  Future<void> _pollAlarms() async {
    if (!_started) return;
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String();
      final rows = await sb.from('alarms').select().or('active.eq.true,created_at.gte.$since').order('created_at');
      final list = List<Map<String, dynamic>>.from(rows);
      final activeIds = list.where((a) => a['active'] == true).map((a) => a['id']).toSet();
      for (final gone in activeAlarms.where((a) => !activeIds.contains(a['id'])).toList()) {
        _onAlarmUpdate({...gone, 'active': false});
      }
      for (final a in list) {
        if (a['active'] == true && !activeAlarms.any((x) => x['id'] == a['id'])) activeAlarms.insert(0, a);
        _deliverIfApplies(a);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _reloadAreas() async {
    await _loadAreas();
    if (pos != null) _onPosition(pos!);
  }

  /// Does this alarm target me, given where I am right now?
  bool applies(Map<String, dynamic> a) {
    switch (a['scope']) {
      case 'employee':
        return a['target_id'] == uid;
      case 'all':
        return where.insideAny;
      case 'sector':
        return where.sectorId != null && where.sectorId == a['target_id'];
      case 'zone':
        return where.zoneId != null && where.zoneId == a['target_id'];
      case 'building':
        return where.buildingId != null && where.buildingId == a['target_id'];
    }
    return false;
  }

  void _onAlarm(Map<String, dynamic> a) {
    if (a['active'] == true) {
      activeAlarms.removeWhere((x) => x['id'] == a['id']);
      activeAlarms.insert(0, a);
    }
    _deliverIfApplies(a);
    notifyListeners();
  }

  void _deliverIfApplies(Map<String, dynamic> a) {
    final id = a['id'] as String;
    if (_handled.contains(id) || !applies(a)) return;
    _handled.add(id);
    inbox.insert(0, a);
    final kind = a['kind'] as String;
    final drill = a['drill'] == true ? tr(' (تمرين)', ' (drill)') : '';
    Notify.alarm(id, kind, '${alarmTitle(a)}$drill', '${areaLabel()}\n${alarmBody(a)}');
    if (kind != 'message') {
      ack(id, 'received');
      _soundingId = id;
      NativeAlarm.start(kind, loop: kind != 'signal3');
      // Signal 3 (all clear) also opens its own green screen with the steady tone,
      // replacing any open emergency/evacuation screen.
      onAlarm?.call(a);
    }
    notifyListeners();
  }

  Future<void> ack(String alarmId, String status) async {
    if (status != 'received' || !myStatus.containsKey(alarmId)) myStatus[alarmId] = status;
    notifyListeners();
    if (status != 'received') {
      await Notify.cancelAlarm(alarmId);
      if (_soundingId == alarmId) {
        _soundingId = null;
        await NativeAlarm.stop();
      }
    }
    try {
      await sb.from('alarm_acks').upsert({
        'alarm_id': alarmId,
        'user_id': uid,
        'status': status,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'building_id': where.buildingId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ack failed: $e');
    }
  }

  // ───── Location / boundaries ─────
  Future<bool> locationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      gpsState = tr('خدمة الموقع مغلقة', 'Location services are off');
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      gpsState = tr('لم يُمنح إذن الموقع', 'Location permission not granted');
      return false;
    }
    return true;
  }

  Future<void> _startLocation() async {
    if (!await locationReady()) {
      notifyListeners();
      return;
    }
    try {
      _onPosition(await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)));
    } catch (_) {}
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 20),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: tr('ONE · الحماية مفعّلة', 'ONE · protection on'),
        notificationText: tr('يستقبل إنذارات موقعك وتنبيهات الحدود', 'Receiving alarms and boundary alerts for your location'),
        enableWakeLock: true,
      ),
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {
      gpsState = tr('تعذّر قراءة الموقع', 'Couldn’t read location');
      notifyListeners();
    });
  }

  void _onPosition(Position p) {
    pos = p;
    gpsState = tr('GPS · دقة ${p.accuracy.round()} م', 'GPS · accuracy ${p.accuracy.round()} m');
    final next = areas.locate(p.latitude, p.longitude);
    final prev = where;
    final changed = next.sectorId != prev.sectorId || next.zoneId != prev.zoneId || next.buildingId != prev.buildingId;
    where = next;
    if (changed) {
      _transition('sector', prev.sectorId, next.sectorId, areas.sector);
      _transition('zone', prev.zoneId, next.zoneId, areas.zone);
      _transition('building', prev.buildingId, next.buildingId, areas.building);
      _pushPosition();
      // alarms already active for an area I just entered
      for (final a in List<Map<String, dynamic>>.from(activeAlarms)) {
        _deliverIfApplies(a);
      }
    } else if (activeAlarms.any((a) => _handled.contains(a['id']))) {
      _pushPosition(); // live location only during an incident
    }
    notifyListeners();
  }

  void _transition(String type, String? from, String? to, Map<String, dynamic>? Function(String?) lookup) {
    if (from == to) return;
    if (from != null) {
      _logEvent(type, from, 'exit');
      final a = lookup(from);
      if (a != null && type != 'building') Notify.message('exit-$from', tr('غادرت حدود ', 'You left ') + '${a['name']}', tr('لن تصلك إنذارات هذه المنطقة حتى تعود إليها.', 'You won’t get this area’s alarms until you return.'));
    }
    if (to != null) {
      _logEvent(type, to, 'enter');
      final a = lookup(to);
      if (a != null) {
        final cls = type == 'zone' ? _clsLabel(a['classification']) : '';
        final msg = (a['entry_message'] as String?)?.trim();
        Notify.message('enter-$to', tr('دخلت حدود ', 'You entered ') + '${a['name']}$cls',
            (msg == null || msg.isEmpty) ? tr('تصلك إنذارات هذه المنطقة ما دمت داخلها.', 'You’ll get this area’s alarms while you are inside it.') : msg);
      }
    }
  }

  static String _clsLabel(dynamic c) => switch (c) { 'zone2' => ' · Zone 2', 'zone1' => ' · Zone 1', 'zone0' => ' · Zone 0', _ => '' };

  Future<void> _logEvent(String type, String id, String ev) async {
    try {
      await sb.from('geofence_events').insert({'user_id': uid, 'area_type': type, 'area_id': id, 'event': ev});
    } catch (_) {}
    transitions++;
    notifyListeners();
  }

  /// Name of a sector / zone / building for the area log.
  String? areaName(String type, String? id) => switch (type) {
        'sector' => areas.sector(id)?['name'],
        'zone' => areas.zone(id)?['name'],
        'building' => areas.building(id)?['name'],
        _ => null,
      };

  Future<void> _pushPosition() async {
    try {
      await sb.from('profiles').update({
        'cur_sector_id': where.sectorId,
        'cur_zone_id': where.zoneId,
        'cur_building_id': where.buildingId,
        'last_lat': pos?.latitude,
        'last_lng': pos?.longitude,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
        'online': true,
      }).eq('id', uid);
    } catch (_) {}
  }

  String areaLabel() {
    final parts = <String>[
      if (areas.sector(where.sectorId) != null) areas.sector(where.sectorId)!['name'],
      if (areas.zone(where.zoneId) != null) areas.zone(where.zoneId)!['name'],
      if (areas.building(where.buildingId) != null) areas.building(where.buildingId)!['name'],
    ];
    return parts.isEmpty ? tr('خارج حدود المناطق', 'Outside all areas') : parts.join(' › ');
  }

  String? musterPoint() => areas.building(where.buildingId)?['muster_point'];
  String? zoneClass() => areas.zone(where.zoneId)?['classification'];
}
