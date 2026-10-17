enum ReaderPhase { idle, ready, preparing, playing, paused, finished }

class BookLoaded {
  BookLoaded({required this.totalPages, required this.startPage});
  final int totalPages;
  final int startPage;
}

class TogglePressed {}

class PrepareSucceeded {}

class PrepareFailed {
  PrepareFailed(this.reason);
  final String reason;
}

class AudioCompleted {}

class PageEntered {
  PageEntered(this.page);
  final int page;
}

class PrepareAudio {
  PrepareAudio(this.page);
  final int page;
}

class SaveProgress {
  SaveProgress(this.page);
  final int page;
}

class PlayAudio {}

class Prefetch {
  Prefetch(this.fromPage);
  final int fromPage;
}

class PauseAudio {}

class ReaderState {
  ReaderState(this.phase, this.currentPage, this.totalPages);
  factory ReaderState.initial() => ReaderState(ReaderPhase.idle, 1, 0);
  final ReaderPhase phase;
  final int currentPage;
  final int totalPages;
}

class TransitionResult {
  TransitionResult(this.state, this.commands);
  final ReaderState state;
  final List<Object> commands;
}

TransitionResult transition(ReaderState state, Object event) {
  var phase = state.phase;
  var page = state.currentPage;
  var total = state.totalPages;
  final commands = <Object>[];

  if (event is BookLoaded) {
    var start = event.startPage;
    if (start < 1 || start > event.totalPages) start = 1;
    phase = ReaderPhase.ready;
    page = start;
    total = event.totalPages;
  } else if (phase != ReaderPhase.idle) {
    if (event is TogglePressed) {
      if (phase == ReaderPhase.ready) {
        phase = ReaderPhase.preparing;
        commands.add(PrepareAudio(page));
      } else if (phase == ReaderPhase.preparing) {
        // no change
      } else if (phase == ReaderPhase.playing) {
        phase = ReaderPhase.paused;
        commands.add(PauseAudio());
      } else if (phase == ReaderPhase.paused) {
        phase = ReaderPhase.playing;
        commands.add(PlayAudio());
      } else if (phase == ReaderPhase.finished) {
        phase = ReaderPhase.preparing;
        commands.add(PrepareAudio(page));
      }
    } else if (event is PrepareSucceeded) {
      if (phase == ReaderPhase.preparing) {
        phase = ReaderPhase.playing;
        commands
          ..add(SaveProgress(page))
          ..add(PlayAudio())
          ..add(Prefetch(page));
      }
    } else if (event is PrepareFailed) {
      if (phase == ReaderPhase.preparing) {
        phase = ReaderPhase.ready;
      }
    } else if (event is AudioCompleted) {
      if (phase == ReaderPhase.playing) {
        if (page < total) {
          page++;
          phase = ReaderPhase.preparing;
          commands.add(PrepareAudio(page));
        } else {
          phase = ReaderPhase.finished;
        }
      }
    } else if (event is PageEntered) {
      final newPage = event.page;
      if (newPage >= 1 && newPage <= total) {
        // finished also accepts page navigation (K5): on a finished book, going to
        // a page and pressing play prepares the NAVIGATED page; otherwise a stale
        // last page would be prepared and SaveProgress would write the stale page.
        if (phase == ReaderPhase.ready ||
            phase == ReaderPhase.paused ||
            phase == ReaderPhase.finished) {
          page = newPage;
        }
      }
    }
  }

  return TransitionResult(ReaderState(phase, page, total), commands);
}
