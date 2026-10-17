import 'dart:math';

class SuspicionVerdict {
  SuspicionVerdict({required this.reasons}) : suspicious = reasons.isNotEmpty;
  final bool suspicious;
  final List<String> reasons;
}

bool _isInvalidCharacter(int codePoint) {
  return codePoint == 0xFFFD ||
      (codePoint >= 0x0400 && codePoint <= 0x04FF) ||
      (codePoint >= 0x2500 && codePoint <= 0x25FF);
}

double _normalizedLevenshtein(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final alen = a.length;
  final blen = b.length;
  final maxLen = max(alen, blen);
  if (maxLen == 0) return 0;
  final dp = List.generate(alen + 1, (_) => List.filled(blen + 1, 0));
  for (var i = 0; i <= alen; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= blen; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= alen; i++) {
    for (var j = 1; j <= blen; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = min(
        dp[i - 1][j] + 1,
        min(dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost),
      );
    }
  }
  return dp[alen][blen] / maxLen;
}

List<String> _tokenize(String text) {
  return text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

// Line-break hyphen merge: a token ending in '-' is joined with the next token.
// It MUST be applied to BOTH sides (raw + clean); applying it to only one side
// created a token-count asymmetry that produced fake 'ekleme' (insertion) reasons
// (device findings p41/p415/p174).
List<String> _mergeHyphenBreaks(List<String> tokens) {
  final result = <String>[];
  var i = 0;
  while (i < tokens.length) {
    if (tokens[i].endsWith('-') && i + 1 < tokens.length) {
      final merged =
          tokens[i].substring(0, tokens[i].length - 1) + tokens[i + 1];
      result.add(merged);
      i += 2;
    } else {
      result.add(tokens[i]);
      i++;
    }
  }
  return result;
}

bool _matchWords(String a, String b) {
  if (a == b) return true;
  final dist = _normalizedLevenshtein(a, b);
  return dist <= 0.5;
}

SuspicionVerdict assessClean({required String raw, required String clean}) {
  final reasons = <String>[];

  // Length check
  if (raw.isNotEmpty) {
    final ratio = clean.length / raw.length;
    if (ratio < 0.85 || ratio > 1.15) {
      reasons.add('uzunluk');
    }
  }

  // Character check
  final cleanCodes = clean.codeUnits;
  for (final code in cleanCodes) {
    if (_isInvalidCharacter(code)) {
      reasons.add('karakter');
      break;
    }
  }

  // Word alignment
  final rawTokens = _mergeHyphenBreaks(_tokenize(raw));
  final cleanTokens = _mergeHyphenBreaks(_tokenize(clean));
  final m = rawTokens.length;
  final n = cleanTokens.length;

  if (m > 0 && n > 0) {
    if (m == n) {
      var anyMismatch = false;
      for (var i = 0; i < m; i++) {
        if (!_matchWords(rawTokens[i], cleanTokens[i])) {
          anyMismatch = true;
          break;
        }
      }
      if (anyMismatch) {
        reasons.add('degisim');
      }
    } else {
      // DP for LCS with custom match
      final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
      for (var i = 1; i <= m; i++) {
        for (var j = 1; j <= n; j++) {
          final match = _matchWords(rawTokens[i - 1], cleanTokens[j - 1])
              ? 1
              : 0;
          dp[i][j] = max(
            dp[i - 1][j],
            max(dp[i][j - 1], dp[i - 1][j - 1] + match),
          );
        }
      }

      // Backtrack to find matched pairs
      final matchedRaw = List.filled(m, -1);
      final matchedClean = List.filled(n, -1);
      var i = m;
      var j = n;
      while (i > 0 && j > 0) {
        if (_matchWords(rawTokens[i - 1], cleanTokens[j - 1])) {
          matchedRaw[i - 1] = j - 1;
          matchedClean[j - 1] = i - 1;
          i--;
          j--;
        } else if (dp[i - 1][j] >= dp[i][j - 1]) {
          i--;
        } else {
          j--;
        }
      }

      // Collect deletions, insertions
      for (var ri = 0; ri < m; ri++) {
        if (matchedRaw[ri] == -1) {
          reasons.add('silme');
          break;
        }
      }
      for (var ci = 0; ci < n; ci++) {
        if (matchedClean[ci] == -1) {
          reasons.add('ekleme');
          break;
        }
      }
    }
  }

  return SuspicionVerdict(reasons: reasons);
}
