/// Display titles derived from product ids shaped like:
/// `{name...}.{entitlement}.{sub|iap}.{period}.{offer_flag}`
/// where [name] may contain additional `.` segments.
///
/// Titles are only ever **Monthly**, **Weekly**, or **Annual**, optionally
/// suffixed with ** Offer**. Segment suffixes like `:base` / `_base` / `-base`
/// are stripped before interpreting the period.
String productIdentifierDisplayTitle(
  String? identifier, {
  String ifEmpty = 'Unknown',
}) {
  if (identifier == null || identifier.isEmpty) return ifEmpty;

  final parts = identifier.split('.').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 5) {
    final typeRaw = parts[parts.length - 3].toLowerCase();
    if (typeRaw == 'sub' || typeRaw == 'iap') {
      final periodRaw = parts[parts.length - 2];
      final offerRaw = parts.last;
      final periodLabel = _periodToStrictLabel(periodRaw);
      final isOffer = _isOfferSegment(_stripBaseArtifacts(offerRaw));
      return isOffer ? '$periodLabel Offer' : periodLabel;
    }
  }

  return _fallbackTitle(identifier);
}

String _stripBaseArtifacts(String s) {
  var t = s.trim();
  for (;;) {
    final lower = t.toLowerCase();
    if (lower.endsWith(':base')) {
      t = t.substring(0, t.length - ':base'.length);
      continue;
    }
    if (lower.endsWith('_base')) {
      t = t.substring(0, t.length - '_base'.length);
      continue;
    }
    if (lower.endsWith('-base')) {
      t = t.substring(0, t.length - '-base'.length);
      continue;
    }
    break;
  }
  return t.trim();
}

bool _isOfferSegment(String raw) {
  final s = _stripBaseArtifacts(raw).toLowerCase();
  if (s.isEmpty) return false;
  const nonOffer = {
    'false',
    '0',
    'no',
    'n',
    'none',
    'standard',
    'regular',
    'base',
    'default',
  };
  if (nonOffer.contains(s)) return false;
  const offer = {
    'true',
    '1',
    'yes',
    'y',
    'offer',
    'intro',
    'introductory',
    'promo',
    'promotional',
    'sale',
    'discount',
  };
  return offer.contains(s);
}

/// Only [Monthly], [Weekly], or [Annual].
String _periodToStrictLabel(String raw) {
  var key = _stripBaseArtifacts(raw).toLowerCase().replaceAll('_', '');
  if (key.isEmpty) return 'Monthly';

  const weeklyExact = {'weekly', 'week', 'w1'};
  const monthlyExact = {'monthly', 'month', 'm1', 'p1m', 'everymonth'};
  const annualExact = {
    'annual',
    'yearly',
    'year',
    'y1',
    'p1y',
    'quarterly',
    'semiannual',
    'biannual',
    'lifetime',
    'life',
    'once',
    'onetime',
  };

  if (weeklyExact.contains(key)) return 'Weekly';
  if (monthlyExact.contains(key)) return 'Monthly';
  if (annualExact.contains(key)) return 'Annual';

  if (key.contains('week')) return 'Weekly';
  if (key.contains('month') || key.contains('mth')) return 'Monthly';
  if (key.contains('year') ||
      key.contains('annual') ||
      key.contains('life') ||
      key.contains('quarter') ||
      key.contains('biannual') ||
      key.contains('semiannual') ||
      key.contains('semester')) {
    return 'Annual';
  }

  if (RegExp(r'^p\d+m').hasMatch(key)) return 'Monthly';
  if (RegExp(r'^p\d+y').hasMatch(key)) return 'Annual';

  return 'Monthly';
}

String _fallbackTitle(String identifier) {
  final parts = identifier.split('.').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'Unknown';

  var idx = parts.length - 1;
  var seg = _stripBaseArtifacts(parts[idx]);
  while (idx >= 0 && _isOfferSegment(seg)) {
    idx--;
    if (idx < 0) break;
    seg = _stripBaseArtifacts(parts[idx]);
  }
  if (idx < 0) return 'Monthly';

  return _periodToStrictLabel(parts[idx]);
}
