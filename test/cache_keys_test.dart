// Oracle test (FAZ 2): cache key + version-tag staleness (spec §4).
// Decision (start of FAZ 2): the cache is FILE-BASED -> keys MUST be file-name safe.
// A record carries tags (cleanPromptVersion/ttsVoice/ttsRate); if the tags do not
// match, the record counts as stale and is regenerated.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/cache_keys.dart';

void main() {
  const stamp = CacheStamp(
    cleanPromptVersion: 'v1',
    ttsVoice: 'tr-TR-AhmetNeural',
    ttsRate: '+0%',
  );

  group('textCacheKey', () {
    test('deterministic: same input, same key', () {
      final a = textCacheKey(
        bookHash: 'abc123',
        pageNo: 30,
        cleanPromptVersion: 'v1',
      );
      final b = textCacheKey(
        bookHash: 'abc123',
        pageNo: 30,
        cleanPromptVersion: 'v1',
      );
      expect(a, b);
    });
    test('the key changes when the page/book/version changes', () {
      final base = textCacheKey(
        bookHash: 'abc123',
        pageNo: 30,
        cleanPromptVersion: 'v1',
      );
      expect(
        textCacheKey(bookHash: 'abc123', pageNo: 31, cleanPromptVersion: 'v1'),
        isNot(base),
      );
      expect(
        textCacheKey(bookHash: 'zzz999', pageNo: 30, cleanPromptVersion: 'v1'),
        isNot(base),
      );
      expect(
        textCacheKey(bookHash: 'abc123', pageNo: 30, cleanPromptVersion: 'v2'),
        isNot(base),
      );
    });
    test('file-name safe: only [a-zA-Z0-9._-]', () {
      final k = textCacheKey(
        bookHash: 'abc123',
        pageNo: 30,
        cleanPromptVersion: 'v1',
      );
      expect(RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(k), isTrue);
    });
  });

  group('audioCacheKey', () {
    test(
      'voice/rate/version: the key changes when any one of them changes',
      () {
        final base = audioCacheKey(
          bookHash: 'abc123',
          pageNo: 30,
          stamp: stamp,
        );
        expect(
          audioCacheKey(
            bookHash: 'abc123',
            pageNo: 30,
            stamp: const CacheStamp(
              cleanPromptVersion: 'v1',
              ttsVoice: 'tr-TR-EmelNeural',
              ttsRate: '+0%',
            ),
          ),
          isNot(base),
        );
        expect(
          audioCacheKey(
            bookHash: 'abc123',
            pageNo: 30,
            stamp: const CacheStamp(
              cleanPromptVersion: 'v1',
              ttsVoice: 'tr-TR-AhmetNeural',
              ttsRate: '+25%',
            ),
          ),
          isNot(base),
        );
        expect(
          audioCacheKey(
            bookHash: 'abc123',
            pageNo: 30,
            stamp: const CacheStamp(
              cleanPromptVersion: 'v2',
              ttsVoice: 'tr-TR-AhmetNeural',
              ttsRate: '+0%',
            ),
          ),
          isNot(base),
        );
      },
    );
    test('file-name safe: characters like "+%" cannot leak into the key', () {
      final k = audioCacheKey(bookHash: 'abc123', pageNo: 30, stamp: stamp);
      expect(RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(k), isTrue);
    });
  });

  group('staleness', () {
    test('text: version difference -> stale; same -> fresh', () {
      expect(
        isTextStale(storedPromptVersion: 'v1', currentPromptVersion: 'v2'),
        isTrue,
      );
      expect(
        isTextStale(storedPromptVersion: 'v1', currentPromptVersion: 'v1'),
        isFalse,
      );
    });
    test(
      'audio: EVERY field difference makes it stale; full equality is fresh',
      () {
        expect(isAudioStale(stored: stamp, current: stamp), isFalse);
        expect(
          isAudioStale(
            stored: stamp,
            current: const CacheStamp(
              cleanPromptVersion: 'v2',
              ttsVoice: 'tr-TR-AhmetNeural',
              ttsRate: '+0%',
            ),
          ),
          isTrue,
        );
        expect(
          isAudioStale(
            stored: stamp,
            current: const CacheStamp(
              cleanPromptVersion: 'v1',
              ttsVoice: 'tr-TR-EmelNeural',
              ttsRate: '+0%',
            ),
          ),
          isTrue,
        );
        expect(
          isAudioStale(
            stored: stamp,
            current: const CacheStamp(
              cleanPromptVersion: 'v1',
              ttsVoice: 'tr-TR-AhmetNeural',
              ttsRate: '-20%',
            ),
          ),
          isTrue,
        );
      },
    );
  });
}
