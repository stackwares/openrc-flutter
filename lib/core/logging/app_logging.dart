import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Call once at app startup before any [Logger] records are emitted.
void configureAppLogging() {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  // Per-logger caps (child level still respects record level for that logger).
  Logger('RcApiService').level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    developer.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}
