// Open item 3 (endless-mode durability): the existing gate tests pinned endless
// mode only with short scenarios (2-8 turns); the device acceptance (04.07)
// observed 20-27 turns, but the repo had NO deterministic evidence for a LONG
// RUN. This test pins two protections that DiscussionController ALREADY HAS
// (audio-buffer eviction + kRecentContextTurns/rolling-summary context limiting)
// over a 50+ turn run -- it adds NO new mechanism; it proves the robustness of
// the existing ones. Fake generate/continueScript/synthesize/play; no real
// LLM/TTS (the mock boundary is the same as in discussion_controller_test.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('endless-mode durability (50+ turns)', () {
    test('the audio buffer NEVER exceeds 2 at any point; continuation context is '
        'ALWAYS capped at kRecentContextTurns; the rolling summary kicks in; '
        'playback order holds for 50 turns', () async {
      const targetTotal = 50;
      var generated = 2; // size of the first batch (generate).
      var extendCalls = 0;
      final bufferedSamples = <int>[];
      final contextSizes = <int>[];
      final topicsSeen = <String>[];
      final playedTexts = <String>[];

      late DiscussionController controller;
      controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
          DiscussionTurn(DiscussionSpeaker.b, 't1'),
        ],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (mp3) async {
          playedTexts.add(utf8.decode(mp3));
          // Small real delay: the pre-synthesis (SynthesizeTurn) micro-task
          // surely completes in this window, so sampling meaningfully exercises
          // the "at most 2 live buffers" invariant (same pattern as the
          // PRE-SYNTHESIS PROOF test in discussion_controller_test.dart).
          await Future<void>.delayed(const Duration(milliseconds: 2));
          bufferedSamples.add(controller.bufferedAudioCount);
        },
        openEnded: true,
        continueScript: (topic, recent) async {
          extendCalls++;
          contextSizes.add(recent.length);
          topicsSeen.add(topic);
          if (generated >= targetTotal) {
            // Model/script source exhausted (test terminator) -- the existing
            // ExtensionFailed path (discussion_machine.dart) gracefully moves to
            // finished, just like the degenerate cases in the existing tests.
            throw Exception('script source exhausted (test terminator)');
          }
          final start = generated;
          generated += 2;
          return [
            DiscussionTurn(DiscussionSpeaker.a, 't$start'),
            DiscussionTurn(DiscussionSpeaker.b, 't${start + 1}'),
          ];
        },
      );

      await controller.run('endless durability test');

      // 1) Order/integrity: t0..t49 exactly in order, no skip/repeat/loss.
      expect(
        playedTexts,
        List.generate(targetTotal, (i) => 't$i'),
        reason: 'playback order must not break over 50 turns',
      );

      // 2) Memory discipline: the audio buffer never exceeded 2 at any sample
      // (no GROWTH beyond playing + pre-synthesized -- repo-level evidence
      // against a runaway-memory risk).
      expect(bufferedSamples, isNotEmpty);
      expect(
        bufferedSamples.every((n) => n <= 2),
        isTrue,
        reason:
            'the audio buffer count (bufferedAudioCount) must not exceed 2 in any turn; '
            'observed: $bufferedSamples',
      );

      // 3) DQ-4 context limit: the window passed to continueScript NEVER exceeded
      // kRecentContextTurns in any continuation call (there are ~24 continuation
      // calls over 50 turns, and all must obey the same limit).
      expect(extendCalls, greaterThan(1));
      expect(
        contextSizes.every((n) => n <= kRecentContextTurns),
        isTrue,
        reason:
            'the continuation context must NEVER exceed the kRecentContextTurns($kRecentContextTurns) '
            'window in any call; observed: $contextSizes',
      );

      // 4) The rolling summary kicked in at least once (when turns exceeded the
      // window, old material was added to the topic as a short trace instead of
      // being "forgotten" -- the real DQ-4 defense against repeating the same
      // argument; it rests on 100+ turn device observations).
      expect(
        topicsSeen.any((t) => t.contains('PREVIOUS COURSE OF THE DISCUSSION')),
        isTrue,
        reason:
            '50 turns >> kRecentContextTurns(6): at least one continuation call '
            'must see a topic containing the rolling summary',
      );
    });
  });
}
