import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'press_scale.dart';

class SemaCard extends StatelessWidget {
  const SemaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SemaSpacing.l),
    this.color = SemaColors.card,
    this.radius = SemaRadii.l,
    this.onTap,
    this.border,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
  final BoxBorder? border;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: child,
    );
    if (onTap == null) return card;
    return PressScale(onTap: onTap, child: card);
  }
}
