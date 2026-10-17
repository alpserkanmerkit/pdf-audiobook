// PHASE 2 wiring: file-based dual cache (spec §4) -- text JSON + audio mp3.
// Decision (start of Phase 2): files, NOT sqflite -- single user, page-granular,
// no relational queries. Keys come from lib/src/cache_keys.dart (filename-safe).
// The raw text is stored too: "show original" (spec §7 Phase 2) reads it from here.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:sesli_kitap/src/digest/digest_model.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';

class TextEntry {
  const TextEntry({
    required this.raw,
    required this.clean,
    required this.promptVersion,
    required this.suspicious,
    this.suspicionReasons = const [],
    this.auditFaithful,
  });

  factory TextEntry.fromJson(Map<String, dynamic> j) => TextEntry(
    raw: j['raw'] as String,
    clean: j['clean'] as String,
    promptVersion: j['promptVersion'] as String,
    suspicious: j['suspicious'] as bool,
    suspicionReasons: (j['suspicionReasons'] as List<dynamic>? ?? [])
        .cast<String>(),
    auditFaithful: j['auditFaithful'] as bool?,
  );

  final String raw;
  final String clean;
  final String promptVersion;
  final bool suspicious;
  final List<String> suspicionReasons;

  /// Verdict of the conditional auditor (V4-Pro): null = not audited / unreachable.
  final bool? auditFaithful;

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'clean': clean,
    'promptVersion': promptVersion,
    'suspicious': suspicious,
    'suspicionReasons': suspicionReasons,
    'auditFaithful': auditFaithful,
  };
}

class CacheStore {
  CacheStore(this.root);

  final Directory root;

