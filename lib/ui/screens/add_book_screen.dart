import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:sesli_kitap/io/llm_skeleton.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/io/pdf_text.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

enum AddPhase { idle, processing, done, error }

const int _kCopyChunkSize = 64 * 1024;

/// Serializable result of the heavy import work, returned from the isolate.
/// CRITICAL: the raw 185MB PDF byte array is NOT here -- only small results
/// (hash, page count, per-page first line / stripped header) are returned, so the
/// large byte array is never moved to the main isolate heap (isolated from main heap).
class _PdfImportResult {
  const _PdfImportResult({
    required this.hash,
    required this.totalPages,
    required this.rawFirstLines,
    required this.strippedHeaders,
  });

  final String hash;
  final int totalPages;
  final List<String> rawFirstLines;
  final List<String?> strippedHeaders;
}

/// Isolate input: [args] = (srcPath, tmpPath). Copies the source PDF to `tmpPath`
/// synchronously chunk by chunk and hashes it, then runs the syncfusion parse
/// (on `tmpPath`: pdfPageCount + running header + full-page text extraction) and
/// returns ONLY the small results. ALL heavy CPU/memory work happens here (a
/// separate isolate = a separate heap) -- the main thread does not ANR, and the
/// raw 185MB byte array is not returned to the main heap.
///
/// R4 (partial record): the rename is NOT done here -- if the isolate parse fails,
/// no final (hash-named) file is created; the main thread only cleans up `tmpPath`.
/// The rename (tmp -> hash-named) is done on the main thread once the isolate
/// returns SUCCESSFULLY.
///
/// NOTE: PDF parsing (syncfusion PdfDocument(inputBytes:)) requires the whole file
/// to be read into the Dart heap in ONE piece (readAsBytesSync; there is no chunk
/// API). This 185MB single read is unavoidable; the isolate SEPARATES it from the
/// MAIN heap (the old native Java-heap copy of file_picker is also gone).
Future<_PdfImportResult> _importPdfInIsolate((String, String) args) {
  return Isolate.run(() async {
    final (srcPath, tmpPath) = args;
    final hash = _copyWithChunkedHash(File(srcPath), File(tmpPath));

    final bytes = File(tmpPath).readAsBytesSync();
    final totalPages = pdfPageCount(bytes);
    final header = PagePipeline.detectRunningHeader(bytes, totalPages);
    final texts = await extractAllPageTexts(bytes);

    final rawFirstLines = <String>[];
    final strippedHeaders = <String?>[];
    for (final raw in texts) {
      final first = raw
          .trim()
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
          .trim();
      final pre = stripPageArtifacts(raw, knownHeader: header);
      rawFirstLines.add(first);
      strippedHeaders.add(pre.strippedHeader);
    }

    return _PdfImportResult(
      hash: hash,
      totalPages: totalPages,
      rawFirstLines: rawFirstLines,
      strippedHeaders: strippedHeaders,
    );
  });
}

/// Copies [src] to [dst] synchronously in chunks with a FIXED 64KB buffer
/// (RandomAccessFile.readIntoSync/writeFromSync), computes sha256 over the same
/// pass (chunked conversion) and returns its first 16 hex characters.
/// The whole source file is never held in memory as ONE piece at any point --
/// the memory footprint of this COPY step (even for a 185MB PDF) is ~64KB.
/// (The parse step is separate: syncfusion needs the full byte array; see [_importPdfInIsolate].)
String _copyWithChunkedHash(File src, File dst) {
  final inRaf = src.openSync();
  final outRaf = dst.openSync(mode: FileMode.write);
  Digest? digest;
  final input = sha256.startChunkedConversion(
    _SyncDigestSink((d) => digest = d),
  );
  try {
    var buf = Uint8List(_kCopyChunkSize);
    var n = inRaf.readIntoSync(buf);
    while (n > 0) {
      final chunk = n == _kCopyChunkSize ? buf : buf.sublist(0, n);
      input.add(chunk);
      outRaf.writeFromSync(chunk);
      buf = Uint8List(_kCopyChunkSize);
      n = inRaf.readIntoSync(buf);
    }
    input.close();
  } finally {
    inRaf.closeSync();
    outRaf.closeSync();
  }
  return digest.toString().substring(0, 16);
}

