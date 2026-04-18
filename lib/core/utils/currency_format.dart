import 'package:intl/intl.dart';

String currencySymbolFor(String isoCode) {
  try {
    return NumberFormat.simpleCurrency(name: isoCode).currencySymbol;
  } catch (_) {
    return '$isoCode ';
  }
}

String formatCompactUsd(double v) {
  if (v >= 1000000) {
    return '\$${(v / 1000000).toStringAsFixed(2)}M';
  }
  if (v >= 1000) {
    return '\$${(v / 1000).toStringAsFixed(1)}K';
  }
  return '\$${v.toStringAsFixed(2)}';
}

String formatCompactForeign(double v, String isoCode) {
  final sym = currencySymbolFor(isoCode);
  if (v >= 1000000) {
    return '$sym${(v / 1000000).toStringAsFixed(2)}M';
  }
  if (v >= 1000) {
    return '$sym${(v / 1000).toStringAsFixed(1)}K';
  }
  final digits = isoCode == 'JPY' || isoCode == 'KRW' ? 0 : 2;
  return NumberFormat.currency(symbol: sym, decimalDigits: digits).format(v);
}

String formatExactUsd(double v) {
  return NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v);
}

String formatExactForeign(double v, String isoCode) {
  final sym = currencySymbolFor(isoCode);
  final digits = isoCode == 'JPY' || isoCode == 'KRW' ? 0 : 2;
  return NumberFormat.currency(symbol: sym, decimalDigits: digits).format(v);
}
