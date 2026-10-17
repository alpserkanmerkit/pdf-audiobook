// lib/ui/screens/quiz_choice_screen.dart

import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

class QuizChoiceScreen extends StatefulWidget {
  const QuizChoiceScreen({
    required this.sorular,
    super.key,
    this.onCompleted,
    this.onFinish,
  });

  final List<MultipleChoiceQuestion> sorular;

  /// Called once when the quiz is completed, with the correctness of each
  /// question (in question order). The caller (quiz_screen) writes it to
  /// reviewbank_[hash].
  final void Function(List<bool> dogrular)? onCompleted;

  /// Called by "Finish" on the completion panel. The caller (quiz_screen)
  /// returns to the generation screen so the panel is not a dead end
  /// ("Study cards" stays reachable).
  final VoidCallback? onFinish;

  @override
  State<QuizChoiceScreen> createState() => _QuizChoiceScreenState();
}

class _QuizChoiceScreenState extends State<QuizChoiceScreen> {
  late QuizChoiceState _state;
  bool _bildirildi = false;

  @override
  void initState() {
    super.initState();
    _state = QuizChoiceState.initial(widget.sorular);
  }

  void _dispatch(QuizChoiceEvent e) {
    setState(() {
      _state = quizChoiceTransition(_state, e);
    });
    if (_state.tamamlandi && !_bildirildi) {
      _bildirildi = true;
      widget.onCompleted?.call(
        _state.dogrular.map((d) => d ?? false).toList(growable: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    if (_state.tamamlandi) {
      return _buildCompletion(palette);
    }

    final gecerli = _state.gecerliSoru;

    if (gecerli == null) {
      return const Center(child: Text('No questions yet'));
    }

    final dogruIndex = gecerli.dogruIndex;
    final yanitlandi = _state.yanitlandi;

    const letters = ['A', 'B', 'C', 'D'];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'STUDY',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: palette.text3,
                    ),
                  ),
                  Text(
                    _state.ilerlemeEtiketi,
                    style: TextStyle(fontSize: 14, color: palette.text3),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Question and options: scrollable so long text does not overflow
              // (the bottom "Next" button always stays fixed and reachable).
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Question
                      Text(
                        'QUESTION —',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        gecerli.soru,
                        style: TextStyle(
                          fontSize: 25,
                          fontFamily: serifDisplayFamily(
                            AppSettingsScope.of(context),
                          ),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Options
                      ...List.generate(4, (i) {
                        final isCorrect = i == dogruIndex;
                        Color boxBackground;
                        Color boxBorder;
                        Color labelBackground;
                        Color labelTextColor;
                        if (yanitlandi) {
                          if (isCorrect) {
                            boxBackground = palette.accentSoft;
                            boxBorder = palette.accent;
                            labelBackground = palette.accent;
                            labelTextColor = palette.text;
                          } else {
                            boxBackground = Colors.transparent;
                            boxBorder = palette.text3;
                            labelBackground = palette.text3;
                            labelTextColor = palette.text;
                          }
                        } else {
                          boxBackground = Colors.transparent;
                          boxBorder = palette.surface;
                          labelBackground = palette.surface;
                          labelTextColor = palette.text;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () {
                              if (!yanitlandi) {
                                _dispatch(ChoiceSelected(i));
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: boxBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: boxBorder,
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  // Badge
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: labelBackground,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      letters[i],
                                      style: TextStyle(
                                        color: labelTextColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      gecerli.secenekler[i],
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: yanitlandi && !isCorrect
                                            ? palette.text3
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (yanitlandi && isCorrect)
                                    Icon(
                                      Icons.check_circle,
                                      color: palette.text,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Bottom message
              if (yanitlandi) ...[
                Text(
                  'Source · ${gecerli.kaynak}',
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.text3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.text,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _dispatch(const NextRequested()),
                  child: const Text('Next →'),
                ),
              ] else ...[
                Text(
                  'Choose an answer — no need to rush',
                  style: TextStyle(fontSize: 14, color: palette.text3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletion(AppPalette palette) {
    final toplam = _state.sorular.length;
    final dogru = _state.dogruSayisi;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 56,
                  color: palette.accent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Quiz completed',
                  style: TextStyle(
                    fontSize: 22,
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$dogru / $toplam correct',
                  style: TextStyle(fontSize: 16, color: palette.text2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Results have been saved to your learning bank.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.text3),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  key: const Key('quiz-finish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.onFinish,
                  child: const Text('Finish'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
