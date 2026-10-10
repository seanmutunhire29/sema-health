import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'press_scale.dart';

enum SemaButtonVariant { primary, secondary, ghost }

class SemaButton extends StatelessWidget {
  const SemaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SemaButtonVariant.primary,
    this.icon,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final SemaButtonVariant variant;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _palette();
    return PressScale(
      onTap: onPressed,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SemaRadii.pill),
          border: border,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color, BoxBorder?) _palette() {
    switch (variant) {
      case SemaButtonVariant.primary:
        return (SemaColors.ink, Colors.white, null);
      case SemaButtonVariant.secondary:
        return (SemaColors.card, SemaColors.ink, null);
      case SemaButtonVariant.ghost:
        return (
          Colors.transparent,
          SemaColors.ink,
          Border.all(color: SemaColors.hairline, width: 1),
        );
    }
  }
}
