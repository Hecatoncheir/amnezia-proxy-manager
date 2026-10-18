import 'package:flutter/material.dart';

ThemeData gruvboxTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = Color(dark ? 0xff282828 : 0xfffbf1c7);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xffb8bb26),
        brightness: brightness,
      ).copyWith(
        surface: background,
        onSurface: Color(dark ? 0xffebdbb2 : 0xff3c3836),
        primary: Color(dark ? 0xffb8bb26 : 0xff79740e),
        onPrimary: Color(dark ? 0xff282828 : 0xfffbf1c7),
        secondary: Color(dark ? 0xff83a598 : 0xff076678),
        error: Color(dark ? 0xfffb4934 : 0xff9d0006),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );
}
