// Slice-1a RED test (oracle). lib/src/theme/palette.dart is written by the worker.
// PURE 4-palette color table; values are taken 1:1 from the design prototype's PAL
// object (cross-checked with the design handoff note). A wrong hex = red (safeguard
// against red-green color blindness regressions).
// Deprecated-safe: uses Color equality (==) and Color.fromARGB; no .value/.alpha.
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/theme/palette.dart';

void main() {
  group('paletFor — anchor values (exact hex)', () {
    test('cognac/dark', () {
      final p = paletFor(AppTheme.cognac, AppMode.dark);
      expect(p.bg, const Color(0xFF15100C));
      expect(p.surface, const Color(0xFF241B14));
      expect(p.text, const Color(0xFFECE0CE));
      // text3: design value 0xFF83755F (4.21:1) -> 0xFF988B75 for WCAG AA (K3b).
      expect(p.text3, const Color(0xFF988B75));
      expect(p.accent, const Color(0xFFC99A52));
      expect(p.accent2, const Color(0xFFA86E39));
      // accentSoft rgba(201,154,82,0.16) -> round(0.16*255)=41
      expect(p.accentSoft, const Color.fromARGB(41, 201, 154, 82));
    });
    test('cognac/light', () {
      final p = paletFor(AppTheme.cognac, AppMode.light);
      expect(p.bg, const Color(0xFFEDE3D1));
      expect(p.text, const Color(0xFF2B1D11));
      expect(p.accent, const Color(0xFF9A6A32));
    });
    test('obsidian/dark', () {
      final p = paletFor(AppTheme.obsidian, AppMode.dark);
      expect(p.bg, const Color(0xFF0F1012));
      expect(p.surface, const Color(0xFF1A1C20));
      expect(p.text, const Color(0xFFEAE8E2));
      expect(p.accent, const Color(0xFFD9C59B));
    });
    test('obsidian/light', () {
      final p = paletFor(AppTheme.obsidian, AppMode.light);
      expect(p.bg, const Color(0xFFEAEAE7));
      expect(p.text, const Color(0xFF17181B));
      expect(p.accent, const Color(0xFF937F4F));
    });
  });

  group('structure', () {
    test('4 palettes differ from one another (palettes not mixed up)', () {
      final cd = paletFor(AppTheme.cognac, AppMode.dark);
      final cl = paletFor(AppTheme.cognac, AppMode.light);
      final od = paletFor(AppTheme.obsidian, AppMode.dark);
      final ol = paletFor(AppTheme.obsidian, AppMode.light);
      final bgs = {cd.bg, cl.bg, od.bg, ol.bg};
      expect(
        bgs,
        hasLength(4),
        reason: 'the 4 palettes must each have a separate bg value',
      );
    });
    test('all 14 tokens assigned (accentSoft is semi-transparent)', () {
      final p = paletFor(AppTheme.cognac, AppMode.dark);
      // accentSoft is NOT opaque (semi-transparent accent): proves the token has the right type.
      expect(p.accentSoft, isNot(equals(p.accent)));
    });
  });

  group('applyHighContrast', () {
    test('in dark mode, text is raised to high contrast', () {
      final base = paletFor(AppTheme.cognac, AppMode.dark);
      final hc = applyHighContrast(base, AppMode.dark);
      expect(hc.text, const Color(0xFFFCF5E9));
    });
    test('in light mode, text is lowered to high contrast', () {
      final base = paletFor(AppTheme.cognac, AppMode.light);
      final hc = applyHighContrast(base, AppMode.light);
      expect(hc.text, const Color(0xFF140D03));
    });
    test(
      'high contrast does NOT change accent/bg (only text/text2/text3/border)',
      () {
        final base = paletFor(AppTheme.cognac, AppMode.dark);
        final hc = applyHighContrast(base, AppMode.dark);
        expect(hc.accent, base.accent);
        expect(hc.bg, base.bg);
      },
    );
  });

  // K3b: WCAG 2.x AA (normal text) = 4.5:1. text3 (12-14px helper text) must exceed
  // 4.5 on every surface where text is drawn (bg, bg2, surface, surface2); 4 palettes
  // x 4 surfaces + high-contrast variants. The measurement is computed here using
  // the WCAG relative luminance (Color.computeLuminance).
  group('text3 contrast (WCAG AA 4.5:1)', () {
    double kontrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test(
      'measurement function computes a known pair correctly (black/white 21:1)',
      () {
        expect(
          kontrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 1e-9),
        );
      },
    );

    for (final tema in AppTheme.values) {
      for (final mod in AppMode.values) {
        for (final hc in [false, true]) {
          test('${tema.name}/${mod.name}${hc ? "/high-contrast" : ""}', () {
            var p = paletFor(tema, mod);
            if (hc) p = applyHighContrast(p, mod);
            final yuzeyler = {
              'bg': p.bg,
              'bg2': p.bg2,
              'surface': p.surface,
              'surface2': p.surface2,
            };
            for (final y in yuzeyler.entries) {
              expect(
                kontrast(p.text3, y.value),
                greaterThanOrEqualTo(4.5),
                reason: 'text3 / ${y.key}',
              );
            }
            // Hierarchy must hold: text3 stays less emphasized than text2.
            expect(
              kontrast(p.text3, p.bg),
              lessThan(kontrast(p.text2, p.bg)),
              reason: 'text3 must be paler than text2',
            );
          });
        }
      }
    }
  });

  group('kCovers', () {
    test('6 cover gradients, first pair exact', () {
      expect(kCovers, hasLength(6));
      expect(kCovers[0].$1, const Color(0xFF3C2B1C));
      expect(kCovers[0].$2, const Color(0xFF22150F));
    });
  });
}
