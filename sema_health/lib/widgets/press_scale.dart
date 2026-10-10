import 'package:flutter/material.dart';

/// Subtle press-down feedback (Apple-style). Wraps any child and scales it
/// to ~0.98 on tap. No splash, no ripple.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.98,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
