// Slice-6 RED test (oracle). lib/src/discussion/discussion_presenter.dart is written by a worker.
// Visual mapping of a 4-voice (A/B/C/D) script -> 2 avatars (Emel/Ahmet) (discussion analysis). PURE, 100%.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('speakerName (4 people — each speaker has its own face)', () {
    test('a/b/c/d -> 4 separate Turkish names', () {
      expect(speakerName(DiscussionSpeaker.a), 'Ahmet');
      expect(speakerName(DiscussionSpeaker.b), 'Emel');
      expect(speakerName(DiscussionSpeaker.c), 'Deniz');
      expect(speakerName(DiscussionSpeaker.d), 'Kaya');
    });
    test('the 4 names are unique (4 people, NO avatar merging)', () {
      final names = DiscussionSpeaker.values.map(speakerName).toSet();
      expect(names, hasLength(4));
    });
  });

  group('steerCaption (steering chips)', () {
    test('known chips produce a line', () {
      for (final kind in SteerKind.values) {
        expect(steerCaption(kind), isNotEmpty);
      }
    });
    test('5 steering types', () {
      expect(SteerKind.values, hasLength(5));
    });
  });

  group('steerDirective (ROOT-CAUSE FIX, device evidence 08.07: OPERATIONAL '
      'instruction going to the model -- steerCaption is ONLY the UI subtitle, '
      'the two must NOT be mixed up)', () {
    test('known types produce a non-empty instruction', () {
      for (final kind in SteerKind.values) {
        expect(steerDirective(kind), isNotEmpty);
      }
    });

    test('steerDirective is ALWAYS DIFFERENT from steerCaption -- one goes to '
        'the model (what to DO), the other to the UI subtitle (what it should '
        'look like it is saying)', () {
      for (final kind in SteerKind.values) {
        expect(
          steerDirective(kind),
          isNot(equals(steerCaption(kind))),
          reason: '$kind: the two must NOT share the same text',
        );
      }
    });

    test(
      'ozet: does NOT request a CLOSING/real summary -- to avoid conflicting with '
      'the continue-prompt\'s "do NOT write a summary" ban, it explicitly directs '
      'toward a NEW axis',
      () {
        final directive = steerDirective(SteerKind.ozet);
        expect(directive, contains('NEW axis'));
        expect(directive, contains('STRICTLY FORBIDDEN'));
      },
    );

    test(
      'derinles: requests a concrete content increase (like mechanism/evidence)',
      () {
        final directive = steerDirective(SteerKind.derinles);
        expect(directive, contains('DEEPER'));
      },
    );

    test(
      'basitlestir: explicitly requests reducing jargon/technical terms',
      () {
        final directive = steerDirective(SteerKind.basitlestir);
        expect(directive, contains('PLAINLY'));
      },
    );
  });
}
