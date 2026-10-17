// Oracle test (Phase 3 prerequisite): reading-rhythm orchestration is a PURE state machine.
// Retrospective lesson #3: in Phase 2 this logic lived inside the UI wiring
// (~525 lines, the worker had no judge). This machine brings it into a
// gate-tested area: the UI shell only executes the commands, and ALL decisions
// are tested here.
//
// Behavior source: the reader_screen.dart Phase 2 wiring (flow verified on the
// device) -- these tests turn the current behavior into a CONTRACT; they do not change it.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/reader_machine.dart';

ReaderState _ready({int page = 32, int total = 706}) {
  final r = transition(
    ReaderState.initial(),
    BookLoaded(totalPages: total, startPage: page),
  );
  return r.state;
}

ReaderState _preparing({int page = 32, int total = 706}) {
  final r = transition(_ready(page: page, total: total), TogglePressed());
  return r.state;
}

ReaderState _playing({int page = 32, int total = 706}) {
  final r = transition(
    _preparing(page: page, total: total),
    PrepareSucceeded(),
  );
  return r.state;
}

ReaderState _paused({int page = 32, int total = 706}) {
  final r = transition(_playing(page: page, total: total), TogglePressed());
  return r.state;
}

void main() {
  group('initial state', () {
    test('initial: idle, page 1, total 0', () {
      final s = ReaderState.initial();
      expect(s.phase, ReaderPhase.idle);
      expect(s.currentPage, 1);
      expect(s.totalPages, 0);
    });

    test(
      'idle + TogglePressed: nothing happens without a book (no command)',
      () {
        final r = transition(ReaderState.initial(), TogglePressed());
        expect(r.state.phase, ReaderPhase.idle);
        expect(r.commands, isEmpty);
      },
    );

    test('idle + AudioCompleted: swallowed (robustness)', () {
      final r = transition(ReaderState.initial(), AudioCompleted());
      expect(r.state.phase, ReaderPhase.idle);
      expect(r.commands, isEmpty);
    });
  });

  group('book loading', () {
    test('BookLoaded: ready + the page you left off on', () {
      final r = transition(
        ReaderState.initial(),
        BookLoaded(totalPages: 706, startPage: 32),
      );
      expect(r.state.phase, ReaderPhase.ready);
      expect(r.state.currentPage, 32);
      expect(r.state.totalPages, 706);
      expect(r.commands, isEmpty);
    });

    test(
      'BookLoaded: out-of-range startPage falls back to 1 (low and high)',
      () {
        final low = transition(
          ReaderState.initial(),
          BookLoaded(totalPages: 706, startPage: 0),
        );
        expect(low.state.currentPage, 1);
        final high = transition(
          ReaderState.initial(),
          BookLoaded(totalPages: 706, startPage: 999),
        );
        expect(high.state.currentPage, 1);
      },
    );

    test(
      'BookLoaded while playing: the new book resets everything (ready)',
      () {
        final r = transition(
          _playing(),
          BookLoaded(totalPages: 50, startPage: 5),
        );
        expect(r.state.phase, ReaderPhase.ready);
        expect(r.state.currentPage, 5);
        expect(r.state.totalPages, 50);
      },
    );
  });

  group('playback rhythm: ready -> preparing -> playing', () {
    test('ready + Toggle: preparing + PrepareAudio(page)', () {
      final r = transition(_ready(), TogglePressed());
      expect(r.state.phase, ReaderPhase.preparing);
      expect(r.commands, hasLength(1));
      expect(r.commands.single, isA<PrepareAudio>());
      expect((r.commands.single as PrepareAudio).page, 32);
    });

    test(
      'preparing + PrepareSucceeded: playing + [SaveProgress, PlayAudio, Prefetch]',
      () {
        final r = transition(_preparing(), PrepareSucceeded());
        expect(r.state.phase, ReaderPhase.playing);
        expect(r.commands, hasLength(3));
        expect(r.commands[0], isA<SaveProgress>());
        expect((r.commands[0] as SaveProgress).page, 32);
        expect(r.commands[1], isA<PlayAudio>());
        expect(r.commands[2], isA<Prefetch>());
        expect((r.commands[2] as Prefetch).fromPage, 32);
      },
    );

    test(
      'preparing + PrepareFailed: returns to ready, no command (error handling is UI work)',
      () {
        final r = transition(_preparing(), PrepareFailed('edge-tts 403'));
        expect(r.state.phase, ReaderPhase.ready);
        expect(r.commands, isEmpty);
      },
    );

    test('preparing + Toggle: busy guard -- swallowed', () {
      final r = transition(_preparing(), TogglePressed());
      expect(r.state.phase, ReaderPhase.preparing);
      expect(r.commands, isEmpty);
    });
  });

  group('automatic advance (spec: continuous reading)', () {
    test(
      'playing + AudioCompleted (not the last page): preparing + PrepareAudio for the next page',
      () {
        final r = transition(_playing(), AudioCompleted());
        expect(r.state.phase, ReaderPhase.preparing);
        expect(r.state.currentPage, 33);
        expect(r.commands, hasLength(1));
        expect((r.commands.single as PrepareAudio).page, 33);
      },
    );

    test(
      'playing + AudioCompleted (last page): finished, does not advance',
      () {
        final r = transition(_playing(page: 706), AudioCompleted());
        expect(r.state.phase, ReaderPhase.finished);
        expect(r.state.currentPage, 706);
        expect(r.commands, isEmpty);
      },
    );

    test(
      'paused + AudioCompleted: does NOT advance (playing-guard regression)',
      () {
        final r = transition(_paused(), AudioCompleted());
        expect(r.state.phase, ReaderPhase.paused);
        expect(r.state.currentPage, 32);
        expect(r.commands, isEmpty);
      },
    );
  });

  group('pause / resume', () {
    test('playing + Toggle: paused + [PauseAudio]', () {
      final r = transition(_playing(), TogglePressed());
      expect(r.state.phase, ReaderPhase.paused);
      expect(r.commands, hasLength(1));
      expect(r.commands.single, isA<PauseAudio>());
    });

    test('paused + Toggle: playing + [PlayAudio] (does not re-prepare)', () {
      final r = transition(_paused(), TogglePressed());
      expect(r.state.phase, ReaderPhase.playing);
      expect(r.commands, hasLength(1));
      expect(r.commands.single, isA<PlayAudio>());
    });

    test('finished + Toggle: re-prepares the page where it stopped', () {
      final fin = transition(_playing(page: 706), AudioCompleted()).state;
      final r = transition(fin, TogglePressed());
      expect(r.state.phase, ReaderPhase.preparing);
      expect((r.commands.single as PrepareAudio).page, 706);
    });
  });

  group('page entry', () {
    test('ready + PageEntered (valid): page changes, no command', () {
      final r = transition(_ready(), PageEntered(40));
      expect(r.state.phase, ReaderPhase.ready);
      expect(r.state.currentPage, 40);
      expect(r.commands, isEmpty);
    });

    test('PageEntered out of range: ignored (0 and total+1)', () {
      final zero = transition(_ready(), PageEntered(0));
      expect(zero.state.currentPage, 32);
      final over = transition(_ready(), PageEntered(707));
      expect(over.state.currentPage, 32);
    });

    test('paused + PageEntered: page changes, phase is kept', () {
      final r = transition(_paused(), PageEntered(100));
      expect(r.state.phase, ReaderPhase.paused);
      expect(r.state.currentPage, 100);
    });

    test(
      'finished + PageEntered: page changes (navigating a finished book, K5)',
      () {
        final fin = transition(_playing(page: 706), AudioCompleted()).state;
        expect(fin.phase, ReaderPhase.finished);
        final r = transition(fin, PageEntered(3));
        expect(r.state.phase, ReaderPhase.finished);
        expect(r.state.currentPage, 3);
        expect(r.commands, isEmpty);
      },
    );

    test(
      'finished + PageEntered + Toggle: prepares the NAVIGATED page, not the stale '
      'last page (K5: SaveProgress would also have written the stale page)',
      () {
        final fin = transition(_playing(page: 706), AudioCompleted()).state;
        final nav = transition(fin, PageEntered(3)).state;
        final r = transition(nav, TogglePressed());
        expect(r.state.phase, ReaderPhase.preparing);
        expect((r.commands.single as PrepareAudio).page, 3);
      },
    );
  });

  group('structural contract', () {
    test('transition is PURE: the same input gives the same result twice', () {
      final s = _playing(page: 41);
      final a = transition(s, AudioCompleted());
      final b = transition(s, AudioCompleted());
      expect(a.state.phase, b.state.phase);
      expect(a.state.currentPage, b.state.currentPage);
      expect(a.commands.length, b.commands.length);
    });

    test('transition does NOT MUTATE the input state (immutability)', () {
      final s = _playing(page: 41);
      transition(s, AudioCompleted());
      expect(s.phase, ReaderPhase.playing);
      expect(s.currentPage, 41);
    });
  });
}
