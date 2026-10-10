import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    this.color = SemaColors.forest,
    this.height = 18,
    this.barCount = 22,
    this.seed = 7,
  });

  final Color color;
  final double height;
  final int barCount;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WavePainter(
          color: color, count: barCount, seed: seed,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.color, required this.count, required this.seed,
  });
  final Color color;
  final int count;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final stride = size.width / count;
    for (int i = 0; i < count; i++) {
      final t = i / count;
      final base = math.sin(t * math.pi * 2) * 0.4 + 0.55;
      final s = (base * 0.55 + r.nextDouble() * 0.45).clamp(0.18, 1.0);
      final h = size.height * s;
      final x = i * stride + stride / 2;
      final y = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y), Offset(x, y + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.color != color || old.count != count || old.seed != seed;
}
