import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

class StudyCard {
  const StudyCard({required this.soru, required this.yanit});
  final String soru;
  final String yanit;
}

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key, this.cards = const [], this.bookHash});

  final List<StudyCard> cards;
  final String? bookHash;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  int _index = 0;
  bool _flipped = false;
  ReviewBank? _bank;
  List<String> _dueIds = [];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBankIfNeeded();
  }

  void _loadBankIfNeeded() {
    if (_initialized) return;
    _initialized = true;

    final hash = widget.bookHash;
    if (hash == null) return; // seed mode

    final services = AppServicesScope.of(context);
    final raw = services.prefs.getString('reviewbank_$hash');
    if (raw == null) return; // seed mode

    try {
      _bank = decodeReviewBank(raw);
    } on FormatException {
      _bank = null; // corrupt record -> fall back to seed
      return;
    }

    if (_bank == null) return;
    final today = daysSinceEpoch(DateTime.now());
    _dueIds = dueIds(_bank!, today);
    _index = 0;
    _flipped = false;
  }

  void _nextCard() {
    if (_bank != null) {
      if (_dueIds.isEmpty) return;
      setState(() {
        _index = (_index + 1) % _dueIds.length;
        _flipped = false;
      });
    } else {
      if (widget.cards.isEmpty) return;
      setState(() {
        _index = (_index + 1) % widget.cards.length;
        _flipped = false;
      });
    }
  }

  Future<void> _onKnewIt() => _mark(knewIt: true);

  /// A1: the "didn't know" path (spaced-repetition wrong -> reset half). "Review
  /// again" is wired to this: applyAnswer(knewIt:false) resets intervalIndex to 0
  /// and sets dueDay to today+1 (due again tomorrow). The twin of _onKnewIt.
  Future<void> _onDidntKnow() => _mark(knewIt: false);

  Future<void> _mark({required bool knewIt}) async {
    if (_bank == null || _dueIds.isEmpty) return;

    final id = _dueIds[_index];
    final today = daysSinceEpoch(DateTime.now());
    final newBank = withAnswer(_bank!, id, knewIt: knewIt, today: today);
    final encoded = encodeReviewBank(newBank);
    final services = AppServicesScope.of(context);
    await services.prefs.setString('reviewbank_${widget.bookHash}', encoded);

    final newDueIds = dueIds(newBank, today);
    setState(() {
      _bank = newBank;
      _dueIds = newDueIds;
      _index = 0;
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    if (_bank != null) {
      if (_dueIds.isEmpty) {
        return _buildEmptyBank(palette);
      }
      final id = _dueIds[_index];
      final question = questionById(_bank!, id)!;
      return _buildCardScreen(
        palette,
        soru: question.soru,
        yanit: question.cevap,
        counter: '${_index + 1} / ${_dueIds.length}',
      );
    }

    // seed mode (bookHash == null, or no/corrupt record)
    if (widget.cards.isEmpty) {
      return _buildEmptySeed(palette);
    }
    final card = widget.cards[_index];
    return _buildCardScreen(
      palette,
      soru: card.soru,
      yanit: card.yanit,
      counter: '${_index + 1} / ${widget.cards.length}',
    );
  }

  Widget _buildEmptyBank(AppPalette palette) {
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: _buildAppBar(palette),
      body: Center(
        child: Text(
          'No cards due for review today',
          style: TextStyle(color: palette.text3),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildEmptySeed(AppPalette palette) {
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: _buildAppBar(palette),
      body: Center(
        child: Text(
          'No study cards yet.',
          style: TextStyle(color: palette.text3),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppPalette palette) {
    return AppBar(
      backgroundColor: palette.surface,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: palette.text),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'STUDY / Spaced repetition',
        style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
      ),
      elevation: 0,
    );
  }

  Widget _buildCardScreen(
    AppPalette palette, {
    required String soru,
    required String yanit,
    required String counter,
  }) {
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: palette.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'STUDY / Spaced repetition',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                counter,
                style: TextStyle(color: palette.text3, fontSize: 14),
              ),
            ),
          ),
        ],
        elevation: 0,
      ),
      // LayoutBuilder + scroll + IntrinsicHeight: when the card text is long,
      // the screen is narrow or the font is large, the Column with Spacers
      // scrolls instead of overflowing. While it fits, the layout (card at the
      // top, centered 1:2) stays the same.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _flipped = !_flipped),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _flipped
                          ? _CardBack(yanit: yanit, palette: palette)
                          : _CardFront(soru: soru, palette: palette),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          // A1: in bank mode "Review again" = didn't know (interval is reset);
                          // in seed mode (no persistence) the old behavior: just advance.
                          onPressed: _bank != null ? _onDidntKnow : _nextCard,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: palette.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Review again',
                            style: TextStyle(color: palette.text),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _bank != null ? _onKnewIt : _nextCard,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: palette.bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('I knew it'),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({required this.soru, required this.palette});

  final String soru;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('front'),
      constraints: const BoxConstraints(minHeight: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'QUESTION',
            style: TextStyle(
              color: palette.text3,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            soru,
            style: TextStyle(
              color: palette.text,
              fontSize: 24,
              fontFamily: serifTextFamily(AppSettingsScope.of(context)),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to flip',
            style: TextStyle(color: palette.text3, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.yanit, required this.palette});

  final String yanit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('back'),
      constraints: const BoxConstraints(minHeight: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ANSWER',
            style: TextStyle(
              color: palette.text3,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            yanit,
            style: TextStyle(
              color: palette.text,
              fontSize: 19,
              fontFamily: serifTextFamily(AppSettingsScope.of(context)),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
