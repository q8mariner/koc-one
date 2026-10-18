// Visual language from the proposal: navy + signal-yellow slash, white cards on pale blue-grey,
// civil-defence signal colours. No company name or logo — the mark is "/ONE".
import 'package:flutter/material.dart';

class C {
  static const navy = Color(0xFF2B4C9B);
  static const navyD = Color(0xFF1F3A7A);
  static const yellow = Color(0xFFF5C518);
  static const bg = Color(0xFFF3F6FB);
  static const card = Colors.white;
  static const line = Color(0xFFE1E7F1);
  static const fg = Color(0xFF1E2A44);
  static const muted = Color(0xFF6B7A96);
  static const sig1 = Color(0xFFC62828); // emergency
  static const sig2 = Color(0xFF2A2D34); // evacuation
  static const sig3 = Color(0xFF2E9E5B); // all clear
  static const ok = Color(0xFF2E9E5B);
  static const warn = Color(0xFFE07B29);
  static const bad = Color(0xFFC62828);
  static const sky = Color(0xFF3A8EDB);
}

ThemeData oneTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.navy, primary: C.navy, secondary: C.yellow, surface: C.card, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, foregroundColor: C.navy, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.navy, width: 1.6)),
    ),
    chipTheme: const ChipThemeData(side: BorderSide(color: C.line)),
    textTheme: const TextTheme(bodyMedium: TextStyle(color: C.fg)),
  );
}

/// White card with a hairline border (the proposal's panel style).
class OneCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  const OneCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: color ?? C.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color == null ? C.line : Colors.transparent)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// "/ONE" wordmark.
class Wordmark extends StatelessWidget {
  final double size;
  final Color color;
  const Wordmark({super.key, this.size = 24, this.color = C.navy});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '/', style: TextStyle(color: C.yellow, fontSize: size, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
          TextSpan(text: 'ONE', style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1)),
        ])),
      );
}

/// Section title with the yellow slash, as in the proposal.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Transform(transform: Matrix4.skewX(-0.3), child: Container(width: 6, height: 18, color: C.yellow)),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: C.navy, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      );
}

/// Small tag label (navy/green pill with yellow slash).
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = C.navy});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Transform(transform: Matrix4.skewX(-0.3), child: Container(width: 4, height: 13, color: C.yellow)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

/// Diagonal yellow/white stripes used on hero panels.
class Stripes extends StatelessWidget {
  const Stripes({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _StripesPainter(), size: Size.infinite),
      );
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    void band(double x, double w, Color c) {
      final p = Path()
        ..moveTo(x, s.height)
        ..lineTo(x + w, s.height)
        ..lineTo(x + w + s.height * .45, 0)
        ..lineTo(x + s.height * .45, 0)
        ..close();
      canvas.drawPath(p, Paint()..color = c);
    }

    band(s.width * .62, 46, C.yellow);
    band(s.width * .62 + 62, 14, Colors.white.withValues(alpha: .9));
    band(s.width * .62 + 90, 26, C.yellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
