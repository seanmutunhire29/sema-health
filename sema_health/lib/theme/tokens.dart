import 'package:flutter/material.dart';

/// Sema design tokens — Apple/Airbnb/Uber DNA.
/// Neutral-first palette, considered greens for the brand,
/// coffee for accent. Tight, restrained, premium.
class SemaColors {
  SemaColors._();

  // Surfaces — true neutrals, almost imperceptibly warm.
  // Card/panel sit just one notch off pure white so chips and avatars don't
  // read as "a second white" against the page bg.
  static const bg = Color(0xFFFFFFFF);
  static const panel = Color(0xFFF8F7F4);
  static const card = Color(0xFFF5F3EE);
  static const cardSoft = Color(0xFFFBFAF6);

  // Brand greens
  static const forest = Color(0xFF2A4A3D);
  static const forestDeep = Color(0xFF1A2F26);
  static const forestSoft = Color(0xFF3F6053);
  static const olive = Color(0xFF7A8F6E);
  static const oliveSoft = Color(0xFFC8D2BC);

  // Coffee accent
  static const coffee = Color(0xFF5C3A2E);
  static const coffeeSoft = Color(0xFFE8DDD3);

  // Status
  static const online = Color(0xFF4FA86E);
  static const danger = Color(0xFFC8553D);
  static const star = Color(0xFFE0B43A);

  // Text — true black for that Apple/Airbnb premium feel
  static const ink = Color(0xFF111111);
  static const inkMid = Color(0xFF555555);
  static const inkMuted = Color(0xFF8A8A8A);
  static const inkSoft = Color(0xFFB8B8B8);

  // Lines
  static const hairline = Color(0xFFE8E5DD);
  static const hairlineSoft = Color(0xFFF0EDE6);

  /// Award-winning pastel accent set — low saturation, equal lightness.
  /// Each surface comes paired with an "ink" tone deep enough for type/icons
  /// to clear AA contrast on the matching surface.
  static const blush      = Color(0xFFF0D4CE); // dusty rose
  static const blushInk   = Color(0xFF7A4A40);
  static const butter     = Color(0xFFF2E2A8); // soft cream yellow
  static const butterInk  = Color(0xFF6E5A1F);
  static const mint       = Color(0xFFC9D7BC); // sage green
  static const mintInk    = Color(0xFF3F5A36);
  static const lilac      = Color(0xFFD8D0E8); // lavender
  static const lilacInk   = Color(0xFF4F4276);
  static const sand       = Color(0xFFE5D7C0); // warm sand
  static const sandInk    = Color(0xFF6B4F2E);
  static const sky        = Color(0xFFC9D6E0); // dusty sky blue
  static const skyInk     = Color(0xFF3B5066);
}

/// Paired surface + ink for accent usage — pass into tiles, chips, avatars.
class SemaAccent {
  const SemaAccent(this.surface, this.ink);
  final Color surface;
  final Color ink;

  static const blush  = SemaAccent(SemaColors.blush,  SemaColors.blushInk);
  static const butter = SemaAccent(SemaColors.butter, SemaColors.butterInk);
  static const mint   = SemaAccent(SemaColors.mint,   SemaColors.mintInk);
  static const lilac  = SemaAccent(SemaColors.lilac,  SemaColors.lilacInk);
  static const sand   = SemaAccent(SemaColors.sand,   SemaColors.sandInk);
  static const sky    = SemaAccent(SemaColors.sky,    SemaColors.skyInk);

  /// Cycle through accents for list items so each gets its own hue.
  static const cycle = <SemaAccent>[mint, blush, butter, lilac, sand, sky];
}

class SemaSpacing {
  SemaSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 40;
}

class SemaRadii {
  SemaRadii._();
  static const double s = 12;
  static const double m = 16;
  static const double l = 22;
  static const double xl = 28;
  static const double pill = 999;
}
