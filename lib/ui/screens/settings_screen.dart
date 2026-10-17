import 'dart:async';
import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:sesli_kitap/ui/widgets/min_tap_area.dart';

String _formatRate(double rate) {
  return '${rate.toStringAsFixed(rate == rate.truncateToDouble() ? 0 : 1)}×';
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final settings = AppSettingsScope.of(context);
    final services = AppServicesScope.of(context);
    final reading = services.reading;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: palette.bg,
        foregroundColor: palette.text,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsSection(
              palette: palette,
              title: 'VOICE',
              children: [
                _SettingsRow(
                  palette: palette,
                  label: 'Voice provider',
                  trailing: const _Chevron(),
                  onTap: () => _showProviderPicker(context, services),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Server voices',
                  trailing: const _Chevron(),
                  subtitle: 'Emel · Ahmet',
                  onTap: () => _showVoicePicker(context, services),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'English server voice',
                  trailing: const _Chevron(),
                  subtitle: 'Sarah · David',
                  onTap: () => _showEnglishVoicePicker(context, services),
                ),
                ListenableBuilder(
                  listenable: reading,
                  builder: (context, _) => _SettingsRow(
                    palette: palette,
                    label: 'Speech rate',
                    trailing: Text(
                      _formatRate(reading.rate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    onTap: () => _showRatePicker(context, services),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              palette: palette,
              title: 'APPEARANCE',
              children: [
                _SettingsSegmentRow(
                  palette: palette,
                  label: 'Theme',
                  segment: _SegmentFullWidth<String>(
                    value: settings.theme == AppTheme.cognac
                        ? 'Cognac'
                        : 'Obsidian',
                    labels: const ['Cognac', 'Obsidian'],
                    onChanged: (value) {
                      settings.setTheme(
                        value == 'Cognac' ? AppTheme.cognac : AppTheme.obsidian,
                      );
                    },
                  ),
                ),
                _SettingsSegmentRow(
                  palette: palette,
                  label: 'Mode',
                  segment: _SegmentFullWidth<AppMode>(
                    value: settings.mode,
                    labels: const ['Dark', 'Light'],
                    values: const [AppMode.dark, AppMode.light],
                    onChanged: settings.setMode,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Text size',
                  naturalTrailing: true,
                  trailing: _FontScaleControl(
                    palette: palette,
                    value: settings.fontScale,
                    onChanged: settings.setFontScale,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'High contrast',
                  trailing: Switch.adaptive(
                    value: settings.highContrast,
                    onChanged: (_) => settings.toggleHighContrast(),
                    activeThumbColor: palette.accent,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Dyslexia-friendly reading',
                  subtitle: 'Lexend font · wide spacing',
                  trailing: Switch.adaptive(
                    value: settings.dyslexia,
                    onChanged: (_) => settings.toggleDyslexia(),
                    activeThumbColor: palette.accent,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Adapt to daylight',
                  trailing: Switch.adaptive(
                    value: settings.daylight,
                    onChanged: (_) => settings.toggleDaylight(),
                    activeThumbColor: palette.accent,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Sound signature',
                  trailing: Switch.adaptive(
                    value: settings.sonic,
                    onChanged: (_) => settings.toggleSonic(),
                    activeThumbColor: palette.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              palette: palette,
              title: 'ASK',
              children: [
                ListenableBuilder(
                  listenable: reading,
                  builder: (context, _) => _SettingsRow(
                    palette: palette,
                    label: 'Ask about a word or sentence',
                    subtitle:
                        'Long-press a sentence while reading · Turkish explanation',
                    trailing: Switch.adaptive(
                      value: reading.askEnabled,
                      onChanged: reading.setAskEnabled,
                      activeThumbColor: palette.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              palette: palette,
              title: 'ACCOUNT & API',
              children: [
                ListenableBuilder(
                  listenable: reading,
                  builder: (context, _) => _SettingsRow(
                    palette: palette,
                    label: 'AI provider',
                    subtitle: LlmChoice.label(reading.llmChoice),
                    trailing: const _Chevron(),
                    onTap: () => _showLlmProviderPicker(context, services),
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Gemini API key',
                  trailing: const _Chevron(),
                  onTap: () => _showApiKeyDialog(
                    context,
                    services,
                    'Gemini',
                    reading.geminiKey,
                    reading.setGeminiKey,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Google API key',
                  trailing: const _Chevron(),
                  onTap: () => _showApiKeyDialog(
                    context,
                    services,
                    'Google',
                    reading.googleKey,
                    reading.setGoogleKey,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'DeepSeek API key',
                  trailing: const _Chevron(),
                  onTap: () => _showApiKeyDialog(
                    context,
                    services,
                    'DeepSeek',
                    reading.deepseekApiKey,
                    reading.setDeepseekApiKey,
                  ),
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'NVIDIA API key',
                  trailing: const _Chevron(),
                  onTap: () => _showApiKeyDialog(
                    context,
                    services,
                    'NVIDIA',
                    reading.nvidiaApiKey,
                    reading.setNvidiaApiKey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              palette: palette,
              title: 'PRONUNCIATION DICTIONARY',
              children: [
                ListenableBuilder(
                  listenable: reading,
                  builder: (context, _) {
                    final raw = reading.pronRulesRaw;
                    if (raw.isEmpty) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SettingsRow(
                            palette: palette,
                            label: 'GPT',
                            subtitle: 'ci-pi-ti',
                          ),
                          _SettingsRow(
                            palette: palette,
                            label: 'Nietzsche',
                            subtitle: 'niçe',
                          ),
                        ],
                      );
                    }
                    final rules = parsePronRules(raw);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: rules
                          .map(
                            (r) => _SettingsRow(
                              palette: palette,
                              label: r.from,
                              subtitle: r.to,
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                _SettingsRow(
                  palette: palette,
                  label: 'Add new pronunciation',
                  trailing: const _Chevron(),
                  onTap: () => _showPronunciationDialog(context, services),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLlmProviderPicker(BuildContext context, AppServices services) {
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('AI provider'),
        children: [
          for (final choice in LlmChoice.values)
            SimpleDialogOption(
              onPressed: () {
                services.reading.setLlmChoice(choice);
                Navigator.pop(ctx);
              },
              child: Text(LlmChoice.label(choice)),
            ),
        ],
      ),
    );
    unawaited(pending);
  }

  void _showProviderPicker(BuildContext context, AppServices services) {
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Voice provider'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              services.reading.setProvider('edge');
              Navigator.pop(ctx);
            },
            child: const Text('Edge'),
          ),
          SimpleDialogOption(
            onPressed: () {
              services.reading.setProvider('azure');
              Navigator.pop(ctx);
            },
            child: const Text('Azure'),
          ),
          SimpleDialogOption(
            onPressed: () {
              services.reading.setProvider('google');
              Navigator.pop(ctx);
            },
            child: const Text('Google'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  void _showVoicePicker(BuildContext context, AppServices services) {
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Server voices'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              services.reading.setVoice(voiceId(SesliVoice.ahmet));
              Navigator.pop(ctx);
            },
            child: const Text('Ahmet'),
          ),
          SimpleDialogOption(
            onPressed: () {
              services.reading.setVoice(voiceId(SesliVoice.emel));
              Navigator.pop(ctx);
            },
            child: const Text('Emel'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  /// Phase 2 (English TTS support): a separate voice preference for English books.
  /// (_showVoicePicker is for Turkish; the two are never mixed -- ReadingSettings.voiceEn).
  void _showEnglishVoicePicker(BuildContext context, AppServices services) {
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('English server voice'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              services.reading.setVoiceEn(voiceId(SesliVoice.enWavenetD));
              Navigator.pop(ctx);
            },
            child: const Text('David'),
          ),
          SimpleDialogOption(
            onPressed: () {
              services.reading.setVoiceEn(voiceId(SesliVoice.enWavenetF));
              Navigator.pop(ctx);
            },
            child: const Text('Sarah'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  void _showRatePicker(BuildContext context, AppServices services) {
    final reading = services.reading;
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Speech rate'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              reading.setRate(0.8);
              Navigator.pop(ctx);
            },
            child: const Text('0.8×'),
          ),
          SimpleDialogOption(
            onPressed: () {
              reading.setRate(1);
              Navigator.pop(ctx);
            },
            child: const Text('1×'),
          ),
          SimpleDialogOption(
            onPressed: () {
              reading.setRate(1.25);
              Navigator.pop(ctx);
            },
            child: const Text('1.25×'),
          ),
          SimpleDialogOption(
            onPressed: () {
              reading.setRate(1.5);
              Navigator.pop(ctx);
            },
            child: const Text('1.5×'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  void _showApiKeyDialog(
    BuildContext context,
    AppServices services,
    String label,
    String currentValue,
    void Function(String) onSave,
  ) {
    final ctrl = TextEditingController(text: currentValue);
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label API key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'API key'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onSave(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  void _showPronunciationDialog(BuildContext context, AppServices services) {
    final reading = services.reading;
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    String? error;

    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add new pronunciation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fromCtrl,
                decoration: const InputDecoration(labelText: 'Misread word'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toCtrl,
                decoration: const InputDecoration(
                  labelText: 'Correct pronunciation',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final from = fromCtrl.text.trim();
                final to = toCtrl.text.trim();
                final currentRaw = reading.pronRulesRaw;
                final candidateRaw = currentRaw.isEmpty
                    ? '$from=$to'
                    : '$currentRaw\n$from=$to';
                try {
                  parsePronRules(candidateRaw);
                  // success
                  reading.setPronRulesRaw(candidateRaw);
                  Navigator.pop(ctx);
                } on PronRuleParseException catch (e) {
                  setState(() {
                    error = e.message;
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    unawaited(pending);
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.palette,
    required this.title,
    required this.children,
  });
  final AppPalette palette;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.text3,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.palette,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.naturalTrailing = false,
  });
  final AppPalette palette;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// true: [trailing] takes its natural width and the label takes the rest
  /// (default: the two split the row evenly; the 48dp -/+ buttons do not fit in half).
  final bool naturalTrailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: palette.text2),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              naturalTrailing ? trailing! : Flexible(child: trailing!),
          ],
        ),
      ),
    );
  }
}

class _SettingsSegmentRow extends StatelessWidget {
  const _SettingsSegmentRow({
    required this.palette,
    required this.label,
    required this.segment,
  });
  final AppPalette palette;
  final String label;
  final Widget segment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          segment,
        ],
      ),
    );
  }
}

class _SegmentFullWidth<T> extends StatelessWidget {
  const _SegmentFullWidth({
    required this.value,
    required this.labels,
    required this.onChanged,
    this.values,
  });
  final T value;
  final List<String> labels;
  final List<T>? values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Row(
      children: List.generate(labels.length, (index) {
        final itemValue = values != null ? values![index] : labels[index] as T;
        final isSelected = value == itemValue;
        return Expanded(
          // 48dp tap target: the visual pill (8dp vertical padding, full width) is
          // UNCHANGED; an invisible area around it brings the height up to 48.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(itemValue),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.accentSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? palette.accent : palette.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Icon(Icons.chevron_right, size: 20, color: palette.text3);
  }
}

class _FontScaleControl extends StatelessWidget {
  const _FontScaleControl({
    required this.palette,
    required this.value,
    required this.onChanged,
  });
  final AppPalette palette;
  final double value;
  final ValueChanged<double> onChanged;

  String get _label {
    if (value <= 0.9) return 'Small';
    if (value <= 1.1) return 'Medium';
    if (value <= 1.35) return 'Large';
    return 'Largest';
  }

  @override
  Widget build(BuildContext context) {
    // The -/+ buttons have a 48dp tap target (the visual 32dp box is the same); 48-32=16 ->
    // an invisible 8dp gap on each side replaces the old 8dp spacing.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Decrease text size',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final newValue = value - 0.25;
              if (newValue >= 0.75) {
                onChanged(newValue.clamp(0.75, 1.5));
              }
            },
            child: MinTapArea(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.remove, size: 20, color: palette.text),
              ),
            ),
          ),
        ),
        Text(
          _label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: palette.text,
          ),
        ),
        Semantics(
          button: true,
          label: 'Increase text size',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final newValue = value + 0.25;
              if (newValue <= 1.5) {
                onChanged(newValue.clamp(0.75, 1.5));
              }
            },
            child: MinTapArea(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add, size: 20, color: palette.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
