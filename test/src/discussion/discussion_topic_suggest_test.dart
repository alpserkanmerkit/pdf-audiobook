// PR (A6) RED test (oracle). lib/src/discussion/discussion_topic_suggest.dart
// has not been written by a worker yet -- this file pins the PURE topic
// suggestion function (discussionTopicForBook). No io/state; text generation only.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_topic_suggest.dart';
import 'package:sesli_kitap/src/library/library_store.dart';

void main() {
  const book = Book(
    id: 'b1',
    title: 'The Architecture of Silence',
    author: 'D. Karaca',
    chapterLabel: 'Chapter 4',
    progressPercent: 38,
    totalPages: 318,
    coverIndex: 0,
  );

  group('discussionTopicForBook', () {
    test('title AND chapter label both appear in the topic text', () {
      final topic = discussionTopicForBook(book);
      expect(topic, contains(book.title));
      expect(topic, contains(book.chapterLabel));
    });

    test(
      'progress percentage (%progressPercent) is embedded in the topic text',
      () {
        final topic = discussionTopicForBook(book);
        expect(topic, contains('%38'));
      },
    );

    test(
      'spoiler-guard sentence is added to the topic text AND comes AFTER the title/chapter',
      () {
        final topic = discussionTopicForBook(book);
        expect(topic, contains('Do NOT reveal'));
        expect(
          topic.indexOf('Do NOT reveal'),
          greaterThan(topic.indexOf(book.chapterLabel)),
          reason:
              'spoiler-guard must be appended to the END of the topic STRING',
        );
      },
    );

    test(
      'empty chapter label: no dangling " — " separator remains, only the title is used',
      () {
        const noChapter = Book(
          id: 'b2',
          title: 'The Limits of Thought',
          author: 'A. Vural',
          chapterLabel: '',
          progressPercent: 16,
          totalPages: 264,
          coverIndex: 1,
        );
        final topic = discussionTopicForBook(noChapter);
        expect(topic, isNot(contains(' — ')));
        expect(topic, startsWith(noChapter.title));
        expect(topic, contains('%16'));
      },
    );

    test(
      'whitespace-only chapter label is also treated as empty (trimmed)',
      () {
        const blankChapter = Book(
          id: 'b3',
          title: 'The Texture of Time',
          author: 'M. Şahin',
          chapterLabel: '   ',
          progressPercent: 0,
          totalPages: 412,
          coverIndex: 2,
        );
        final topic = discussionTopicForBook(blankChapter);
        expect(topic, isNot(contains(' — ')));
        expect(topic, startsWith(blankChapter.title));
        expect(topic, contains('%0'));
      },
    );
  });
}
