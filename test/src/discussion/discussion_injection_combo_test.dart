// PR insurance package: REGRESSION guards for the ADDITION -- withRollingSummary
// (lib/src/discussion/discussion_rolling_summary.dart) AND withListenerDirective
// (lib/src/discussion/discussion_directive.dart) called together (the real production chain:
// discussion_controller.dart _handleExtend -> withRollingSummary, then
// discussion_room_screen.dart _consumePendingDirective -> withListenerDirective)
// DOCUMENT the CURRENT behavior. These tests add NO new logic -- they only prove (a) the
// BYTE-IDENTITY in the disabled/default state is preserved and (b) when both are active,
// neither breaks the other.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_directive.dart';
import 'package:sesli_kitap/src/discussion/discussion_rolling_summary.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('discussion injection combo (rolling-summary + listener-directive)', () {
    test(
      'BYTE-IDENTITY: empty older-turns + null directive -- original topic UNCHANGED',
      () {
        const topic = 'Discussion on freedom';
        final afterSummary = withRollingSummary(topic, const []);
        final afterDirective = withListenerDirective(afterSummary, null);
        expect(afterDirective, topic);
        // codeUnits comparison: an extra byte-identity guarantee beyond string equality
        // (the "byte-for-byte" emphasis in the task definition).
        expect(afterDirective.codeUnits, topic.codeUnits);
      },
    );

    test('COMBINED: summary context AND directive on the SAME topic -- both visible, '
        'order correct (summary FIRST, directive AFTER), neither breaks the other', () {
      // Production chain: withRollingSummary FIRST (long-term context), its result is fed
      // to withListenerDirective (short-term steer)
      // -- see discussion_controller.dart:279 + discussion_room_screen.dart:242.
      final withContext = withRollingSummary('topic', const [
        DiscussionTurn(DiscussionSpeaker.a, 'the first thesis was this'),
      ]);
      final combined = withListenerDirective(withContext, 'Elaborate on this');

      const expectedCombined =
          'topic\n\n'
          'PREVIOUS COURSE OF THE DISCUSSION (summary -- do NOT repeat, only remember): '
          'Ahmet: the first thesis was this\n\n'
          'LISTENER DIRECTION: Elaborate on this — '
          'address this in the next few lines.';
      expect(combined, expectedCombined);

      // Redundant (golden-independent) order + presence checks.
      expect(combined, contains('PREVIOUS COURSE OF THE DISCUSSION'));
      expect(combined, contains('LISTENER DIRECTION'));
      expect(combined, contains('Ahmet: the first thesis was this'));
      expect(combined, contains('Elaborate on this'));
      final summaryIdx = combined.indexOf('PREVIOUS COURSE OF THE DISCUSSION');
      final directiveIdx = combined.indexOf('LISTENER DIRECTION');
      expect(summaryIdx, greaterThanOrEqualTo(0));
      expect(
        summaryIdx,
        lessThan(directiveIdx),
        reason:
            'summary-first, directive-second order must stay the same as the production chain: '
            'withListenerDirective(withRollingSummary(topic, older), directive)',
      );
    });
  });
}
