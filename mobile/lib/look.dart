import 'package:flutter/material.dart';

/// Paleta e fonte do app original (app/Talk.cs, classe Look).
class Look {
  static const Color back = Color(0xFF05060A);
  static const Color panel = Color(0xFF090B0F);
  static const Color edge = Color(0xFF343C4A);
  static const Color cyan = Color(0xFF3AD6EB);
  static const Color red = Color(0xFFE82440);
  static const Color yellow = Color(0xFFF4D646);
  static const Color neon = Color(0xFF38B0FF);
  static const Color ink = Color(0xFFE8ECF0);
  static const Color dim = Color(0xFF7A808A);

  static const String mono = 'ShareTechMono';

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: back,
      colorScheme: base.colorScheme.copyWith(
        primary: cyan,
        secondary: neon,
        surface: panel,
        error: red,
        onPrimary: back,
        onSurface: ink,
      ),
      textTheme: base.textTheme.apply(fontFamily: mono, bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: back,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: TextStyle(fontFamily: mono, fontSize: 18, color: cyan, letterSpacing: 2),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: TextStyle(color: dim, fontFamily: mono),
        labelStyle: TextStyle(color: dim, fontFamily: mono),
        border: OutlineInputBorder(borderSide: BorderSide(color: edge)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: edge)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: cyan)),
      ),
    );
  }
}
