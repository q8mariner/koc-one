import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDay(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

double? toD(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const weekNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String fmtNum(double? v) {
  if (v == null) return '–';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

String fmtDate(DateTime? d) => d == null ? '' : '${d.day}/${d.month}/${d.year}';

class OpsMonth {
  final DateTime month;
  final int count;
  OpsMonth(this.month, this.count);
}

class Weather {
  final DateTime day;
  final double? temp, wind;
  final String condition, windDir;
  final int? humidity;
  final List<Tide> tides;
  final String stateDay, stateNight;
  Weather(this.day, this.temp, this.condition, this.wind, this.windDir, this.humidity, this.tides,
      this.stateDay, this.stateNight);

  factory Weather.fromRow(Map<String, dynamic> r) {
    Tide? t(String label, String m, String time) {
      final h = toD(r[m]);
      final tm = (r[time] ?? '').toString();
      if (h == null && tm.isEmpty) return null;
      return Tide(label, h, tm);
    }

    return Weather(
      parseDay(r['day']) ?? DateTime.now(),
      toD(r['temp_c']),
      (r['condition'] ?? 'rain_sun').toString(),
      toD(r['wind_kmh']),
      (r['wind_dir'] ?? '').toString(),
      r['humidity'] == null ? null : (r['humidity'] as num).toInt(),
      [
        t('1st High Tide', 'high1_m', 'high1_time'),
        t('2nd High Tide', 'high2_m', 'high2_time'),
        t('1st Low Tide', 'low1_m', 'low1_time'),
        t('2nd Low Tide', 'low2_m', 'low2_time'),
      ].whereType<Tide>().toList(),
      (r['state_day'] ?? '').toString(),
      (r['state_night'] ?? '').toString(),
    );
  }
}

class Tide {
  final String label, time;
  final double? height;
  Tide(this.label, this.height, this.time);
}

class News {
  final String id, title, body, unit, image;
  final DateTime? date;
  News(this.id, this.title, this.body, this.unit, this.image, this.date);
  factory News.fromRow(Map<String, dynamic> r) => News(
        r['id'].toString(),
        (r['title'] ?? '').toString(),
        (r['body'] ?? '').toString(),
        (r['unit'] ?? '').toString(),
        (r['image_url'] ?? '').toString(),
        parseDay(r['published_on']),
      );
}

class DutyPerson {
  final String shift, role, name;
  DutyPerson(this.shift, this.role, this.name);
}

class Duty {
  final DateTime day;
  final String morning, night;
  final List<DutyPerson> people;
  Duty(this.day, this.morning, this.night, this.people);
  factory Duty.fromRow(Map<String, dynamic> r) {
    final raw = r['people'];
    final list = <DutyPerson>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          list.add(DutyPerson((p['shift'] ?? 'M').toString(), (p['role'] ?? '').toString(),
              (p['name'] ?? '').toString()));
        }
      }
    }
    return Duty(parseDay(r['day'])!, (r['morning_shift'] ?? '').toString(),
        (r['night_shift'] ?? '').toString(), list);
  }
}

class Contact {
  final String name, role, phone;
  Contact(this.name, this.role, this.phone);
}

class Repo {
  static Future<List<OpsMonth>> operations() async {
    final rows = await db.from('operations').select().order('month');
    return [
      for (final r in rows)
        OpsMonth(parseDay(r['month'])!, (r['count'] as num).toInt()),
    ];
  }

  /// Today's forecast first, then the following days. Falls back to the most recent entry.
  static Future<List<Weather>> weather() async {
    final today = ymd(DateTime.now());
    final rows = await db.from('weather').select().gte('day', today).order('day').limit(7);
    if (rows.isNotEmpty) return rows.map(Weather.fromRow).toList();
    final last = await db.from('weather').select().order('day', ascending: false).limit(1);
    return last.map(Weather.fromRow).toList();
  }

  static Future<List<News>> news() async {
    final rows = await db
        .from('news')
        .select()
        .order('published_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(News.fromRow).toList();
  }

  static Future<Map<String, Duty>> duty(DateTime from, DateTime to) async {
    final rows = await db.from('duty').select().gte('day', ymd(from)).lte('day', ymd(to));
    return {for (final r in rows) ymd(parseDay(r['day'])!): Duty.fromRow(r)};
  }

  static Future<List<Contact>> contacts() async {
    final rows = await db.from('contacts').select().order('sort').order('name');
    return [
      for (final r in rows)
        Contact((r['name'] ?? '').toString(), (r['role'] ?? '').toString(), (r['phone'] ?? '').toString()),
    ];
  }
}
