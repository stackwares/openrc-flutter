import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
// The public API offers no way to load translations without a widget tree.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';

/// Every test sees the English strings, as the app does on an English device.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final en = json.decode(File('assets/translations/en.json').readAsStringSync())
      as Map<String, dynamic>;
  Localization.load(const Locale('en'), translations: Translations(en));
  await testMain();
}
