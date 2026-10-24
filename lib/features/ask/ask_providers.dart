import 'package:flutter_riverpod/legacy.dart';

/// Prefilled prompt when jumping to Ask from another tab (⌘K or header action).
final askPrefillProvider = StateProvider<String?>((ref) => null);

/// Increment to focus the Ask composer.
final askFocusTickProvider = StateProvider<int>((ref) => 0);

/// Show the in-tab key editor even when a key is already saved.
final askEditingKeyProvider = StateProvider<bool>((ref) => false);
