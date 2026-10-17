// Oracle test (PHASE 1): voice identity + pure rate format mapping.
// Spec §2: edge-tts Ahmet/Emel; the speed goes out as a prosody rate percentage.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  group('voiceId', () {
    test('ahmet -> tr-TR-AhmetNeural', () {
      expect(voiceId(SesliVoice.ahmet), 'tr-TR-AhmetNeural');
    });
    test('emel -> tr-TR-EmelNeural', () {
      expect(voiceId(SesliVoice.emel), 'tr-TR-EmelNeural');
    });
    // Slice-2 (4 Google voices): the 4 selected voices (de-risk #3, approved by ear by the user).
    test('wavenetB -> tr-TR-Wavenet-B', () {
      expect(voiceId(SesliVoice.wavenetB), 'tr-TR-Wavenet-B');
    });
    test('aoede -> tr-TR-Chirp3-HD-Aoede', () {
      expect(voiceId(SesliVoice.aoede), 'tr-TR-Chirp3-HD-Aoede');
    });
    test('wavenetE -> tr-TR-Wavenet-E', () {
      expect(voiceId(SesliVoice.wavenetE), 'tr-TR-Wavenet-E');
    });
    test('wavenetC -> tr-TR-Wavenet-C', () {
      expect(voiceId(SesliVoice.wavenetC), 'tr-TR-Wavenet-C');
    });
    // Phase 2 (English TTS support): one male and one female English voice on Google.
    test('enWavenetD -> en-US-Wavenet-D', () {
      expect(voiceId(SesliVoice.enWavenetD), 'en-US-Wavenet-D');
    });
    test('enWavenetF -> en-US-Wavenet-F', () {
      expect(voiceId(SesliVoice.enWavenetF), 'en-US-Wavenet-F');
    });
  });

  // K24 (PHASE 3b RED, 2026-07-02): SesliVoice mixed up the Microsoft (AhmetNeural/EmelNeural)
  // and Google (Wavenet/Chirp3) voice IDs without a provider tag; the adapters passed them
  // through blindly and silently fell back to EdgeTts for an unknown provider.
  // Pure metadata: providerOf maps every enum value to a provider (exhaustive).
  group('providerOf', () {
    test('microsoft voices (edge-tts): ahmet, emel', () {
      expect(providerOf(SesliVoice.ahmet), TtsProviderKind.microsoft);
      expect(providerOf(SesliVoice.emel), TtsProviderKind.microsoft);
    });
    test('google voices: wavenet B/E/C + chirp3 aoede', () {
      expect(providerOf(SesliVoice.wavenetB), TtsProviderKind.google);
      expect(providerOf(SesliVoice.aoede), TtsProviderKind.google);
      expect(providerOf(SesliVoice.wavenetE), TtsProviderKind.google);
      expect(providerOf(SesliVoice.wavenetC), TtsProviderKind.google);
    });
    test('English voices also map to the Google provider (Phase 2)', () {
      expect(providerOf(SesliVoice.enWavenetD), TtsProviderKind.google);
      expect(providerOf(SesliVoice.enWavenetF), TtsProviderKind.google);
    });
    test(
      'every enum value maps (exhaustive -- a new voice cannot stay untagged)',
      () {
        for (final v in SesliVoice.values) {
          expect(
            providerOf(v),
            anyOf(TtsProviderKind.microsoft, TtsProviderKind.google),
            reason: 'providerOf($v) must map to a provider',
          );
        }
      },
    );
  });

  // Bug-G (2026-07-04, device finding): with provider='google' + voice=ahmet/emel
  // selected, the raw voiceId() sends an UNDEFINED name such as "tr-TR-AhmetNeural" to
  // Google -> curl proof: 400 "Voice ... does not exist. Is it
  // misspelled?". googleVoiceId MUST return a VALID Google ID for EVERY SesliVoice
  // (Microsoft-family voices are translated to a gender-matched Google counterpart;
  // Google-family voices pass through unchanged).
  group('googleVoiceId (Bug-G fix)', () {
    test('ahmet (male, Microsoft) -> Wavenet-B (male, Google)', () {
      expect(googleVoiceId(SesliVoice.ahmet), 'tr-TR-Wavenet-B');
    });
    test('emel (female, Microsoft) -> Aoede (female, Google)', () {
      expect(googleVoiceId(SesliVoice.emel), 'tr-TR-Chirp3-HD-Aoede');
    });
    test(
      'Google-family voices pass through unchanged (wavenetB/E/C, aoede)',
      () {
        expect(googleVoiceId(SesliVoice.wavenetB), 'tr-TR-Wavenet-B');
        expect(googleVoiceId(SesliVoice.aoede), 'tr-TR-Chirp3-HD-Aoede');
        expect(googleVoiceId(SesliVoice.wavenetE), 'tr-TR-Wavenet-E');
        expect(googleVoiceId(SesliVoice.wavenetC), 'tr-TR-Wavenet-C');
      },
    );
    test(
      'English voices are also Google-family and pass through (Phase 2)',
      () {
        expect(googleVoiceId(SesliVoice.enWavenetD), 'en-US-Wavenet-D');
        expect(googleVoiceId(SesliVoice.enWavenetF), 'en-US-Wavenet-F');
      },
    );
    test('every enum value maps to a Google-valid name (exhaustive)', () {
      const validGoogleNames = {
        'tr-TR-Wavenet-B',
        'tr-TR-Wavenet-C',
        'tr-TR-Wavenet-E',
        'tr-TR-Chirp3-HD-Aoede',
        'en-US-Wavenet-D',
        'en-US-Wavenet-F',
      };
      for (final v in SesliVoice.values) {
        expect(
          validGoogleNames,
          contains(googleVoiceId(v)),
          reason: 'googleVoiceId($v) must be a valid Google name',
        );
      }
    });
  });

  // Phase 2 (English TTS support): the locale code sent in the xml:lang/languageCode API
  // fields is derived FROM THE VOICE ITSELF (from the locale prefix that voiceId already
  // carries), not a fixed tr-TR. A separate Book.language parameter never leaks into the
  // TTS layer; the single source of truth is SesliVoice.
  group('localeCodeOf (Phase 2 -- SSML/API language code)', () {
    test('Turkish voices -> tr-TR', () {
      for (final v in [
        SesliVoice.ahmet,
        SesliVoice.emel,
        SesliVoice.wavenetB,
        SesliVoice.aoede,
        SesliVoice.wavenetE,
        SesliVoice.wavenetC,
      ]) {
        expect(localeCodeOf(v), 'tr-TR', reason: '$v');
      }
    });
    test('English voices -> en-US', () {
      expect(localeCodeOf(SesliVoice.enWavenetD), 'en-US');
      expect(localeCodeOf(SesliVoice.enWavenetF), 'en-US');
    });
    test('every enum value returns a locale (exhaustive)', () {
      for (final v in SesliVoice.values) {
        expect(localeCodeOf(v), anyOf('tr-TR', 'en-US'), reason: '$v');
      }
    });
  });

  // Phase 2 (English TTS support): the reader's REAL decision point -- from the book's
  // language and the user's general/English voice preferences, it decides purely which
  // SesliVoice + provider to use. reader_screen calls this directly (a thin wrapper);
  // all the branching logic lives here and is easy to unit-test.
  group('resolveReadingVoice (Phase 2 -- reader voice/provider decision)', () {
    test(
      "Turkish book: the user's general voice+provider preference is used",
      () {
        final r = resolveReadingVoice(
          bookLanguage: 'tr',
          preferredVoiceId: 'tr-TR-EmelNeural',
          preferredProvider: 'google',
          preferredEnglishVoiceId: '',
        );
        expect(r.voice, SesliVoice.emel);
        expect(r.provider, 'google');
      },
    );

    test('Turkish book + undefined/empty preference -> ahmet default', () {
      final r = resolveReadingVoice(
        bookLanguage: 'tr',
        preferredVoiceId: '',
        preferredProvider: 'edge',
        preferredEnglishVoiceId: '',
      );
      expect(r.voice, SesliVoice.ahmet);
    });

    test('English book: the provider is ALWAYS google (the Turkish provider '
        'preference -- e.g. edge -- is IGNORED, because English voices exist '
        'only on Google right now)', () {
      final r = resolveReadingVoice(
        bookLanguage: 'en',
        preferredVoiceId: 'tr-TR-AhmetNeural',
        preferredProvider: 'edge',
        preferredEnglishVoiceId: 'en-US-Wavenet-F',
      );
      expect(r.voice, SesliVoice.enWavenetF);
      expect(r.provider, 'google');
    });

    test(
      'English book + undefined/empty English voice preference -> enWavenetD '
      'default (still provider=google)',
      () {
        final r = resolveReadingVoice(
          bookLanguage: 'en',
          preferredVoiceId: 'tr-TR-AhmetNeural',
          preferredProvider: 'azure',
          preferredEnglishVoiceId: '',
        );
        expect(r.voice, SesliVoice.enWavenetD);
        expect(r.provider, 'google');
      },
    );

    test('any bookLanguage other than "tr" -- behaves like Turkish', () {
      final r = resolveReadingVoice(
        bookLanguage: '',
        preferredVoiceId: 'tr-TR-AhmetNeural',
        preferredProvider: 'edge',
        preferredEnglishVoiceId: '',
      );
      expect(r.voice, SesliVoice.ahmet);
      expect(r.provider, 'edge');
    });
  });

  group('formatRate', () {
    test('1.0 -> +0% (default speed)', () {
      expect(formatRate(1), '+0%');
    });
    test('1.25 -> +25%', () {
      expect(formatRate(1.25), '+25%');
    });
    test('0.8 -> -20%', () {
      expect(formatRate(0.8), '-20%');
    });
    test('fractions round to a whole percent (1.004 -> +0%)', () {
      expect(formatRate(1.004), '+0%');
    });
    test('zero or negative speed throws ArgumentError', () {
      expect(() => formatRate(0), throwsArgumentError);
      expect(() => formatRate(-0.5), throwsArgumentError);
    });
  });

  // Gemini TTS slice (2026-09-28): the user approved the 4-speaker sample by ear
  // (Masaustu\Ses_Karsilastirma\3_gemini_4kisi_flash_lite.wav): Ahmet=Charon,
  // Emel=Aoede, Deniz=Gacrux (Kore sounded too similar to Emel), Kaya=Puck.
  group('geminiVoiceName', () {
    test('voices of the 4 discussion speakers (via voiceForSpeaker)', () {
      expect(geminiVoiceName(SesliVoice.wavenetB), 'Charon'); // A = Ahmet
      expect(geminiVoiceName(SesliVoice.aoede), 'Aoede'); // B = Emel
      expect(geminiVoiceName(SesliVoice.wavenetE), 'Gacrux'); // C = Deniz
      expect(geminiVoiceName(SesliVoice.wavenetC), 'Puck'); // D = Kaya
    });
    test('the 4 speakers have DISTINCT voices', () {
      final names = {
        SesliVoice.wavenetB,
        SesliVoice.aoede,
        SesliVoice.wavenetE,
        SesliVoice.wavenetC,
      }.map(geminiVoiceName).toSet();
      expect(names.length, 4);
    });
    test('other voices fall back to a gender-matched Gemini voice', () {
      expect(geminiVoiceName(SesliVoice.ahmet), 'Charon');
      expect(geminiVoiceName(SesliVoice.emel), 'Aoede');
      expect(geminiVoiceName(SesliVoice.enWavenetD), 'Charon');
      expect(geminiVoiceName(SesliVoice.enWavenetF), 'Aoede');
    });
  });
}
