import 'package:flutter/material.dart';

/// Paleta Octano / Fuel & Go+ (misma del tablero de mockups).
class C {
  C._();
  static const ink = Color(0xFF15191B);
  static const inkDeep = Color(0xFF0E1214);
  static const surface = Color(0xFF1B2124);
  static const surfaceHi = Color(0xFF222A2C);
  static const line = Color(0xFF2A3231);
  static const green = Color(0xFF1FC16B);
  static const greenDim = Color(0xFF14603A);
  static const amber = Color(0xFFF5A524);
  static const red = Color(0xFFE5484D);
  static const bone = Color(0xFFF3F1EA);
  static const muted = Color(0xFF9AA7A3);
  static const mutedDim = Color(0xFF6B7775);
}

class Gap {
  Gap._();
  static const h4 = SizedBox(height: 4);
  static const h8 = SizedBox(height: 8);
  static const h10 = SizedBox(height: 10);
  static const h12 = SizedBox(height: 12);
  static const h16 = SizedBox(height: 16);
  static const h24 = SizedBox(height: 24);
  static const h32 = SizedBox(height: 32);
  static const w4 = SizedBox(width: 4);
  static const w8 = SizedBox(width: 8);
  static const w12 = SizedBox(width: 12);
  static const w16 = SizedBox(width: 16);
}

class Radii {
  Radii._();
  static const card = BorderRadius.all(Radius.circular(18));
  static const field = BorderRadius.all(Radius.circular(14));
  static const pill = BorderRadius.all(Radius.circular(999));
}
