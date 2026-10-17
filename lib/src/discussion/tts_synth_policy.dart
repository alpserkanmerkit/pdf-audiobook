// Package A1: TTS synthesis resilience -- PURE decision, NO I/O.
//
// CONFIRMED PROBLEM: while discussion_machine.dart is in the playing/waiting
// phase, a TurnFailed (synthesis failure) drops the WHOLE discussion into the
// 'failed' phase (see discussion_machine.dart around lines ~177-185: "Any error
// while waiting or playing -> failed") -- a single TTS hiccup kills a 300-turn
// run with a red banner. ExtensionFailed (continuation-batch failure), by
// contrast, degrades GRACEFULLY in the same situation (openEnded closes, the
// phase stays the SAME). Without touching discussion_machine.dart (FROZEN) at
// all, this package closes that asymmetry at the SYNTHESIS layer: before a
// TurnFailed reaches the machine, the attempts are tried in order: primary
// provider (Gemini) -> 1 Gemini retry -> Edge fallback; only if ALL THREE fail
// is TurnFailed finally triggered (the behavior is deliberately KEPT -- only its
// arrival is delayed).
// Gemini TTS slice (user decision 2026-09-28): the primary provider moved from
// Google Cloud TTS to Gemini (gemini-3.8-flash-lite-tts).
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sesli_kitap/src/voices.dart';

/// Specifies which provider a synthesis attempt goes to.
enum SynthProvider { gemini, edge }

/// A SINGLE attempt in the ordered plan: WHICH provider + the voice identity
/// VALID for that provider ([geminiVoiceName] for Gemini, [edgeVoiceId] for
/// Edge) -- the calling layer (discussion_room_screen.dart) does NOT have to
/// compute this again.
@immutable
class SynthAttempt {
  const SynthAttempt({required this.provider, required this.voiceId});

  final SynthProvider provider;
  final String voiceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SynthAttempt &&
          runtimeType == other.runtimeType &&
          provider == other.provider &&
          voiceId == other.voiceId;

  @override
  int get hashCode => Object.hash(provider, voiceId);

  @override
  String toString() => 'SynthAttempt(${provider.name}, $voiceId)';
}

/// Ordered synthesis attempt plan for [voice]: primary (Gemini) -> 1 Gemini
/// retry -> Edge fallback (3 attempts in total).
///
/// The first two attempts carry the [geminiVoiceName] identity (the 4 voices
/// the user approved by ear). The Edge attempt uses [edgeVoiceId] INSTEAD of
/// the raw [voice]: the discussion's 4 speakers carry Google-family SesliVoice
/// values, so the raw voiceId() would have sent an identity UNDEFINED for Edge
/// (e.g. 'tr-TR-Wavenet-B') (the mirror image of Bug-G).
List<SynthAttempt> synthAttemptPlan(SesliVoice voice) {
  final geminiName = geminiVoiceName(voice);
  return [
    SynthAttempt(provider: SynthProvider.gemini, voiceId: geminiName),
    SynthAttempt(provider: SynthProvider.gemini, voiceId: geminiName),
    SynthAttempt(provider: SynthProvider.edge, voiceId: edgeVoiceId(voice)),
  ];
}

/// Tries [attempt] for each [SynthAttempt] in [plan] in order and returns the
/// FIRST successful result immediately. Intermediate failures (Exception/Error)
/// are SILENTLY SWALLOWED and the next attempt is tried; if the LAST attempt
/// also fails, that error is re-thrown AS-IS (rethrow -- the original stack
/// trace is preserved). Thus the caller (discussion_room_screen.dart ->
/// DiscussionController._handleSynthesize -> TurnFailed) sees a failure ONLY
/// after the plan is FULLY exhausted.
///
/// [plan] must not be empty ([ArgumentError] -- a defensive guard: synthAttemptPlan
/// always returns 3 elements, but a caller of [attempt] could theoretically pass
/// an empty list).
Future<Uint8List> runSynthAttempts(
  List<SynthAttempt> plan,
  Future<Uint8List> Function(SynthAttempt attempt) attempt,
) async {
  if (plan.isEmpty) {
    throw ArgumentError.value(plan, 'plan', 'must have at least one attempt');
  }
  var index = 0;
  while (true) {
    try {
      return await attempt(plan[index]);
    } catch (_) {
      if (index == plan.length - 1) rethrow;
      index++;
    }
  }
}
