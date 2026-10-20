import 'dart:math' as math;
import 'package:flutter/material.dart';

const kBlue = Color(0xFF1F5FFF);
const kBlueDeep = Color(0xFF0E3FD0);
const kCard = Color(0xD9CADCFF); // frosted light blue
const kInk = Color(0xFF1E1E24);
const kCyan = Color(0xFF14B4E6);
const kSerif = 'serif';

/// Frosted card used on every screen.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x22000030), blurRadius: 18, offset: Offset(0, 6))],
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}

class PageTitle extends StatelessWidget {
  final String text;
  const PageTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: kSerif,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x55000000), blurRadius: 8)])),
      );
}

/// Loads data and shows spinner / retry; pull-to-refresh is handled by callers.
class Loader<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  const Loader({super.key, required this.future, required this.builder, required this.onRetry});

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Glass(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_rounded, color: kBlue, size: 40),
                  const SizedBox(height: 8),
                  const Text('Could not load data.\nCheck your connection.',
                      textAlign: TextAlign.center, style: TextStyle(color: kInk, fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kBlue),
                      onPressed: onRetry,
                      child: const Text('Try again')),
                ]),
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          return builder(s.data as T);
        },
      );
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Glass(
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kInk, fontSize: 16)));
}

/// Smooth line chart (Catmull-Rom) like the "Total Of Operations" card.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  const Sparkline(this.values, {super.key, this.height = 110});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values)));
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  _SparkPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final mx = v.reduce(math.max), mn = v.reduce(math.min);
    final range = (mx - mn) == 0 ? 1 : (mx - mn);
    final pts = <Offset>[
      for (var i = 0; i < v.length; i++)
        Offset(size.width * i / (v.length - 1), size.height - 4 - (v[i] - mn) / range * (size.height - 8)),
    ];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i], p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = kBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.v != v;
}

/// Line-art weather icon: sun / cloud / rain / wind combinations.
/// condition: sunny, partly_cloudy, cloudy, rain, rain_sun, storm, dust, fog
class WeatherIcon extends StatelessWidget {
  final String condition;
  final double size;
  const WeatherIcon(this.condition, {super.key, this.size = 110});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _WxPainter(condition)));
}

class _WxPainter extends CustomPainter {
  final String c;
  _WxPainter(this.c);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final stroke = Paint()
      ..color = kBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final sun = c == 'sunny' || c == 'partly_cloudy' || c == 'rain_sun';
    final cloud = c != 'sunny' && c != 'dust';
    final rain = c == 'rain' || c == 'rain_sun' || c == 'storm';

    final cloudPath = Path.combine(
      PathOperation.union,
      Path.combine(
        PathOperation.union,
        Path()..addOval(Rect.fromCircle(center: Offset(w * 0.30, w * 0.50), radius: w * 0.16)),
        Path()..addOval(Rect.fromCircle(center: Offset(w * 0.50, w * 0.42), radius: w * 0.21)),
      ),
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(w * 0.08, w * 0.48, w * 0.80, w * 0.68), Radius.circular(w * 0.10))),
    );

    if (sun) {
      final center = cloud ? Offset(w * 0.66, w * 0.34) : Offset(w * 0.5, w * 0.5);
      final r = cloud ? w * 0.15 : w * 0.2;
      canvas.save();
      if (cloud) {
        canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & s), cloudPath));
      }
      canvas.drawCircle(center, r, stroke);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(center + d * (r + w * 0.06), center + d * (r + w * 0.12), stroke);
      }
      canvas.restore();
    }
    if (cloud) {
      canvas.drawPath(cloudPath, stroke);
    }
    if (rain) {
      for (var row = 0; row < 2; row++) {
        for (var i = 0; i < 4 - row; i++) {
          final x = w * (0.26 + i * 0.13 + row * 0.04);
          final y = w * (0.76 + row * 0.11);
          canvas.drawLine(Offset(x, y), Offset(x - w * 0.03, y + w * 0.06), stroke);
        }
      }
    }
    if (c == 'storm') {
      final bolt = Path()
        ..moveTo(w * 0.52, w * 0.70)
        ..lineTo(w * 0.44, w * 0.84)
        ..lineTo(w * 0.53, w * 0.84)
        ..lineTo(w * 0.46, w * 0.98);
      canvas.drawPath(bolt, stroke);
    }
    if (c == 'dust' || c == 'fog') {
      for (var i = 0; i < 3; i++) {
        final y = w * (c == 'fog' ? 0.78 : 0.40) + i * w * 0.13;
        canvas.drawLine(Offset(w * (0.12 + i * 0.05), y), Offset(w * (0.82 - i * 0.04), y), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_WxPainter old) => old.c != c;
}

double dirAngle(String d) {
  const m = {
    'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5, 'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
    'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5, 'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
  };
  final k = d.trim().toUpperCase();
  final v = m[k] ?? double.tryParse(k) ?? 0;
  return v.toDouble() * math.pi / 180;
}

/// Wind / Direction / Humidity row.
class WindRow extends StatelessWidget {
  final double? wind;
  final String dir;
  final int? humidity;
  final double scale;
  const WindRow({super.key, this.wind, required this.dir, this.humidity, this.scale = 1});

  Widget _cell(Widget icon, String label, String value) => Expanded(
        child: Column(children: [
          SizedBox(height: 30 * scale, child: Center(child: icon)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 17 * scale, color: kInk, letterSpacing: 0.8)),
          Text(value, style: TextStyle(fontSize: 17 * scale, color: kBlue, letterSpacing: 0.8)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Row(children: [
        _cell(Icon(Icons.air_rounded, color: kBlue, size: 30 * scale), 'Wind',
            wind == null ? '–' : '${fmtNumD(wind)} km/h'),
        _cell(
            Transform.rotate(
                angle: dirAngle(dir),
                child: Icon(Icons.navigation_rounded, color: kBlue, size: 28 * scale)),
            'Direction',
            dir.isEmpty ? '–' : dir),
        _cell(Icon(Icons.water_drop_rounded, color: kBlue, size: 28 * scale), 'Humidity',
            humidity == null ? '–' : '$humidity%'),
      ]);
}

String fmtNumD(double? v) =>
    v == null ? '–' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
