import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Tipografía del sistema: Space Grotesk (display), Hanken Grotesk (UI),
/// JetBrains Mono (datos / cifras).
TextStyle display({
  double size = 28,
  FontWeight weight = FontWeight.w600,
  Color color = C.bone,
  double height = 1.1,
  double letterSpacing = -0.4,
}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

TextStyle body({
  double size = 15,
  FontWeight weight = FontWeight.w400,
  Color color = C.bone,
  double height = 1.45,
}) =>
    GoogleFonts.hankenGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

TextStyle mono({
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color color = C.muted,
  double letterSpacing = 0.02,
}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.ink,
    colorScheme: const ColorScheme.dark(
      primary: C.green,
      onPrimary: Color(0xFF0C130F),
      secondary: C.amber,
      surface: C.surface,
      onSurface: C.bone,
      error: C.red,
    ),
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
      bodyColor: C.bone,
      displayColor: C.bone,
    ),
    splashFactory: InkRipple.splashFactory,
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: C.green,
      inactiveTrackColor: C.line,
      thumbColor: C.green,
      overlayColor: const Color(0x221FC16B),
      trackHeight: 6,
    ),
    dividerColor: C.line,
  );
}
