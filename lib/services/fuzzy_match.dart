import 'dart:math';

/// Computes the Levenshtein edit distance between [a] and [b].
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Two-row rolling DP — O(n) space.
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = min(curr[j - 1] + 1, min(prev[j] + 1, prev[j - 1] + cost));
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Returns true when [query] and [candidate] are "fuzzy similar":
///   - exact (case-insensitive) match, or
///   - one is a substring of the other (handles plurals, truncation), or
///   - edit distance ≤ floor(maxLen / 4), clamped to [1, 2], but only when
///     both strings are ≥ 4 characters (avoids false-positive noise on short
///     words like "egg" ↔ "fig").
bool isFuzzyMatch(String query, String candidate) {
  final q = query.toLowerCase().trim();
  final c = candidate.toLowerCase().trim();
  if (q.isEmpty || c.isEmpty) return false;
  if (q == c) return true;
  if (q.contains(c) || c.contains(q)) return true;
  if (q.length < 4 || c.length < 4) return false;
  final maxLen = max(q.length, c.length);
  final threshold = (maxLen / 4).floor().clamp(1, 2);
  return levenshtein(q, c) <= threshold;
}
