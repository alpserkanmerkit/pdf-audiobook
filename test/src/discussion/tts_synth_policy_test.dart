// Package A1 RED test (oracle). lib/src/discussion/tts_synth_policy.dart
// is written by a worker. Core of TTS SYNTHESIS RESILIENCE (see discussion_machine.dart
// ~177-185: in playing/waiting a SINGLE TurnFailed drops the WHOLE discussion to 'failed' --
// unlike ExtensionFailed it does NOT degrade gracefully). This package closes the asymmetry
// in the SYNTHESIS layer WITHOUT TOUCHING discussion_machine.dart at all (that file is FROZEN):
// primary (Google) -> 1 Google retry -> Edge fallback.
//
// PURE, 100% (no io/UI): synthAttemptPlan/edgeVoiceId are pure data; runSynthAttempts
// calls the provider through an injected callback -- it NEVER touches the real network/
// websocket (fully tested closed with fake callbacks).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/tts_synth_policy.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  group('edgeVoiceId (Bug-G mirror -- Edge-valid voice identity)', () {
    test('Microsoft-family voice (ahmet) passes through unchanged', () {
      expect(edgeVoiceId(SesliVoice.ahmet), voiceId(SesliVoice.ahmet));
    });

    test('Microsoft-family voice (emel) passes through unchanged', () {
      expect(edgeVoiceId(SesliVoice.emel), voiceId(SesliVoice.emel));
    });

    test('wavenetB (speaker A, male) -> Ahmet counterpart', () {
      expect(edgeVoiceId(SesliVoice.wavenetB), voiceId(SesliVoice.ahmet));
    });

    test('aoede (speaker B, female) -> Emel counterpart', () {
      expect(edgeVoiceId(SesliVoice.aoede), voiceId(SesliVoice.emel));
    });

    test('wavenetE (speaker C, male) -> Ahmet counterpart', () {
      expect(edgeVoiceId(SesliVoice.wavenetE), voiceId(SesliVoice.ahmet));
    });

    test('wavenetC (speaker D, female) -> Emel counterpart', () {
      expect(edgeVoiceId(SesliVoice.wavenetC), voiceId(SesliVoice.emel));
    });

    test('enWavenetD (English, male) -> Ahmet counterpart', () {
      expect(edgeVoiceId(SesliVoice.enWavenetD), voiceId(SesliVoice.ahmet));
    });

    test('enWavenetF (English, female) -> Emel counterpart', () {
      expect(edgeVoiceId(SesliVoice.enWavenetF), voiceId(SesliVoice.emel));
    });

    test(
      'raw voiceId for the 4 discussion voices would be INVALID on Edge too (Bug-G)',
      () {
        // If a Google-family voice is sent to Edge via the raw voiceId(), an UNDEFINED
        // name goes out (the MIRROR of the asymmetry that googleVoiceId resolves).
        // Since edgeVoiceId ALWAYS maps to Ahmet/Emel, it must DIFFER from the raw voiceId().
        for (final v in [
          SesliVoice.wavenetB,
          SesliVoice.aoede,
          SesliVoice.wavenetE,
          SesliVoice.wavenetC,
        ]) {
          expect(
            edgeVoiceId(v),
            isNot(voiceId(v)),
            reason:
                '$v: the raw voiceId would have stayed UNDEFINED on the Edge side',
          );
        }
      },
    );
  });

  group('synthAttemptPlan (ordered attempt plan)', () {
    // Gemini TTS slice (user decision 2026-09-28): the discussion voice is now
    // Gemini (gemini-3.8-flash-lite-tts); primary -> 1 retry -> Edge fallback
    // resilience is kept AS IS, only the primary provider changes.
    test('order: Gemini (primary) -> Gemini (retry) -> Edge (fallback)', () {
      final plan = synthAttemptPlan(SesliVoice.wavenetB);
      expect(plan, hasLength(3));
      expect(plan[0].provider, SynthProvider.gemini);
      expect(plan[1].provider, SynthProvider.gemini);
      expect(plan[2].provider, SynthProvider.edge);
    });

    test('HAPPY PATH: first attempt is GeminiTts + geminiVoiceName', () {
      final plan = synthAttemptPlan(SesliVoice.wavenetB);
      expect(plan.first.provider, SynthProvider.gemini);
      expect(plan.first.voiceId, geminiVoiceName(SesliVoice.wavenetB));
      expect(plan.first.voiceId, 'Charon');
    });

    test(
      'Gemini retry attempt carries EXACTLY the same identity as the primary',
      () {
        final plan = synthAttemptPlan(SesliVoice.aoede);
        expect(plan[1].voiceId, plan[0].voiceId);
        expect(plan[1].provider, plan[0].provider);
      },
    );

    test('Edge-voice substitution: fallback attempt uses edgeVoiceId '
        '(NOT the raw Google identity)', () {
      final plan = synthAttemptPlan(SesliVoice.wavenetB);
      expect(plan[2].voiceId, edgeVoiceId(SesliVoice.wavenetB));
      // wavenetB is male -> Ahmet counterpart.
      expect(plan[2].voiceId, voiceId(SesliVoice.ahmet));
    });

    test(
      'a plan is produced for all 4 discussion voices (speakers a/b/c/d)',
      () {
        for (final v in [
          SesliVoice.wavenetB,
          SesliVoice.aoede,
          SesliVoice.wavenetE,
          SesliVoice.wavenetC,
        ]) {
          final plan = synthAttemptPlan(v);
          expect(plan, hasLength(3));
          expect(plan[2].voiceId, edgeVoiceId(v));
        }
      },
    );
  });

  group('SynthAttempt equality/toString (test readability)', () {
    test('same provider+voiceId are equal (including hashCode)', () {
      const a = SynthAttempt(provider: SynthProvider.gemini, voiceId: 'x');
      const b = SynthAttempt(provider: SynthProvider.gemini, voiceId: 'x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different voiceId is not equal', () {
      const a = SynthAttempt(provider: SynthProvider.gemini, voiceId: 'x');
      const b = SynthAttempt(provider: SynthProvider.gemini, voiceId: 'y');
      expect(a, isNot(b));
    });

    test('different provider is not equal', () {
      const a = SynthAttempt(provider: SynthProvider.gemini, voiceId: 'x');
      const b = SynthAttempt(provider: SynthProvider.edge, voiceId: 'x');
      expect(a, isNot(b));
    });

    test('toString contains the readable identities', () {
      const a = SynthAttempt(
        provider: SynthProvider.edge,
        voiceId: 'tr-TR-AhmetNeural',
      );
      expect(a.toString(), contains('tr-TR-AhmetNeural'));
    });
  });

  group(
    'runSynthAttempts (generic attempt runner -- NO I/O, fake callbacks)',
    () {
      List<SynthAttempt> threeAttempts() => const [
        SynthAttempt(provider: SynthProvider.gemini, voiceId: 'g1'),
        SynthAttempt(provider: SynthProvider.gemini, voiceId: 'g2'),
        SynthAttempt(provider: SynthProvider.edge, voiceId: 'e1'),
      ];

      test(
        'first attempt succeeds -> ONE call, later attempts are NEVER made',
        () async {
          final calls = <SynthAttempt>[];
          final result = await runSynthAttempts(threeAttempts(), (
            attempt,
          ) async {
            calls.add(attempt);
            return Uint8List.fromList([1, 2, 3]);
          });
          expect(result, Uint8List.fromList([1, 2, 3]));
          expect(calls, hasLength(1));
          expect(calls.single.voiceId, 'g1');
        },
      );

      test('first attempt throws, second succeeds -> TurnFailed is never seen '
          '(2 calls, retry recovers)', () async {
        final calls = <SynthAttempt>[];
        final result = await runSynthAttempts(threeAttempts(), (attempt) async {
          calls.add(attempt);
          if (calls.length == 1) throw Exception('temporary google error');
          return Uint8List.fromList([9]);
        });
        expect(result, Uint8List.fromList([9]));
        expect(calls, hasLength(2));
        expect(calls[0].voiceId, 'g1');
        expect(calls[1].voiceId, 'g2');
      });

      test(
        'first two (Google) attempts throw, Edge fallback recovers (3 calls)',
        () async {
          final calls = <SynthAttempt>[];
          final result = await runSynthAttempts(threeAttempts(), (
            attempt,
          ) async {
            calls.add(attempt);
            if (calls.length < 3) throw Exception('temporary error');
            return Uint8List.fromList([7]);
          });
          expect(result, Uint8List.fromList([7]));
          expect(calls, hasLength(3));
          expect(calls.last.provider, SynthProvider.edge);
        },
      );

      test("all three fail -> the LAST attempt's error is rethrown "
          '(first two are swallowed silently, 3 calls)', () async {
        final errors = [
          Exception('error #1'),
          Exception('error #2'),
          Exception('error #3 -- last'),
        ];
        var callIndex = 0;
        Object? caught;
        try {
          await runSynthAttempts(threeAttempts(), (attempt) async {
            final err = errors[callIndex];
            callIndex++;
            throw err;
          });
        } on Object catch (e) {
          caught = e;
        }
        expect(callIndex, 3, reason: 'all three must have been attempted');
        expect(
          identical(caught, errors[2]),
          isTrue,
          reason:
              'the LAST attempt (Edge fallback) error must propagate outward',
        );
      });

      test('empty plan -> ArgumentError (defensive guard)', () async {
        await expectLater(
          runSynthAttempts(const [], (attempt) async => Uint8List(0)),
          throwsArgumentError,
        );
      });
    },
  );
}
