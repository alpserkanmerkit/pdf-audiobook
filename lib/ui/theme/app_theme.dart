import 'package:flutter/material.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.glass,
    required this.border,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accent2,
    required this.accentSoft,
    required this.shadow,
    required this.spot,
  });

  factory AppPalette.fromPalette(Palette p) => AppPalette(
    bg: p.bg,
    bg2: p.bg2,
    surface: p.surface,
    surface2: p.surface2,
    glass: p.glass,
    border: p.border,
    text: p.text,
    text2: p.text2,
    text3: p.text3,
    accent: p.accent,
    accent2: p.accent2,
    accentSoft: p.accentSoft,
    shadow: p.shadow,
    spot: p.spot,
  );

  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surface2;
  final Color glass;
  final Color border;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accent2;
  final Color accentSoft;
  final Color shadow;
  final Color spot;

  @override
  AppPalette copyWith({
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? glass,
    Color? border,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accent2,
    Color? accentSoft,
    Color? shadow,
    Color? spot,
  }) => AppPalette(
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    glass: glass ?? this.glass,
    border: border ?? this.border,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    text3: text3 ?? this.text3,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    accentSoft: accentSoft ?? this.accentSoft,
    shadow: shadow ?? this.shadow,
    spot: spot ?? this.spot,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      spot: Color.lerp(spot, other.spot, t)!,
    );
  }
}

ThemeData buildAppTheme(AppSettings s) {
  var p = paletFor(s.theme, s.mode);
  if (s.highContrast) {
    p = applyHighContrast(p, s.mode);
  }
  final brightness = s.mode == AppMode.dark
      ? Brightness.dark
      : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.bg,
    fontFamily: s.dyslexia ? 'Lexend' : 'Public Sans',
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ),
    extensions: <ThemeExtension<dynamic>>[AppPalette.fromPalette(p)],
  );
}

/// R6: Serif display (heading) family — switches to Lexend in dyslexia mode.
/// Hard-coded 'Libre Caslon *' literals on screens were overriding the font swap in
/// buildAppTheme; serif usage must go through these tokens.
String serifDisplayFamily(AppSettings s) =>
    s.dyslexia ? 'Lexend' : 'Libre Caslon Display';

/// R6: Serif body/text family — switches to Lexend in dyslexia mode.
String serifTextFamily(AppSettings s) =>
    s.dyslexia ? 'Lexend' : 'Libre Caslon Text';
