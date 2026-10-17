// Phase 2 (English TTS support): enWavenetD/enWavenetF are 1 male + 1 female
// English voice on Google Cloud TTS (works with the currently verified Google key).
// Google only -- the Microsoft/Edge side is out of scope in this wave.
enum SesliVoice {
  ahmet,
  emel,
  wavenetB,
  aoede,
  wavenetE,
  wavenetC,
  enWavenetD,
  enWavenetF,
}

String voiceId(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.ahmet:
      return 'tr-TR-AhmetNeural';
    case SesliVoice.emel:
      return 'tr-TR-EmelNeural';
    case SesliVoice.wavenetB:
      return 'tr-TR-Wavenet-B';
    case SesliVoice.aoede:
      return 'tr-TR-Chirp3-HD-Aoede';
    case SesliVoice.wavenetE:
      return 'tr-TR-Wavenet-E';
    case SesliVoice.wavenetC:
      return 'tr-TR-Wavenet-C';
    case SesliVoice.enWavenetD:
      return 'en-US-Wavenet-D';
    case SesliVoice.enWavenetF:
      return 'en-US-Wavenet-F';
  }
}

/// Locale sent in the SSML `xml:lang` / Google `languageCode` fields.
/// Phase 2: the fixed tr-TR was removed -- the single source of truth is the VOICE
/// ITSELF (a separate Book.language parameter never leaks into the TTS layer).
String localeCodeOf(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.ahmet:
    case SesliVoice.emel:
    case SesliVoice.wavenetB:
    case SesliVoice.aoede:
    case SesliVoice.wavenetE:
    case SesliVoice.wavenetC:
      return 'tr-TR';
    case SesliVoice.enWavenetD:
    case SesliVoice.enWavenetF:
      return 'en-US';
  }
}

/// TTS provider kind (Phase 3b K24): SesliVoice mixes Microsoft (AhmetNeural/
/// EmelNeural) and Google (Wavenet/Chirp3) identities; this is a pure metadata
/// tag so adapters do not pass an unlabeled identity through blindly.
enum TtsProviderKind { microsoft, google }

/// Maps every [SesliVoice] to its TTS provider (exhaustive switch: the compiler
/// requires a label when a new voice is added).
TtsProviderKind providerOf(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.ahmet:
    case SesliVoice.emel:
      return TtsProviderKind.microsoft;
    case SesliVoice.wavenetB:
    case SesliVoice.aoede:
    case SesliVoice.wavenetE:
    case SesliVoice.wavenetC:
    case SesliVoice.enWavenetD:
    case SesliVoice.enWavenetF:
      return TtsProviderKind.google;
  }
}

/// Returns the voice identity to SEND to Google Cloud TTS (Bug-G fix).
/// [voiceId] mixes Microsoft (Edge/Azure) and Google identities as-is;
/// if the Google provider is selected with a Microsoft-family voice (ahmet/emel),
/// the raw [voiceId] sends Google an UNDEFINED name such as "tr-TR-AhmetNeural"
/// and the API returns 400 INVALID_ARGUMENT ("Voice ... does not exist")
/// (verified with curl). This function returns a VALID Google voice identity for
/// EVERY [SesliVoice]: Google-family voices pass through unchanged; Microsoft-family
/// voices are mapped to a gender-matched, ear-approved Google counterpart (the same
/// 4 voices chosen for voiceForSpeaker) -- ahmet (male) -> Wavenet-B (male),
/// emel (female) -> Aoede (female).
String googleVoiceId(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.ahmet:
      return voiceId(SesliVoice.wavenetB);
    case SesliVoice.emel:
      return voiceId(SesliVoice.aoede);
    case SesliVoice.wavenetB:
    case SesliVoice.aoede:
    case SesliVoice.wavenetE:
    case SesliVoice.wavenetC:
    case SesliVoice.enWavenetD:
    case SesliVoice.enWavenetF:
      return voiceId(voice);
  }
}

