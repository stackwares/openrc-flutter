import 'package:flutter/material.dart';

/// Accent colors for store row icons (Play / App Store).
abstract final class StoreBrandIconColors {
  /// Android brand green.
  static const Color androidGreen = Color(0xFF3DDC84);

  /// iOS-style blue for the Apple icon.
  static const Color appleBlue = Color(0xFF007AFF);
}

Color? storeBrandIconTint(String? store) {
  switch (store) {
    case 'App Store':
      return StoreBrandIconColors.appleBlue;
    case 'Play Store':
      return StoreBrandIconColors.androidGreen;
    default:
      return null;
  }
}
