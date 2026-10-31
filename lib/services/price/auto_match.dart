import '../../models/price_link.dart';
import '../../models/price_product.dart';
import 'price_compare.dart';

/// How sure the matcher is about one store's picks.
enum MatchConfidence { high, low, none }

class AutoMatchResult {
  /// [LinkMode.anyOf] when either store has several picks, else
  /// [LinkMode.exact]. An auto no-match is just an empty list; the unavailable
  /// flags are never set (those are the user's call).
  final PriceLink link;

  /// The brand the item name locked to (lowercase label, e.g. 'heinz'), or
  /// 'asda' for own-brand at Asda. Null when no brand was named.
  final String? brand;
  final MatchConfidence asdaConfidence;
  final MatchConfidence costcoConfidence;

  /// Why Costco produced no match (debug / UI hint). Null when it matched.
  final String? costcoRejectReason;

  const AutoMatchResult({
    required this.link,
    this.brand,
    required this.asdaConfidence,
    required this.costcoConfidence,
    this.costcoRejectReason,
  });
}

// ---------------------------------------------------------------------------
// Data tables. All of these are extended over time as real shopping lists
// expose gaps; keep them small and add entries rather than special cases.
// ---------------------------------------------------------------------------

/// Phrase aliases, applied to singularised, lowercase tokens in one
/// longest-first pass (so no chaining). Keys and values are space-joined
/// singular tokens. Extended over time.
const Map<String, String> _aliases = {
  // Toilet roll (tissue ~ roll).
  'loo roll': 'toilet roll',
  'loo paper': 'toilet roll',
  'toilet tissue': 'toilet roll',
  'toilet paper': 'toilet roll',
  // Kitchen roll.
  'kitchen towel': 'kitchen roll',
  // Laundry vs washing up (kept distinct).
  'washing liquid': 'laundry liquid',
  'liquid detergent': 'laundry liquid',
  'detergent': 'laundry liquid',
  'dish soap': 'washing up liquid',
  'dishwashing liquid': 'washing up liquid',
  'dish washing liquid': 'washing up liquid',
  // Dishwasher tablets.
  'dishwasher tab': 'dishwasher tablet',
  'dishwasher pod': 'dishwasher tablet',
  'dishwasher pac': 'dishwasher tablet',
  'dishwasher capsule': 'dishwasher tablet',
  // Tea bags become one token.
  'tea bag': 'teabag',
  // Bio / non bio are one word so they never read as "bio".
  'non bio': 'nonbio',
  // Milk types.
  'semi skimmed': 'semiskimmed',
  'semi skim': 'semiskimmed',
};

/// A token that also implies another ("spaghetti" is a pasta). Applied to
/// product token sets only, never to the item's required tokens. Extended
/// over time.
const Map<String, List<String>> _implied = {
  'spaghetti': ['pasta'],
  'penne': ['pasta'],
  'fusilli': ['pasta'],
  'tagliatelle': ['pasta'],
  'linguine': ['pasta'],
  'macaroni': ['pasta'],
  'teabag': ['tea'],
};

/// Singularisation leaves brands that end in a plural-looking s alone via
/// this table (applied after singularisation).
const Map<String, String> _spellFixes = {
  'kellogg': 'kelloggs',
  'hellmann': 'hellmanns',
  'ben': 'bens',
};

const Set<String> _stopwords = {
  'a',
  'an',
  'the',
  'of',
  'and',
  'in',
  'with',
  'for',
  'some',
  'x',
  'pack',
  'pk',
};

/// Common UK brands an item name may lock to. Brand values found on the Asda
/// results (other than ASDA's own labels) are added at match time. Extended
/// over time.
const List<String> _knownBrands = [
  'Heinz',
  'Branston',
  'Persil',
  'Ariel',
  'Surf',
  'Fairy',
  'Finish',
  'Andrex',
  'Cushelle',
  'Regina',
  'Plenty',
  'Tilda',
  "Uncle Ben's",
  'Napolina',
  'Mutti',
  'Yorkshire Tea',
  'Taylors',
  'PG Tips',
  'Tetley',
  'Twinings',
  "Kellogg's",
  'Weetabix',
  'Quaker',
  'Nescafe',
  'Kenco',
  'Douwe Egberts',
  'Lavazza',
  'Filippo Berio',
  'Lurpak',
  'Anchor',
  'Cathedral City',
  'Cravendale',
  'Warburtons',
  'Hovis',
  "Hellmann's",
  'Colgate',
  'Kirkland',
];

