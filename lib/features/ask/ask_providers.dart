import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/features/ask/ask_context.dart';

/// Prefilled prompt when jumping to Ask from another tab (⌘K or a context chip).
final askPrefillProvider = StateProvider<String?>((ref) => null);

/// What the next question is about, shown above the composer.
final askContextProvider = StateProvider<AskContext?>((ref) => null);

/// Store transaction the next question is about, if any. Masked in tools.
final askFocusTransactionIdProvider = StateProvider<String?>((ref) => null);

/// Increment to focus the Ask composer.
final askFocusTickProvider = StateProvider<int>((ref) => 0);
