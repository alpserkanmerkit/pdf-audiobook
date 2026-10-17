import 'dart:ui' show Color;

/// The available theme families.
enum AppTheme { cognac, obsidian }

/// The brightness mode.
enum AppMode { dark, light }

/// A collection of 14 color tokens defining a complete palette.
class Palette {
  const Palette({
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

  /// Primary background.
  final Color bg;

  /// Slightly lighter background (cards, dialogs).
  final Color bg2;

  /// Surface color for elevated elements.
  final Color surface;

  /// Secondary surface (e.g., hovered state).
  final Color surface2;

  /// Translucent glass-like overlay.
  final Color glass;

  /// Subtle border and divider color.
  final Color border;

  /// Primary text color.
  final Color text;

  /// Secondary text (less emphasis).
  final Color text2;

  /// Tertiary text (lowest emphasis, placeholders).
  final Color text3;

  /// Main accent color (highlights, links).
  final Color accent;

  /// Secondary accent (complementary).
  final Color accent2;

  /// Soft transparent accent (used for subtle highlights).
  final Color accentSoft;

  /// Drop shadow color.
  final Color shadow;

  /// Spotlight / selection highlight.
  final Color spot;
}

/// Returns the standard [Palette] for the given [theme] and [mode].
Palette paletFor(AppTheme theme, AppMode mode) {
  switch ((theme, mode)) {
    case (AppTheme.cognac, AppMode.dark):
      return const Palette(
        bg: Color(0xFF15100C),
        bg2: Color(0xFF1F1812),
        surface: Color(0xFF241B14),
        surface2: Color(0xFF2E241B),
        glass: Color.fromARGB(140, 46, 35, 25),
        border: Color.fromARGB(33, 224, 194, 150),
        text: Color(0xFFECE0CE),
        text2: Color(0xFFB7A488),
        text3: Color(0xFF988B75),
        accent: Color(0xFFC99A52),
        accent2: Color(0xFFA86E39),
        accentSoft: Color.fromARGB(41, 201, 154, 82),
        shadow: Color.fromARGB(140, 0, 0, 0),
        spot: Color.fromARGB(51, 201, 154, 82),
      );
    case (AppTheme.cognac, AppMode.light):
      return const Palette(
        bg: Color(0xFFEDE3D1),
        bg2: Color(0xFFF4ECDC),
        surface: Color(0xFFFBF6EC),
        surface2: Color(0xFFFFFEF9),
        glass: Color.fromARGB(168, 255, 250, 240),
        border: Color.fromARGB(41, 96, 66, 34),
        text: Color(0xFF2B1D11),
        text2: Color(0xFF6B563C),
        text3: Color(0xFF76634D),
        accent: Color(0xFF9A6A32),
        accent2: Color(0xFFB6854A),
        accentSoft: Color.fromARGB(36, 154, 106, 50),
        shadow: Color.fromARGB(46, 80, 50, 20),
        spot: Color.fromARGB(36, 154, 106, 50),
      );
    case (AppTheme.obsidian, AppMode.dark):
      return const Palette(
        bg: Color(0xFF0F1012),
        bg2: Color(0xFF16181B),
        surface: Color(0xFF1A1C20),
        surface2: Color(0xFF222529),
        glass: Color.fromARGB(140, 26, 28, 32),
        border: Color.fromARGB(31, 224, 216, 196),
        text: Color(0xFFEAE8E2),
        text2: Color(0xFFA7A49B),
        text3: Color(0xFF8D8B83),
        accent: Color(0xFFD9C59B),
        accent2: Color(0xFFBBA983),
        accentSoft: Color.fromARGB(36, 217, 197, 155),
        shadow: Color.fromARGB(153, 0, 0, 0),
        spot: Color.fromARGB(41, 217, 197, 155),
      );
    case (AppTheme.obsidian, AppMode.light):
      return const Palette(
        bg: Color(0xFFEAEAE7),
        bg2: Color(0xFFF3F3F0),
        surface: Color(0xFFFBFBF8),
        surface2: Color(0xFFFFFFFF),
        glass: Color.fromARGB(168, 252, 252, 249),
        border: Color.fromARGB(33, 40, 40, 44),
        text: Color(0xFF17181B),
        text2: Color(0xFF5B5D62),
        text3: Color(0xFF68696E),
        accent: Color(0xFF937F4F),
        accent2: Color(0xFFA8945F),
        accentSoft: Color.fromARGB(33, 147, 127, 79),
        shadow: Color.fromARGB(36, 20, 20, 25),
        spot: Color.fromARGB(31, 147, 127, 79),
      );
  }
}

/// Returns a high-contrast variant of [base] for the given [mode].
/// Only `text`, `text2`, `text3`, and `border` are overridden;
/// all other tokens are identical to [base].
Palette applyHighContrast(Palette base, AppMode mode) {
  switch (mode) {
    case AppMode.dark:
      return Palette(
        bg: base.bg,
        bg2: base.bg2,
        surface: base.surface,
        surface2: base.surface2,
        glass: base.glass,
        border: const Color.fromARGB(82, 232, 212, 172),
        text: const Color(0xFFFCF5E9),
        text2: const Color(0xFFDCCEB3),
        text3: const Color(0xFFAA9B81),
        accent: base.accent,
        accent2: base.accent2,
        accentSoft: base.accentSoft,
        shadow: base.shadow,
        spot: base.spot,
      );
    case AppMode.light:
      return Palette(
        bg: base.bg,
        bg2: base.bg2,
        surface: base.surface,
        surface2: base.surface2,
        glass: base.glass,
        border: const Color.fromARGB(92, 78, 54, 24),
        text: const Color(0xFF140D03),
        text2: const Color(0xFF3B2C17),
        text3: const Color(0xFF6A573C),
        accent: base.accent,
        accent2: base.accent2,
        accentSoft: base.accentSoft,
        shadow: base.shadow,
        spot: base.spot,
      );
  }
}

/// Six cover gradient color pairs (top-left to bottom-right).
const List<(Color, Color)> kCovers = [
  (Color(0xFF3C2B1C), Color(0xFF22150F)),
  (Color(0xFF2B2A2F), Color(0xFF16151A)),
  (Color(0xFF4A3422), Color(0xFF2A1A10)),
  (Color(0xFF28302B), Color(0xFF161E1A)),
  (Color(0xFF3E2630), Color(0xFF21141C)),
  (Color(0xFF34302A), Color(0xFF1C1A15)),
];