/// Words that change what a product is. A Costco (or Asda sibling) product
/// carrying one of these is rejected unless the item name or the Asda anchor
/// also has it, so "tea bags" never picks green matcha tea, "pasta" never
/// picks the gluten-free pack, and so on. Entries are singularised on first
/// use. Extended over time as new false positives turn up.
const Set<String> _modifierWords = {
  'gluten', 'free', 'organic', 'decaf', 'vegan', 'flavoured', 'flavour',
  'chilli', 'garlic', 'mini', 'kids', 'baby', 'infant', 'cat', 'dog', 'pet',
  'puppy', 'kitten', 'whiskas', 'green', 'matcha', 'herbal', 'fruit',
  'camomile', 'peppermint', 'latte', 'cappuccino', 'pods', 'salt', 'rinse',
  'aid', 'wipes', 'nog', 'mayonnaise', 'cookies', 'nougat', 'chocolate',
  'aperitivo', 'frother',
  // Added after the milk / baked beans fixtures: milk alternatives and
  // formula, flavoured beans.
  'coconut', 'oat', 'soya', 'almond', 'powder', 'formula', 'stage', 'ready',
  'malted', 'caramel', 'spread', 'barbecue', 'bbq',
};

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

const Map<String, String> _accents = {
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ü': 'u',
  'û': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String _singular(String t) {
  if (t.length <= 3 || !t.endsWith('s')) return t;
  if (t.endsWith('ss') || t.endsWith('us') || t.endsWith('is')) return t;
  final stem = t.substring(0, t.length - 1);
  if (t.endsWith('ies') && t.length > 4) {
    return '${t.substring(0, t.length - 3)}y';
  }
  if (t.endsWith('oes') && t.length > 5) return t.substring(0, t.length - 2);
  if (RegExp(r'(sh|ch|x|z)es$').hasMatch(t)) {
    return t.substring(0, t.length - 2);
  }
  return stem;
}

/// Lowercase, accent-folded, punctuation-stripped, singularised tokens.
/// Apostrophes vanish without splitting ("kellogg's" -> "kelloggs") and such
/// tokens are not singularised; other punctuation separates tokens.
List<String> _baseTokens(String text) {
  final buf = StringBuffer();
  for (final r in text.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    buf.write(_accents[ch] ?? ch);
  }
  final s = buf.toString().replaceAll('&', ' and ');
  final out = <String>[];
  for (final raw in s.split(RegExp(r"[^a-z0-9'’]+"))) {
    if (raw.isEmpty) continue;
    final hasApostrophe = raw.contains("'") || raw.contains('’');
    final t = raw.replaceAll("'", '').replaceAll('’', '');
    if (t.isEmpty) continue;
    final base = hasApostrophe ? t : _singular(t);
    out.add(_spellFixes[base] ?? base);
  }
  return out;
}

final int _maxAliasWords = _aliases.keys
    .map((k) => k.split(' ').length)
    .reduce((a, b) => a > b ? a : b);

/// Applies [_aliases] to [tokens], longest phrase first.
List<String> _applyAliases(List<String> tokens) {
  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    var matched = false;
    for (var n = _maxAliasWords; n >= 1; n--) {
      if (i + n > tokens.length) continue;
      final to = _aliases[tokens.sublist(i, i + n).join(' ')];
      if (to != null) {
        out.addAll(to.split(' '));
        i += n;
        matched = true;
        break;
      }
    }
    if (!matched) out.add(tokens[i++]);
  }
  return out;
}

/// Aliased tokens plus implied ones: what a product name "contains".
Set<String> _tokenSet(String text) {
  final tokens = _applyAliases(_baseTokens(text)).toSet();
  for (final t in tokens.toList()) {
    final extra = _implied[t];
    if (extra != null) tokens.addAll(extra);
  }
  return tokens;
}

