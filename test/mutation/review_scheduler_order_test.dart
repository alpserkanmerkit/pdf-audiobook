// Mutation test (tool/mutation.dart) finding: review_scheduler.dart session order. Spec: SessionStarted(ids) asks
// questions IN THE GIVEN ORDER (first id immediately, the rest in order via Marked). Earlier tests ran with at most
// 2 ids -> the `.last` instead of `.first` mutant survived.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';

void main() {
  test(
    '3-question session: questions are asked in the given order (a, b, c)',
    () {
      var r = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['a', 'b', 'c']),
      );
      final asked = <String>[(r.commands.single as SpeakQuestion).id];
      expect(r.state.remaining, ['b', 'c']);

      for (var i = 0; i < 2; i++) {
        r = reviewTransition(r.state, const RevealRequested());
        r = reviewTransition(r.state, const Marked(knewIt: true));
        final q = (r.commands.single as SpeakQuestion).id;
        asked.add(q);
        expect(
          r.state.current,
          q,
          reason: 'the command and the state must show the same question',
        );
      }

      expect(asked, ['a', 'b', 'c']);
      expect(r.state.remaining, isEmpty);
      expect(r.state.knownCount, 2);
    },
  );
}
