// "Ask" bottom sheet: for the tapped sentence, "ask about the sentence" or a word chip
// choice -> fetchExplanation -> Turkish explanation text (+ speak, if given, reads it aloud).
// Fetch and speak come in via DI (widget-test fakes; the real
// LLM/TTS connection lives in the reader wiring).
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/explanation/explanation.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

/// Returns the in-context Turkish explanation of the chosen target
/// ([isWord] true: a single word, false: the whole sentence).
typedef ExplanationFetcher =
    Future<String> Function({required String target, required bool isWord});

class ExplanationSheet extends StatefulWidget {
  const ExplanationSheet({
    required this.sentence,
    required this.fetchExplanation,
    super.key,
    this.speak,
  });

  final String sentence;
  final ExplanationFetcher fetchExplanation;

  /// If given, the answer is read aloud when it arrives (best effort: a speech
  /// error does NOT block the answer, the text is already on screen); null = silent.
  final Future<void> Function(String text)? speak;

  @override
  State<ExplanationSheet> createState() => _ExplanationSheetState();
}

enum _AskPhase { select, loading, ready, error }

class _ExplanationSheetState extends State<ExplanationSheet> {
  _AskPhase _phase = _AskPhase.select;
  String _answer = '';
  String _error = '';

  /// Last asked target (for retry).
  String? _lastTarget;
  bool _lastIsWord = false;

  Future<void> _ask(String target, {required bool isWord}) async {
    _lastTarget = target;
    _lastIsWord = isWord;
    setState(() {
      _phase = _AskPhase.loading;
    });
    try {
      final answer = await widget.fetchExplanation(
        target: target,
        isWord: isWord,
      );
      if (!mounted) return;
      setState(() {
        _phase = _AskPhase.ready;
        _answer = answer;
      });
      _speak(answer);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _AskPhase.error;
        _error = '$e';
      });
    }
  }

  /// Best-effort speech: every sync or async error is swallowed --
  /// the explanation text is already on screen; the audio is only an add-on.
  void _speak(String text) {
    final speak = widget.speak;
    if (speak == null) return;
    try {
      unawaited(speak(text).catchError((Object _) {}));
    } on Object catch (_) {
      // synchronous throws are also swallowed on a best-effort basis
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What did they mean here?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.sentence,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 16),
              ..._buildPhase(palette),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPhase(AppPalette palette) {
    switch (_phase) {
      case _AskPhase.select:
        final words = explainableWords(widget.sentence);
        return [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('ask-sentence'),
              onPressed: () => _ask(widget.sentence, isWord: false),
              icon: const Icon(Icons.help_outline, size: 20),
              label: const Text('What does this sentence mean?'),
            ),
          ),
          if (words.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'OR ASK ABOUT A WORD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: palette.text3,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < words.length; i++)
                  ActionChip(
                    key: Key('word-chip-$i'),
                    label: Text(words[i]),
                    onPressed: () => _ask(words[i], isWord: true),
                  ),
              ],
            ),
          ],
        ];
      case _AskPhase.loading:
        return [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Preparing explanation…',
                style: TextStyle(fontSize: 14, color: palette.text2),
              ),
            ],
          ),
        ];
      case _AskPhase.ready:
        return [
          Text(
            _lastIsWord
                ? '"$_lastTarget" in this context:'
                : 'Meaning of the sentence:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _answer,
            style: TextStyle(fontSize: 15, height: 1.5, color: palette.text),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (widget.speak != null)
                TextButton.icon(
                  key: const Key('speak-again'),
                  onPressed: () => _speak(_answer),
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text('Read aloud again'),
                ),
              TextButton(
                key: const Key('ask-back'),
                onPressed: () => setState(() {
                  _phase = _AskPhase.select;
                }),
                child: const Text('Ask something else'),
              ),
            ],
          ),
        ];
      case _AskPhase.error:
        return [
          Text(
            'Could not get an explanation: $_error',
            style: const TextStyle(fontSize: 14, color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('ask-retry'),
            onPressed: () {
              final t = _lastTarget;
              if (t != null) unawaited(_ask(t, isWord: _lastIsWord));
            },
            child: const Text('Try again'),
          ),
        ];
    }
  }
}
