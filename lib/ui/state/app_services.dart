import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:sesli_kitap/io/audio_playback.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/llm_tutor.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Description of the picked PDF. TWO separate shapes are supported:
/// - [path] set, [bytes] null: the file_picker withData:false path (185MB OOM
///   fix, 2026-07-04) -- at PICK time the file is NOT loaded into memory; only the path
///   is carried (file_picker's old Java-heap copy is dropped). The import
///   runs in a separate isolate (see add_book_screen.dart
///   _importPdfInIsolate); copying uses a 64KB buffer; the syncfusion parse
///   reads whole bytes as its parsing contract requires, but is isolated from the MAIN heap.
/// - [bytes] set, [path] null: the old/test path (small fixtures, a fake picker
///   without touching the real file system) -- kept for backward compatibility.
/// Both cannot be empty (assert; the caller must provide at least one).
class PickedBook {
  const PickedBook({required this.name, this.bytes, this.path})
    : assert(
        bytes != null || path != null,
        'PickedBook: bytes or path -- at least one must be set',
      );
  final String name;
  final Uint8List? bytes;
  final String? path;
}

class AppServices {
  AppServices({
    required this.prefs,
    required this.dataDir,
    AudioPlayerOps Function()? playerOpsFactory,
    Future<PickedBook?> Function()? pickPdf,
    TutorLlm Function()? tutorLlmFactory,
  }) : _playerOpsFactory = playerOpsFactory,
       _pickPdf = pickPdf,
       _tutorLlmFactory = tutorLlmFactory;

  final SharedPreferences prefs;
  final Directory dataDir;
  final AudioPlayerOps Function()? _playerOpsFactory;
  final Future<PickedBook?> Function()? _pickPdf;
  final TutorLlm Function()? _tutorLlmFactory;

  late final CacheStore cache = CacheStore(
    Directory('${dataDir.path}/sesli_kitap_cache')..createSync(recursive: true),
  );

  GuardedAudioPlayer? _reader;
  GuardedAudioPlayer? _discussion;

  GuardedAudioPlayer get readerPlayer =>
      _reader ??= GuardedAudioPlayer(ops: _playerOpsFactory?.call());
  GuardedAudioPlayer get discussionPlayer =>
      _discussion ??= GuardedAudioPlayer(ops: _playerOpsFactory?.call());

  late final ReadingSettings reading = ReadingSettings(prefs);

  Future<void> disposePlayers() async {
    if (_reader != null) {
      await _reader!.dispose();
    }
    if (_discussion != null) {
      await _discussion!.dispose();
    }
  }

  // OOM FIX (2026-07-04): withData:true made file_picker, on Android,
  // read the file into ONE Java ByteArray(size) (see FileUtils.kt loadData()
  // in the file_picker package). For a 185MB PDF this
  // grew the Java heap by ~402MB and the app was killed with OutOfMemoryError
  // (FAZ-3 live crash, 15:34). With withData:false, file_picker returns only the path
  // (its internal copy step already works with a stream/buffer, 8KB at a time,
  // so no extra Java-heap copy is ever made.
  Future<PickedBook?> _defaultPickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (result == null || path == null) return null;
    return PickedBook(name: result.files.single.name, path: path);
  }

  /// Tutor LLM. If a test seam (`tutorLlmFactory`) exists, use what it returns;
  /// otherwise null if the Gemini key is empty (the screen shows the "no key" error;
  /// no network call is made); if set, the real [LlmTutor].
  TutorLlm? tutorLlm() {
    final factory = _tutorLlmFactory;
    if (factory != null) return factory();
    final access = reading.llmAccess;
    if (!access.isConfigured) return null;
    return LlmTutor(access: access).complete;
  }

  Future<PickedBook?> pickPdf() async {
    if (_pickPdf != null) return _pickPdf();
    return _defaultPickPdf();
  }
}

class ReadingSettings extends ChangeNotifier {
  ReadingSettings(this._prefs);

  final SharedPreferences _prefs;

  /// SharedPreferences key of the old version (kept for migration; deleted).
  static const String legacyDeepseekPrefKey = 'deepseekKey';

  /// SharedPreferences key of the previous version (NVIDIA) (for the Gemini migration;
  /// deleted -- the same pattern as deepseekKey).
  static const String legacyNvidiaPrefKey = 'nvidiaKey';

  String geminiKey = '';
  String googleKey = '';

  /// AI provider choice ([LlmChoice]); default is Gemini.
  String llmChoice = LlmChoice.gemini;

