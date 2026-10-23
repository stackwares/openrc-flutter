import 'package:flutter/material.dart';

/// Stadium search field used by filter and picker sheets.
InputDecoration searchFieldDecoration(ColorScheme scheme, String hint) {
  const radius = BorderRadius.all(Radius.circular(40));
  const idle = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide.none,
  );
  final focused = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: scheme.primary, width: 1.5),
  );
  return InputDecoration(
    hintText: hint,
    prefixIcon: const Icon(Icons.search_rounded, size: 22),
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
    isDense: true,
    border: idle,
    enabledBorder: idle,
    focusedBorder: focused,
    disabledBorder: idle,
    errorBorder: idle,
    focusedErrorBorder: focused,
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
  );
}