/// Returns the voice identity to SEND to Edge (Microsoft) TTS (Package A1: TTS
/// synthesis resilience -- because a single TurnFailed in discussion_machine.dart
/// drops the WHOLE discussion to 'failed', the screen falls back to Edge when Google
/// fails). The MIRROR of [googleVoiceId]: [voiceId] mixes Microsoft-family
/// (ahmet/emel) AND Google-family (wavenet/chirp/English) identities; if a
/// Google-family voice (e.g. the 4 discussion speakers -- see voiceForSpeaker) is
/// sent to Edge as-is, Edge receives a name it does NOT recognize (e.g.
/// 'tr-TR-Wavenet-B') and the provider silently returns a "no voice" error (the
/// mirror of Bug-G -- see the resolveTtsProvider comment in page_pipeline.dart).
/// This function returns a VALID Edge identity for EVERY [SesliVoice]: Microsoft-family
/// voices pass through unchanged; Google-family (and English) voices are mapped to a
/// gender-matched Edge counterpart -- male voices (Wavenet-B, Wavenet-E, en-Wavenet-D)
/// -> AhmetNeural; female voices (Aoede, Wavenet-C, en-Wavenet-F) -> EmelNeural
/// (the gender mapping comes from the SAME source as 'voiceForSpeaker (Slice-2: 4-voice Google)'
/// in discussion_turn_test.dart: A/C male, B/D female).
String edgeVoiceId(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.ahmet:
    case SesliVoice.emel:
      return voiceId(voice);
    case SesliVoice.wavenetB:
    case SesliVoice.wavenetE:
    case SesliVoice.enWavenetD:
      return voiceId(SesliVoice.ahmet);
    case SesliVoice.aoede:
    case SesliVoice.wavenetC:
    case SesliVoice.enWavenetF:
      return voiceId(SesliVoice.emel);
  }
}

/// The Reader's actual decision point (Phase 2): purely determines WHICH [SesliVoice]
/// and WHICH TTS provider to use, from the book's language and the user's general
/// (Turkish) and English voice preferences.
///
/// If [bookLanguage] is 'en', the returned provider is ALWAYS 'google' --
/// [preferredProvider] (the general provider the user chose for Turkish reading,
/// e.g. 'edge') is IGNORED, because English voices currently exist only on Google
/// (sending a Google-style voiceId to Edge/Azure gives an invalid result).
({SesliVoice voice, String provider}) resolveReadingVoice({
  required String bookLanguage,
  required String preferredVoiceId,
  required String preferredProvider,
  required String preferredEnglishVoiceId,
}) {
  if (bookLanguage == 'en') {
    final voice = SesliVoice.values.firstWhere(
      (v) => voiceId(v) == preferredEnglishVoiceId,
      orElse: () => SesliVoice.enWavenetD,
    );
    return (voice: voice, provider: 'google');
  }
  final voice = SesliVoice.values.firstWhere(
    (v) => voiceId(v) == preferredVoiceId,
    orElse: () => SesliVoice.ahmet,
  );
  return (voice: voice, provider: preferredProvider);
}

/// Gemini TTS prebuilt voice name (the user approved the 4-person sample by ear on
/// 2026-09-28). The discussion's 4 speakers via voiceForSpeaker:
/// A Ahmet=Charon, B Emel=Aoede, C Deniz=Gacrux, D Kaya=Puck. Other voices fall
/// back to the gender-matched Charon/Aoede.
String geminiVoiceName(SesliVoice voice) {
  switch (voice) {
    case SesliVoice.wavenetB:
    case SesliVoice.ahmet:
    case SesliVoice.enWavenetD:
      return 'Charon';
    case SesliVoice.aoede:
    case SesliVoice.emel:
    case SesliVoice.enWavenetF:
      return 'Aoede';
    case SesliVoice.wavenetE:
      return 'Gacrux';
    case SesliVoice.wavenetC:
      return 'Puck';
  }
}

String formatRate(double rate) {
  if (rate <= 0) throw ArgumentError('Rate must be positive');
  final percent = ((rate - 1) * 100).round();
  final sign = percent >= 0 ? '+' : '';
  return '$sign$percent%';
}