  /// DeepSeek / NVIDIA keys. Their pref names are DIFFERENT from
  /// 'deepseekKey'/'nvidiaKey' that the old migration deletes; that migration stays as it is.
  String deepseekApiKey = '';
  String nvidiaApiKey = '';

  /// Providers to try, in order (those with an empty key are skipped).
  LlmAccess get llmAccess => LlmAccess.fromSettings(
    choice: llmChoice,
    geminiKey: geminiKey,
    deepseekKey: deepseekApiKey,
    nvidiaKey: nvidiaApiKey,
  );
  String provider = 'edge';
  String voice = '';

  /// Phase 2 (English TTS support): the preferred voice for English books
  /// (David/Sarah). It is kept SEPARATE from the [voice] field -- they are preferences for different
  /// languages and must not overwrite each other.
  String voiceEn = '';
  double rate = 1;
  String pronRulesRaw = '';

  /// The "Ask" feature (long-press a sentence in the reader -> word or sentence explanation)
  /// on or off. Default on; when off, a long-press is a silent no-op.
  bool askEnabled = true;

  void load() {
    // Migration: delete an old 'deepseekKey' if present (invalid for NVIDIA); do not copy it.
    if (_prefs.containsKey(legacyDeepseekPrefKey)) {
      unawaited(_prefs.remove(legacyDeepseekPrefKey));
    }
    // Migration: delete an old 'nvidiaKey' if present (invalid for Gemini); do not copy it.
    if (_prefs.containsKey(legacyNvidiaPrefKey)) {
      unawaited(_prefs.remove(legacyNvidiaPrefKey));
    }
    geminiKey = _prefs.getString('geminiKey') ?? geminiKey;
    googleKey = _prefs.getString('googleKey') ?? googleKey;
    llmChoice = _prefs.getString('llmProvider') ?? llmChoice;
    deepseekApiKey = _prefs.getString('deepseekApiKey') ?? deepseekApiKey;
    nvidiaApiKey = _prefs.getString('nvidiaApiKey') ?? nvidiaApiKey;
    provider = _prefs.getString('provider') ?? provider;
    voice = _prefs.getString('voice') ?? voice;
    voiceEn = _prefs.getString('voiceEn') ?? voiceEn;
    rate = _prefs.getDouble('rate') ?? rate;
    pronRulesRaw = _prefs.getString('pronRules') ?? pronRulesRaw;
    askEnabled = _prefs.getBool('askEnabled') ?? askEnabled;
    notifyListeners();
  }

  // Persistence: every setter writes its value to prefs IMMEDIATELY (there is no
  // separate save(); the old save() was never called and was removed on 2026-09-28).
  void setProvider(String v) {
    provider = v;
    unawaited(_prefs.setString('provider', v));
    notifyListeners();
  }

  void setGeminiKey(String v) {
    geminiKey = v;
    unawaited(_prefs.setString('geminiKey', v));
    notifyListeners();
  }

  void setLlmChoice(String v) {
    llmChoice = v;
    unawaited(_prefs.setString('llmProvider', v));
    notifyListeners();
  }

  void setDeepseekApiKey(String v) {
    deepseekApiKey = v;
    unawaited(_prefs.setString('deepseekApiKey', v));
    notifyListeners();
  }

  void setNvidiaApiKey(String v) {
    nvidiaApiKey = v;
    unawaited(_prefs.setString('nvidiaApiKey', v));
    notifyListeners();
  }

  void setGoogleKey(String v) {
    googleKey = v;
    unawaited(_prefs.setString('googleKey', v));
    notifyListeners();
  }

  void setVoice(String v) {
    voice = v;
    unawaited(_prefs.setString('voice', v));
    notifyListeners();
  }

  void setVoiceEn(String v) {
    voiceEn = v;
    unawaited(_prefs.setString('voiceEn', v));
    notifyListeners();
  }

  void setRate(double v) {
    rate = v;
    unawaited(_prefs.setDouble('rate', v));
    notifyListeners();
  }

  void setPronRulesRaw(String v) {
    pronRulesRaw = v;
    unawaited(_prefs.setString('pronRules', v));
    notifyListeners();
  }

  // Used as a Switch.onChanged (ValueChanged<bool>) tear-off, so the positional parameter is required.
  // ignore: avoid_positional_boolean_parameters
  void setAskEnabled(bool v) {
    askEnabled = v;
    unawaited(_prefs.setBool('askEnabled', v));
    notifyListeners();
  }
}

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    required this.services,
    required super.child,
    super.key,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppServicesScope>();
    assert(s != null, 'AppServicesScope not found');
    return s!.services;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      services != oldWidget.services;
}