final Set<String> _modifiers = {
  for (final w in _modifierWords) ..._baseTokens(w),
};

final RegExp _sizeTokenRe = RegExp(r'^\d');

/// Words that split one shelf-worth of "the same thing" into different
/// products. Products on a sibling shelf (same Asda aisle or item-named dept) are
/// only accepted when their variant words equal the anchor's, so "milk" never
/// crosses from semi skimmed to whole, "olive oil" never mixes with extra
/// virgin, and sensitive non-bio never mixes with bio. "semi skimmed" counts as
/// semi + skimmed and "non bio" as nonbio. Extended over time.
const Set<String> _variantWords = {
  'whole',
  'skimmed',
  'semi',
  '1%',
  'lactose',
  'organic',
  'unsalted',
  'salted',
  'brown',
  'white',
  'wholemeal',
  'bio',
  'nonbio',
  'sensitive',
  'extra',
  'virgin',
  'light',
  'mild',
  'medium',
  'mature',
  'smoked',
  'unsmoked',
};

final RegExp _onePercentRe = RegExp(r'(?<![\d.])1\s*%');

Set<String> _variantTokens(String text) {
  final t = _tokenSet(text);
  if (t.remove('semiskimmed')) t.addAll(const ['semi', 'skimmed']);
  final v = t.where(_variantWords.contains).toSet();
  if (_onePercentRe.hasMatch(text)) v.add('1%');
  return v;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

// ---------------------------------------------------------------------------
// Brands
// ---------------------------------------------------------------------------

class _Brand {
  final String label;
  final List<String> tokens;
  const _Brand(this.label, this.tokens);
}

String _brandLabel(String raw) =>
    raw.toLowerCase().replaceAll(RegExp("['’]"), '').trim();

_Brand? _makeBrand(String raw) {
  final tokens = _baseTokens(raw);
  return tokens.isEmpty ? null : _Brand(_brandLabel(raw), tokens);
}

const _Brand _asdaBrand = _Brand('asda', ['asda']);

int _indexOfSeq(List<String> hay, List<String> needle, [int from = 0]) {
  if (needle.isEmpty) return -1;
  for (var i = from; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

List<_Brand> _brandCatalog(List<PriceProduct> asda) {
  final seen = <String>{};
  final out = <_Brand>[];
  void add(_Brand? b) {
    if (b != null && seen.add(b.tokens.join(' '))) out.add(b);
  }

  add(_asdaBrand);
  _knownBrands.map(_makeBrand).forEach(add);
  for (final p in asda) {
    final b = _makeBrand(p.brand);
    // Asda's own labels ("ASDA", "Shades by ASDA") are not brand locks.
    if (b != null && !b.tokens.contains('asda')) add(b);
  }
  return out;
}

class _BrandHit {
  final _Brand brand;
  final int start;
  const _BrandHit(this.brand, this.start);
}

// Earliest whole-token brand mention in the item, longest phrase on a tie.
_BrandHit? _detectBrand(List<String> itemTokens, List<_Brand> catalog) {
  _BrandHit? best;
  for (final b in catalog) {
    final i = _indexOfSeq(itemTokens, b.tokens);
    if (i < 0) continue;
    if (best == null ||
        i < best.start ||
        (i == best.start && b.tokens.length > best.brand.tokens.length)) {
      best = _BrandHit(b, i);
    }
  }
  return best;
}

bool _productHasBrand(PriceProduct p, _Brand brand) {
  final tokens = _baseTokens('${p.brand} ${p.name}');
  return _indexOfSeq(tokens, brand.tokens) >= 0;
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

bool _hasUnrequestedModifier(Set<String> product, Set<String> allowed) =>
    product.any((t) => _modifiers.contains(t) && !allowed.contains(t));

({List<PriceProduct> picks, PriceProduct? anchor, MatchConfidence conf})
_matchAsda({
  required List<PriceProduct> asda,
  required List<String> core,
  required Set<String> itemTokens,
  required _Brand? lock,
}) {
  const none = (
    picks: <PriceProduct>[],
    anchor: null,
    conf: MatchConfidence.none,
  );
  final pool = lock == null
      ? asda
      : asda.where((p) => _productHasBrand(p, lock)).toList();
  if (pool.isEmpty) return none;

  bool hasCore(PriceProduct p) {
    final t = _tokenSet(p.name);
    return core.every(t.contains);
  }

  PriceProduct anchor;
  MatchConfidence conf;
  final full = core.isEmpty ? <PriceProduct>[] : pool.where(hasCore).toList();
  if (full.isNotEmpty) {
    // First relevant result; skip ones with unrequested modifiers
    // ("Barbecue" beans) and out-of-stock ones when something cleaner exists.
    bool clean(PriceProduct p) =>
        !_hasUnrequestedModifier(_tokenSet(p.name), itemTokens);
    anchor = full.firstWhere(
      (p) => clean(p) && p.inStock,
      orElse: () => full.firstWhere(
        clean,
        orElse: () =>
            full.firstWhere((p) => p.inStock, orElse: () => full.first),
      ),
    );
    conf = MatchConfidence.high;
  } else {
    anchor = pool.firstWhere((p) => p.inStock, orElse: () => pool.first);
    conf = MatchConfidence.low;
  }

  final allowed = {...itemTokens, ..._tokenSet(anchor.name)};
  final aq = anchor.quantity;
  final shelf = anchor.shelf;
  final aisle = anchor.aisle;
  final dept = anchor.dept;
  // The whole department counts as one group when its name is nothing but the
  // item ("Toilet Roll" for "toilet roll"); "Milk, Butter, Cream & Eggs" is
  // wider than "milk", so milk stays scoped to its aisle.
  final deptTokens = dept == null
      ? const <String>[]
      : _applyAliases(
          _baseTokens(dept),
        ).where((t) => !_stopwords.contains(t)).toList();
  final deptIsItem = deptTokens.isNotEmpty && deptTokens.every(core.contains);
  final anchorVariants = _variantTokens(anchor.name);

  // Pack amount within 0.5x-2x of the anchor's on their shared basis.
  bool sizeOk(PriceProduct p) {
    if (aq == null) return true;
    final basis = chooseBasis(aq, p.quantity);
    if (basis == null) return false;
    final a = amountIn(aq, basis);
    final b = amountIn(p.quantity!, basis);
    if (a == null || b == null) return false;
    final ratio = b / a;
    return ratio >= 0.5 - 1e-9 && ratio <= 2 + 1e-9;
  }

  final cands = <PriceProduct>[];
  for (final p in asda) {
    if (identical(p, anchor)) {
      cands.add(p);
      continue;
    }
    if (lock != null && !_productHasBrand(p, lock)) continue;
    final tokens = _tokenSet(p.name);
    if (_hasUnrequestedModifier(tokens, allowed)) continue;
    if (shelf != null && p.shelf == shelf) {
      if (sizeOk(p)) cands.add(p);
    } else if (aq != null &&
        core.isNotEmpty &&
        ((aisle != null && p.aisle == aisle) ||
            (deptIsItem && p.dept == dept)) &&
        core.every({...tokens, ..._tokenSet(p.shelf ?? '')}.contains) &&
        _sameSet(_variantTokens(p.name), anchorVariants) &&
        sizeOk(p)) {
      // Own-brand names often leave out the product word ("So Soft 12
      // Long-Lasting Rolls"), so the shelf name counts toward the core words.
      // Sibling shelf in the same aisle (or department, see above): accepted
      // only when it is the same variant.
      cands.add(p);
    }
  }
  final inStock = cands.where((p) => p.inStock).toList();
  return (
    picks: inStock.isNotEmpty ? inStock : cands,
    anchor: anchor,
    conf: conf,
  );
}

({List<PriceProduct> picks, String? reason}) _matchCostco({
  required List<PriceProduct> costco,
  required List<String> core,
  required Set<String> itemTokens,
  required _Brand? lock,
  required PriceProduct? anchor,
}) {
  if (costco.isEmpty) return (picks: const [], reason: 'no Costco results');
  if (core.isEmpty) {
    return (picks: const [], reason: 'item has no product words to match');
  }
  // Own-brand ("asda ...") locks Asda only; Costco stays open.
  final brand = (lock == null || lock.label == 'asda') ? null : lock;
  final allowed = {
    ...itemTokens,
    if (anchor != null) ..._tokenSet(anchor.name),
  };

  var nameMiss = 0;
  var basisMiss = 0;
  var brandMiss = 0;
  final modifierHits = <String>{};
  var modifierMiss = 0;
  final picks = <PriceProduct>[];
  for (final p in costco) {
    final tokens = _tokenSet(p.name);
    if (!core.every(tokens.contains)) {
      nameMiss++;
      continue;
    }
    final q = p.quantity;
    final sharesBasis = anchor?.quantity != null
        ? chooseBasis(anchor!.quantity, q) != null
        : (anchor == null &&
              q != null &&
              (q.grams != null || q.millilitres != null || q.count != null));
    if (!sharesBasis) {
      basisMiss++;
      continue;
    }
    if (brand != null && !_productHasBrand(p, brand)) {
      brandMiss++;
      continue;
    }
    final bad = tokens
        .where((t) => _modifiers.contains(t) && !allowed.contains(t))
        .toList();
    if (bad.isNotEmpty) {
      modifierMiss++;
      modifierHits.addAll(bad);
      continue;
    }
    picks.add(p);
  }
  if (picks.isNotEmpty) return (picks: picks, reason: null);
  if (nameMiss == costco.length) {
    return (
      picks: const [],
      reason: 'no Costco product matched all of: ${core.join(', ')}',
    );
  }
  final parts = <String>[
    if (basisMiss > 0) 'no shared pack basis ($basisMiss)',
    if (brandMiss > 0) 'wrong brand ($brandMiss)',
    if (modifierMiss > 0)
      'modifier guard ($modifierMiss: ${(modifierHits.toList()..sort()).join(', ')})',
  ];
  return (
    picks: const [],
    reason:
        '${costco.length - nameMiss} Costco product(s) matched the name but '
        'were rejected: ${parts.join('; ')}',
  );
}

/// Picks store products for a list item with no user input.
///
/// [asda] and [costco] are the parsed search results for the item name, in
/// the store's relevance order. Asda (good relevance) anchors on its first
/// result that has every item word, then takes that shelf's products of a
/// similar size. Costco (poor relevance) must match every item word, share a
/// comparison basis with the Asda anchor and pass the modifier guard, else no
/// Costco match is returned. A brand named in the item locks both stores to
/// it; "asda" locks Asda to own-brand only.
AutoMatchResult autoMatch(
  String itemName, {
  required List<PriceProduct> asda,
  required List<PriceProduct> costco,
  DateTime? now,
}) {
  final base = _baseTokens(itemName);
  final hit = _detectBrand(base, _brandCatalog(asda));
  final lock = hit?.brand;

  var rest = base;
  if (hit != null) {
    var end = hit.start + hit.brand.tokens.length;
    // "Yorkshire Tea bags": the brand's trailing "tea" is also the product.
    if (hit.brand.tokens.length > 1 && hit.brand.tokens.last == 'tea') end--;
    rest = [...base.sublist(0, hit.start), ...base.sublist(end)];
  }
  final core = <String>[];
  for (final t in _applyAliases(rest)) {
    if (_stopwords.contains(t) || _sizeTokenRe.hasMatch(t)) continue;
    if (!core.contains(t)) core.add(t);
  }
  final itemTokens = _tokenSet(itemName);

  final a = _matchAsda(
    asda: asda,
    core: core,
    itemTokens: itemTokens,
    lock: lock,
  );
  final c = _matchCostco(
    costco: costco,
    core: core,
    itemTokens: itemTokens,
    lock: lock,
    anchor: a.anchor,
  );

  final link = PriceLink(
    itemKey: PriceLink.keyFor(itemName),
    mode: (a.picks.length > 1 || c.picks.length > 1)
        ? LinkMode.anyOf
        : LinkMode.exact,
    asda: a.picks,
    costco: c.picks,
    updatedAt: now ?? DateTime.now(),
  );
  return AutoMatchResult(
    link: link,
    brand: lock?.label,
    asdaConfidence: a.conf,
    costcoConfidence: c.picks.isEmpty
        ? MatchConfidence.none
        : MatchConfidence.high,
    costcoRejectReason: c.reason,
  );
}