/// Minimal [Sink] for the streaming hash (chunked sha256.startChunkedConversion):
/// passes the single [Digest] result to a callback.
class _SyncDigestSink implements Sink<Digest> {
  _SyncDigestSink(this._onDigest);
  final void Function(Digest digest) _onDigest;

  @override
  void add(Digest data) => _onDigest(data);

  @override
  void close() {}
}

class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  AddPhase _phase = AddPhase.idle;
  String _title = '';
  String _errorMessage = '';
  Book? _newBook;

  /// Phase 2 (English TTS support): chosen manually when adding a book; default
  /// 'tr' (existing behavior unchanged). Passed as-is to Book.language.
  String _selectedLanguage = 'tr';

  Future<void> _pickPdf() async {
    final services = AppServicesScope.of(context);
    final picked = await services.pickPdf();
    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _phase = AddPhase.processing;
      _title = picked.name;
    });

    // R4 (partial record / orphan file cleanup): kept outside try so the catch
    // block -- whichever of the copy/parse/LLM steps fails -- can best-effort
    // delete the temp/target file that may have been written in this round
    // (a file never added to books_v1 is not left orphaned).
    File? tmpFile;
    File? copiedFile;
    try {
      final String hash;
      final File file;
      final int totalPages;
      final List<String> rawFirstLines;
      final List<String?> strippedHeaders;
      final booksDir = Directory('${services.dataDir.path}/books')
        ..createSync(recursive: true);

      if (picked.path != null) {
        // OOM + ANR FIX (2026-07-04): ALL heavy work (copy+hash, full-byte read,
        // syncfusion parse) runs in a separate ISOLATE. Two gains:
        //  1) With file_picker withData:false the 185MB copy in the Java heap is
        //     NEVER created (the real 402MB OOM cause is gone).
        //  2) The copy uses a fixed 64KB buffer; the full-byte read
        //     (readAsBytesSync) that syncfusion needs for parsing is unavoidable as
        //     a SINGLE piece, but since it runs in the ISOLATE it is not moved to the
        //     main isolate heap and does not block the main UI thread (in this repo a
        //     long main-thread parse ALREADY caused an ANR; see the 2026-06-13 ANR fix
        //     comment in pdf_text.dart). Only PATHS are passed to the isolate, and only
        //     SMALL results come back.
        tmpFile = File('${booksDir.path}/_incoming.pdf.tmp');
        final result = await _importPdfInIsolate((picked.path!, tmpFile.path));
        // Rename on the main thread (R4: if the isolate fails, no final file is created).
        hash = result.hash;
        file = File('${booksDir.path}/$hash.pdf');
        tmpFile.renameSync(file.path);
        tmpFile = null; // rename succeeded: no .tmp left, no cleanup needed
        copiedFile = file;
        totalPages = result.totalPages;
        rawFirstLines = result.rawFirstLines;
        strippedHeaders = result.strippedHeaders;
      } else {
        // Legacy/test path: small fixture bytes are processed on the main thread
        // (tests cannot pump the isolate in fake-async; this path is not an OOM/ANR scenario).
        final bytes = picked.bytes!;
        hash = sha256.convert(bytes).toString().substring(0, 16);
        file = File('${booksDir.path}/$hash.pdf');
        await file.writeAsBytes(bytes);
        copiedFile = file;
        totalPages = pdfPageCount(bytes);
        final header = PagePipeline.detectRunningHeader(bytes, totalPages);
        final texts = await extractAllPageTexts(bytes);
        rawFirstLines = <String>[];
        strippedHeaders = <String?>[];
        for (final raw in texts) {
          rawFirstLines.add(
            raw
                .trim()
                .split('\n')
                .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
                .trim(),
          );
          strippedHeaders.add(
            stripPageArtifacts(raw, knownHeader: header).strippedHeader,
          );
        }
      }

      final rawEntries = <PageHeaderEntry>[];
      final strippedEntries = <PageHeaderEntry>[];
      for (var i = 0; i < rawFirstLines.length; i++) {
        rawEntries.add(PageHeaderEntry(page: i + 1, header: rawFirstLines[i]));
        strippedEntries.add(
          PageHeaderEntry(page: i + 1, header: strippedHeaders[i]),
        );
      }

      final llmAccess = services.reading.llmAccess;
      List<Chapter> chapters;
      if (llmAccess.isConfigured) {
        try {
          chapters = await LlmSkeleton(
            access: llmAccess,
          ).fetch(headers: rawEntries, totalPages: totalPages);
        } on Exception {
          chapters = buildChapterMap(strippedEntries);
        }
      } else {
        chapters = buildChapterMap(strippedEntries);
      }

      final encoded = encodeChapters(chapters);
      await services.prefs.setString('chapters_$hash', encoded);

      // The book file was already written to its target above (path flow or bytes
      // write) -- it is not written again here.

      // Load the current book list and add the new book
      final rawBooks = services.prefs.getString('books_v1') ?? '[]';
      final books = decodeBooks(rawBooks);
      final newBook = Book(
        id: hash,
        title: picked.name.endsWith('.pdf')
            ? picked.name.substring(0, picked.name.length - 4)
            : picked.name,
        author: '',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: totalPages,
        coverIndex: books.length % 6,
        hash: hash,
        filePath: file.path,
        language: _selectedLanguage,
      );
      books.add(newBook);
      await services.prefs.setString('books_v1', encodeBooks(books));

      if (!mounted) return;
      setState(() {
        _phase = AddPhase.done;
        _newBook = newBook;
      });
    } on Object catch (e) {
      // R4: if a temp/target file may have been written in this round and the book
      // could never be added to books_v1 (an exception from one of the earlier steps),
      // delete it best-effort so no partial record is left. A delete error does not
      // hide the original error (it is swallowed; the user sees the original $e).
      if (tmpFile != null) {
        try {
          if (tmpFile.existsSync()) tmpFile.deleteSync();
        } on Object catch (_) {
          // best-effort
        }
      }
      if (copiedFile != null) {
        try {
          if (copiedFile.existsSync()) copiedFile.deleteSync();
        } on Object catch (_) {
          // best-effort
        }
      }
      if (!mounted) return;
      setState(() {
        _phase = AddPhase.error;
        _errorMessage = 'An error occurred while adding the book: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('ADD TO LIBRARY / New Book'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_phase) {
            AddPhase.idle => _buildIdle(palette),
            AddPhase.processing => _buildProcessing(palette),
            AddPhase.done => _buildDone(palette),
            AddPhase.error => _buildError(palette),
          },
        ),
      ),
    );
  }

  Widget _buildIdle(AppPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: palette.accent, width: 1.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_file, size: 64, color: palette.accent),
              const SizedBox(height: 16),
              Text(
                'Drop your PDF here',
                style: TextStyle(fontSize: 18, color: palette.text),
              ),
              const SizedBox(height: 8),
              Text(
                'or choose one with the button below',
                style: TextStyle(fontSize: 14, color: palette.text2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Phase 2 (English TTS support): language choice BEFORE adding a book --
        // passed as-is to Book.language; default Turkish (existing behavior).
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Turkish'),
              selected: _selectedLanguage == 'tr',
              onSelected: (_) => setState(() => _selectedLanguage = 'tr'),
            ),
            ChoiceChip(
              label: const Text('English'),
              selected: _selectedLanguage == 'en',
              onSelected: (_) => setState(() => _selectedLanguage = 'en'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _pickPdf, child: const Text('Choose file')),
      ],
    );
  }

  Widget _buildProcessing(AppPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 128,
          height: 128,
          child: CircularProgressIndicator(
            strokeWidth: 8,
            color: palette.accent,
            backgroundColor: palette.bg2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Processing…',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Preparing the book for reading',
          style: TextStyle(fontSize: 14, color: palette.text2),
        ),
      ],
    );
  }

  Widget _buildDone(AppPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.accent.withValues(alpha: 0.2),
          ),
          child: Icon(Icons.check, size: 48, color: palette.accent),
        ),
        const SizedBox(height: 16),
        Text(
          'Ready',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _title,
          style: TextStyle(fontSize: 16, color: palette.text2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_newBook),
          child: const Text('Start reading →'),
        ),
      ],
    );
  }

  Widget _buildError(AppPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.accent.withValues(alpha: 0.2),
          ),
          child: Icon(Icons.error_outline, size: 48, color: palette.accent),
        ),
        const SizedBox(height: 16),
        Text(
          'Error',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage,
          style: TextStyle(fontSize: 16, color: palette.text2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _phase = AddPhase.idle;
              _errorMessage = '';
            });
          },
          child: const Text('Try again'),
        ),
      ],
    );
  }
}
