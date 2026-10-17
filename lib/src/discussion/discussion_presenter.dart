import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

String speakerName(DiscussionSpeaker s) {
  switch (s) {
    case DiscussionSpeaker.a:
      return 'Ahmet';
    case DiscussionSpeaker.b:
      return 'Emel';
    case DiscussionSpeaker.c:
      return 'Deniz';
    case DiscussionSpeaker.d:
      return 'Kaya';
  }
}

enum SteerKind { derinles, basitlestir, ornek, ozet, karsilastir }

String steerCaption(SteerKind k) {
  switch (k) {
    case SteerKind.derinles:
      return 'Going a bit deeper on this point…';
    case SteerKind.basitlestir:
      return 'Let me put it more plainly…';
    case SteerKind.ornek:
      return 'Let me give an example…';
    case SteerKind.ozet:
      return 'To summarize…';
    case SteerKind.karsilastir:
      return 'Comparing it with this…';
  }
}

/// ROOT-CAUSE FIX (device evidence 08.07): [steerCaption] is a first-person line
/// written ONLY as UI subtitle text ("Let's go a bit deeper on this point…") --
/// it is NOT an operational instruction telling the model WHAT to do. When it
/// was injected directly as a listener directive, the model could "satisfy" it
/// by just saying a similar sentence without actually deepening or simplifying
/// the content. Only "compare" (karsilastir) seemed to work, and that was pure
/// chance: its four opposing stances already form a comparison naturally.
///
/// [steerDirective] instead returns a SEPARATE, OPERATIONAL instruction sent to
/// the model: it explicitly states WHAT content-level change is requested.
/// [SteerKind.ozet] is a special case: the continuation prompt ("CONTINUATION
/// RULES") says "do NOT write a summary". Asking for a real summary/closing would
/// have directly CONTRADICTED that rule (it could never work structurally). So
/// the summary instruction is redefined to mean "briefly recall, THEN steer to a
/// new axis" rather than a closing.
String steerDirective(SteerKind k) {
  switch (k) {
    case SteerKind.derinles:
      return 'Take the topic DEEPER: add a concrete mechanism, a '
          'cause-and-effect relation or evidence -- superficial repetition '
          'is FORBIDDEN.';
    case SteerKind.basitlestir:
      return 'Explain the topic MORE PLAINLY: reduce technical terms and '
          'jargon, and explain it with an everyday analogy.';
    case SteerKind.ornek:
      return 'Add a CONCRETE example or a real case to the point under '
          'discussion.';
    case SteerKind.ozet:
      return 'Briefly recall the positions so far in ONE SENTENCE, THEN steer '
          'the discussion to a NEW axis -- ending with a closing or a real '
          'summary is STRICTLY FORBIDDEN.';
    case SteerKind.karsilastir:
      return 'Compare the topic under discussion with a CONCRETE, different '
          'example or situation.';
  }
}

String steerLabelTr(SteerKind k) {
  switch (k) {
    case SteerKind.derinles:
      return 'Go deeper';
    case SteerKind.basitlestir:
      return 'Simplify';
    case SteerKind.ornek:
      return 'Give example';
    case SteerKind.ozet:
      return 'Summarize';
    case SteerKind.karsilastir:
      return 'Compare';
  }
}
