import 'package:flutter/material.dart';

ThemeData gruvboxTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = Color(dark ? 0xff282828 : 0xfffbf1c7);
  final foreground = Color(dark ? 0xffebdbb2 : 0xff3c3836);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xffb8bb26),
        brightness: brightness,
      ).copyWith(
        surface: Color(dark ? 0xff3c3836 : 0xffebdbb2),
        onSurface: foreground,
        onSurfaceVariant: Color(dark ? 0xffa89984 : 0xff665c54),
        primary: Color(dark ? 0xffb8bb26 : 0xff79740e),
        onPrimary: Color(dark ? 0xff282828 : 0xfffbf1c7),
        secondary: Color(dark ? 0xff83a598 : 0xff076678),
        tertiary: Color(dark ? 0xffd3869b : 0xff8f3f71),
        error: Color(dark ? 0xfffb4934 : 0xff9d0006),
      );
  final base = ThemeData(
    brightness: brightness,
    fontFamily: 'NunitoSans',
  ).textTheme.apply(bodyColor: foreground, displayColor: foreground);
  final headings = base.apply(fontFamily: 'Nunito');
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NunitoSans',
    textTheme: base.copyWith(
      displayLarge: headings.displayLarge,
      displayMedium: headings.displayMedium,
      displaySmall: headings.displaySmall,
      headlineLarge: headings.headlineLarge,
      headlineMedium: headings.headlineMedium,
      headlineSmall: headings.headlineSmall,
      titleLarge: headings.titleLarge,
      titleMedium: headings.titleMedium,
      titleSmall: headings.titleSmall,
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
