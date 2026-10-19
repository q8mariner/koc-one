// Live safety service: boundary detection (sector › zone › building), targeted alarms over Supabase
// Realtime, acknowledgments, and incoming ORT voice calls.
// Location runs as an Android foreground service (persistent notification) so alarms arrive while the
// phone is locked. Position is sent live (every ≥5 s) while inside a boundary or during an alarm, and once on leaving; never outside.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await _restoreWhere();
    await _loadAreas();
    await _loadHistory();
    _subscribe();
    await _registerDevice();
    await _startLocation();
    await sb.from('profiles').update({'online': true, 'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
    _heartbeat();
    _beat = Timer.periodic(const Duration(seconds: 60), (_) => _heartbeat());
    notifyListeners();
    _insist(); // alarms the background service already delivered while the app was closed
    _openRingingCall(); // a call the background service is ringing for
  }

  Future<void> _openRingingCall() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(seconds: 70)).toIso8601String();
      final c = await sb.from('calls').select().eq('callee_id', uid).eq('status', 'ringing').gte('created_at', since)
          .order('created_at', ascending: false).limit(1).maybeSingle();
      if (c != null) onIncomingCall?.call(c);
    } catch (_) {}
  }

  /// One registered device per account; the native service uses this token while the app is closed.
  Future<void> _registerDevice() async {
    try {
      final token = await sb.rpc('register_device');
      if (token is String) await NativeAlarm.registerDevice(token);
    } catch (e) {
      debugPrint('register_device failed: $e');
    }
  }

  Future<void> stop() async {
    _started = false;
    await _posSub?.cancel();
    _poll?.cancel();
    _beat?.cancel();
    await NativeAlarm.stop();
    await NativeAlarm.unregisterDevice();
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
  Timer? _beat;

  /// Location-signal heartbeat: ORT sees an employee as "signal lost" after 3 min without one
  /// (phone off, no network) or while GPS is off. The background service sends the same when the app is closed.
  Future<void> _heartbeat() async {
    var gps = false;
    try {
      final perm = await Geolocator.checkPermission();
      gps = await Geolocator.isLocationServiceEnabled() &&
          (perm == LocationPermission.always || perm == LocationPermission.whileInUse);
    } catch (_) {}
    try {
      await sb.rpc('heartbeat', params: {'p_gps': gps});
    } catch (_) {}
  }

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
              NativeAlarm.bringToFront(); // the call screen rings natively (CallKit) over any app
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
        NativeAlarm.start(a['kind'] as String, id: id);
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
      NativeAlarm.start(kind, loop: kind != 'signal3', id: id);
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
    final LocationSettings settings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            activityType: ActivityType.otherNavigation,
            allowBackgroundLocationUpdates: true,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          )
        : AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 5),
      // no second notification: the ONE background service (type "location") keeps GPS alive in the background
    );
    await NativeAlarm.refreshService();
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {
      gpsState = tr('تعذّر قراءة الموقع', 'Couldn’t read location');
      notifyListeners();
    });
  }

  // ── Where I was last time ──
  // The app starts from the last area it reported, so reopening it (or restarting the phone) in the
  // same place sends no "entered" alert; a different place does.
  String get _whereKey => 'one.where.$uid';

  Future<void> _restoreWhere() async {
    String? s, z, b;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_whereKey);
      if (saved != null) {
        final parts = saved.split('|').map((x) => x.isEmpty ? null : x).toList();
        if (parts.length == 3) { s = parts[0]; z = parts[1]; b = parts[2]; }
      } else {
        s = me?['cur_sector_id']; z = me?['cur_zone_id']; b = me?['cur_building_id'];
      }
    } catch (_) {}
    where = Position3(s, z, b);
  }

  Future<void> _saveWhere() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_whereKey, '${where.sectorId ?? ''}|${where.zoneId ?? ''}|${where.buildingId ?? ''}');
    } catch (_) {}
  }

  static bool _same(Position3 a, Position3 b) => a.sectorId == b.sectorId && a.zoneId == b.zoneId && a.buildingId == b.buildingId;

  // A boundary crossing counts only when the fix is precise (≤ 25 m) or two fixes in a row agree,
  // so GPS drift along a boundary doesn't fire enter/exit over and over.
  Position3? _candidate;

  void _onPosition(Position p) {
    pos = p;
    gpsState = tr('GPS · دقة ${p.accuracy.round()} م', 'GPS · accuracy ${p.accuracy.round()} m');
    final next = areas.locate(p.latitude, p.longitude);
    final prev = where;
    var changed = !_same(next, prev);
    if (changed) {
      if (p.accuracy > 100) {
        changed = false; // too vague to decide
      } else if (p.accuracy > 35 && (_candidate == null || !_same(_candidate!, next))) {
        _candidate = next; // wait for a second fix that agrees
        changed = false;
      }
    }
    if (!changed && _same(next, prev)) _candidate = null;
    if (changed) {
      _candidate = null;
      where = next;
      _saveWhere();
      _transition('sector', prev.sectorId, next.sectorId, areas.sector);
      _transition('zone', prev.zoneId, next.zoneId, areas.zone);
      _transition('building', prev.buildingId, next.buildingId, areas.building);
      _pushPosition();
      // alarms already active for an area I just entered
      for (final a in List<Map<String, dynamic>>.from(activeAlarms)) {
        _deliverIfApplies(a);
      }
    } else if (where.insideAny || activeAlarms.any((a) => _handled.contains(a['id']))) {
      // live location for ORT while inside a boundary (and during an incident); never outside
      final now = DateTime.now();
      if (_lastPush == null || now.difference(_lastPush!).inSeconds >= 5) _pushPosition();
    }
    notifyListeners();
  }

  // One alert per area: the same enter/exit alert isn't repeated within 30 minutes.
  final Map<String, int> _alerted = {};

  Future<bool> _shouldAlert(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences? sp;
    try { sp = await SharedPreferences.getInstance(); } catch (_) {}
    final last = _alerted[key] ?? sp?.getInt('one.alert.$uid.$key') ?? 0;
    if (now - last < 30 * 60 * 1000) return false;
    _alerted[key] = now;
    try { await sp?.setInt('one.alert.$uid.$key', now); } catch (_) {}
    return true;
  }

  void _alertOnce(String key, void Function() show) {
    _shouldAlert(key).then((ok) { if (ok) show(); });
  }

  void _transition(String type, String? from, String? to, Map<String, dynamic>? Function(String?) lookup) {
    if (from == to) return;
    if (from != null) {
      _logEvent(type, from, 'exit');
      final a = lookup(from);
      if (a != null && type != 'building') _alertOnce('exit-$from', () => Notify.message('exit-$from', tr('غادرت حدود ', 'You left ') + '${a['name']}', tr('لن تصلك إنذارات هذه المنطقة حتى تعود إليها.', 'You won’t get this area’s alarms until you return.')));
    }
    if (to != null) {
      _logEvent(type, to, 'enter');
      final a = lookup(to);
      if (a != null) {
        final cls = type == 'zone' ? _clsLabel(a['classification']) : '';
        final msg = (a['entry_message'] as String?)?.trim();
        _alertOnce('enter-$to', () => Notify.message('enter-$to', tr('دخلت حدود ', 'You entered ') + '${a['name']}$cls',
            (msg == null || msg.isEmpty) ? tr('تصلك إنذارات هذه المنطقة ما دمت داخلها.', 'You’ll get this area’s alarms while you are inside it.') : msg));
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

  DateTime? _lastPush;

  Future<void> _pushPosition() async {
    _lastPush = DateTime.now();
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
