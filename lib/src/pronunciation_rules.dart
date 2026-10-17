class PronRule {
  const PronRule({required this.from, required this.to});
  final String from;
  final String to;
}

class PronRuleParseException implements Exception {
  PronRuleParseException(this.message, this.lineNumber);
  final String message;
  final int lineNumber;

  @override
  String toString() => 'Line $lineNumber: $message';
}

List<PronRule> parsePronRules(String raw) {
  final lines = raw.split('\n');
  final rules = <PronRule>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.contains('=')) {
      throw PronRuleParseException('Missing "="', i + 1);
    }
    final eqIndex = line.indexOf('=');
    final from = line.substring(0, eqIndex).trim();
    if (from.isEmpty) {
      throw PronRuleParseException('Empty "from" part', i + 1);
    }
    final to = line.substring(eqIndex + 1).trim();
    rules.add(PronRule(from: from, to: to));
  }
  return rules;
}

String applyPronRules(String text, List<PronRule> rules) {
  if (rules.isEmpty) return text;

  final wordChars = <String>{
    for (final ch
        in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789çğıöşüÇĞİÖŞÜâîûÂÎÛ'
            .split(''))
      ch,
  };

  bool isWordChar(String ch) => wordChars.contains(ch);

  var result = text;
  var skipApplied = false;
  var i = 0;

  while (i < result.length) {
    var matched = false;
    for (final rule in rules) {
      final from = rule.from;
      if (i + from.length > result.length) continue;
      if (result.substring(i, i + from.length) != from) continue;

      // left boundary
      if (from.isNotEmpty && isWordChar(from[0])) {
        if (i > 0 && isWordChar(result[i - 1])) continue;
      }
      // right boundary
      if (from.isNotEmpty && isWordChar(from[from.length - 1])) {
        if (i + from.length < result.length &&
            isWordChar(result[i + from.length])) {
          continue;
        }
      }

      // match found
      final replacement = rule.to;
      if (replacement.isEmpty) {
        skipApplied = true;
      }
      result =
          result.substring(0, i) +
          replacement +
          result.substring(i + from.length);
      i += replacement.length;
      matched = true;
      break;
    }
    if (!matched) {
      i++;
    }
  }

  if (skipApplied) {
    while (result.contains('  ')) {
      result = result.replaceAll('  ', ' ');
    }
  }
  return result;
}

String pronRulesTag(List<PronRule> rules) {
  if (rules.isEmpty) return '';
  var hash = 0x811c9dc5; // FNV offset basis 32-bit
  for (final rule in rules) {
    final combined = '${rule.from}|${rule.to}|';
    for (final codeUnit in combined.codeUnits) {
      hash ^= codeUnit;
      hash *= 0x01000193; // FNV prime 32-bit
      hash &= 0xFFFFFFFF; // Keep 32-bit
    }
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
