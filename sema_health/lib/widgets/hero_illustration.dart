import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Subtle abstract illustration for the hero card.
/// Organic blobs + thin contour lines — premium, restrained,
/// reads at any size. Used as the "image area" of the hero.
class HeroIllustration extends StatelessWidget {
  const HeroIllustration({
    super.key,
    this.background = const Color(0xFF2A4A3D),
    this.accent = const Color(0xFF7A8F6E),
  });
  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeroPainter(bg: background, accent: accent),
      size: Size.infinite,
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter({required this.bg, required this.accent});
  final Color bg;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    // Soft glow blob top-right
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.45),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.15),
          radius: size.width * 0.6,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    // Concentric thin contour rings
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final center = Offset(size.width * 0.82, size.height * 0.5);
    for (int i = 0; i < 5; i++) {
      ring.color = Colors.white.withValues(alpha: 0.06 + i * 0.015);
      canvas.drawCircle(center, 60.0 + i * 28, ring);
    }

    // A flowing organic line (waveform-like)
    final flow = Path();
    final baseY = size.height * 0.62;
    flow.moveTo(-10, baseY);
    final r = math.Random(11);
    for (double x = 0; x <= size.width + 10; x += 8) {
      final t = x / size.width;
      final y = baseY +
          math.sin(t * math.pi * 3.4) * 6 +
          (r.nextDouble() - 0.5) * 1.6;
      flow.lineTo(x, y);
    }
    final flowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(flow, flowPaint);

    // Small dot accents
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.28), 2.5, dot,
    );
    canvas.drawCircle(
      Offset(size.width * 0.55, size.height * 0.18), 1.8,
      Paint()..color = Colors.white.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) =>
      old.bg != bg || old.accent != accent;
}
