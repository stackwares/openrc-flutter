import 'package:easy_localization/easy_localization.dart';

/// ISO 4217 currencies that are typically shown without fractional units.
bool _usesZeroDecimalMinorUnits(String isoCode) {
  switch (isoCode) {
    case 'BIF':
    case 'CLP':
    case 'DJF':
    case 'GNF':
    case 'IDR':
    case 'ISK':
    case 'JPY':
    case 'KMF':
    case 'KRW':
    case 'PYG':
    case 'RWF':
    case 'UGX':
    case 'UYI':
    case 'VND':
    case 'VUV':
    case 'XAF':
    case 'XOF':
    case 'XPF':
      return true;
    default:
      return false;
  }
}

String currencySymbolFor(String isoCode) {
  try {
    return NumberFormat.simpleCurrency(name: isoCode).currencySymbol;
  } catch (_) {
    return '$isoCode ';
  }
}

/// Compact unit after an amount: single letters attach ($1.2K), words get a
/// space ($1.2 Tsd.).
String _suffix(String key) {
  final suffix = key.tr();
  return suffix.length > 1 ? ' $suffix' : suffix;
}

String formatCompactUsd(double v) {
  if (v >= 1000000) {
    return '\$${(v / 1000000).toStringAsFixed(2)}${_suffix('common.suffixMillion')}';
  }
  if (v >= 1000) {
    return '\$${(v / 1000).toStringAsFixed(1)}${_suffix('common.suffixThousand')}';
  }
  return '\$${v.toStringAsFixed(2)}';
}

String formatCompactForeign(double v, String isoCode) {
  final sym = currencySymbolFor(isoCode);
  if (v >= 1000000) {
    return '$sym${(v / 1000000).toStringAsFixed(2)}${_suffix('common.suffixMillion')}';
  }
  if (v >= 1000) {
    return '$sym${(v / 1000).toStringAsFixed(1)}${_suffix('common.suffixThousand')}';
  }
  final digits = _usesZeroDecimalMinorUnits(isoCode) ? 0 : 2;
  return NumberFormat.currency(symbol: sym, decimalDigits: digits).format(v);
}

String formatExactUsd(double v) {
  return NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v);
}

String formatExactForeign(double v, String isoCode) {
  final sym = currencySymbolFor(isoCode);
  final digits = _usesZeroDecimalMinorUnits(isoCode) ? 0 : 2;
  return NumberFormat.currency(symbol: sym, decimalDigits: digits).format(v);
}