  static Future<CacheStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sesli_kitap_cache');
    await dir.create(recursive: true);
    return CacheStore(dir);
  }

  File _file(String name) => File('${root.path}/$name');

  Future<TextEntry?> readText(String key) async {
    final f = _file('$key.json');
    if (!await f.exists()) {
      return null;
    }
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return TextEntry.fromJson(j);
      // K11: NOT only Exception -- a wrong-typed field cast throws TypeError
      // (an Error). The contract is "a corrupt record = treat as absent", so ALL
      // corruptions are swallowed and the record is regenerated.
    } on Object catch (_) {
      return null; // corrupt record = treat as absent; it is regenerated
    }
  }

  Future<void> writeText(String key, TextEntry entry) =>
      _file('$key.json').writeAsString(jsonEncode(entry.toJson()), flush: true);

  File audioFile(String key) => _file('$key.mp3');

  // K23: a 0-byte file = leftover of a half-finished write; the cache does NOT
  // count it. Keys are content-stamped (never change) -- if an empty file counted
  // as "present", a truncated record would be served forever.
  Future<bool> hasAudio(String key) async {
    final f = audioFile(key);
    if (!await f.exists()) {
      return false;
    }
    return await f.length() > 0;
  }

  // K23: atomic write -- first write to $key.mp3.tmp (flush), then rename to the
  // final name (a rename within the same directory is atomic). A crash mid-write
  // NEVER leaves a truncated file at the final name; on error the .tmp is deleted
  // on a best-effort basis.
  Future<File> writeAudio(String key, Uint8List bytes) async {
    final f = audioFile(key);
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await tmp.rename(f.path);
    } on Object catch (_) {
      try {
        await tmp.delete();
      } on Object catch (_) {
        // best-effort cleanup; the real error is rethrown below
      }
      rethrow;
    }
  }

  // Karaoke foundation (PR-K1): sentence-timing sidecar. Next to the audio mp3 is
  // $key.timing.json. Old mp3s have NO sidecar -> readTimings returns null (by
  // design; PR-K2 falls back).
  File timingFile(String key) => _file('$key.timing.json');

  // K11 catch-all pattern: absent/corrupt/wrong-version -> null; the caller is not crashed.
  Future<SentenceTimings?> readTimings(String key) async {
    final f = timingFile(key);
    if (!await f.exists()) {
      return null;
    }
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return SentenceTimings.fromJson(j);
    } on Object catch (_) {
      return null; // corrupt sidecar = treat as absent
    }
  }

  // K23 atomic: write to tmp + rename; on error, best-effort delete the tmp.
  Future<File> writeTimings(String key, SentenceTimings t) async {
    final f = timingFile(key);
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(t.toJson()), flush: true);
      return await tmp.rename(f.path);
    } on Object catch (_) {
      try {
        await tmp.delete();
      } on Object catch (_) {
        // best-effort cleanup; the real error is rethrown below
      }
      rethrow;
    }
  }

  /// S2: deletes audio leftovers (.mp3 + .mp3.tmp) whose name starts with
  /// [prefix]. An endless discussion leaves a temporary mp3 for every turn; the
  /// sweep at the start of a run cleans the leftovers of the previous run (and of
  /// half-written .tmp files). Best-effort: a file that cannot be deleted is
  /// skipped; returns the number of files actually deleted.
  Future<int> sweepAudio(String prefix) async {
    var deleted = 0;
    try {
      await for (final entity in root.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        if (!name.endsWith('.mp3') && !name.endsWith('.mp3.tmp')) continue;
        try {
          await entity.delete();
          deleted++;
        } on Object catch (_) {
          // best-effort: skip locked/racing files.
        }
      }
    } on Object catch (_) {
      // If the directory cannot be listed (race/permission), silently skip the sweep.
    }
    return deleted;
  }

  // --- Book-digest (DG-W1) cache region -------------------------------------
  // SEPARATE region: does not touch the text/audio/sweepAudio code above. Keys come
  // from lib/src/digest/digest_constants.dart (chapterDigestCacheKey /
  // bookDigestCacheKey); JSON encoding from lib/src/digest/digest_model.dart
  // (ChapterDigest/BookDigest). Same K11 contract: a corrupt record -> null, it is
  // regenerated. Same K23 contract: atomic tmp+rename write.

  File _digestFile(String key) => _file('$key.json');

  /// Reads the COMBINED digest of a single chapter (not a per-part intermediate
  /// record -- after io mergeChapterParts combines them, ONE record is kept here).
  Future<ChapterDigest?> readChapterDigest(String key) async {
    final f = _digestFile(key);
    if (!await f.exists()) {
      return null;
    }
    try {
      final raw = jsonDecode(await f.readAsString());
      return ChapterDigest.fromJson(raw);
    } on Object catch (_) {
      return null; // corrupt record = treat as absent; regenerated (K11 pattern)
    }
  }

  Future<File> writeChapterDigest(String key, ChapterDigest digest) =>
      _writeJsonAtomic(_digestFile(key), jsonEncode(digest.toJson()));

  /// Reads the full digest manifest for the whole book.
  Future<BookDigest?> readBookDigest(String key) async {
    final f = _digestFile(key);
    if (!await f.exists()) {
      return null;
    }
    try {
      return decodeBookDigest(await f.readAsString());
    } on Object catch (_) {
      return null; // corrupt record = treat as absent; regenerated (K11 pattern)
    }
  }

  Future<File> writeBookDigest(String key, BookDigest digest) =>
      _writeJsonAtomic(_digestFile(key), encodeBookDigest(digest));

  /// Atomic JSON write: write to $key.json.tmp (flush), then rename to the final
  /// name (same as the K23 pattern -- a crash mid-write never leaves a truncated
  /// file at the final name).
  Future<File> _writeJsonAtomic(File f, String json) async {
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(json, flush: true);
      return await tmp.rename(f.path);
    } on Object catch (_) {
      try {
        await tmp.delete();
      } on Object catch (_) {
        // best-effort cleanup; the real error is rethrown below
      }
      rethrow;
    }
  }
}
