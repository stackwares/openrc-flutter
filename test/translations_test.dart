import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/l10n/app_locales.dart';

Map<String, String> _flatten(Map<String, dynamic> map, [String prefix = '']) {
  final out = <String, String>{};
  map.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = value.toString();
    }
  });
  return out;
}

Map<String, String> _load(String stem) => _flatten(
  json.decode(File('assets/translations/$stem.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// `{name}` arguments and `{}` plural slots, in order of first use.
Set<String> _placeholders(String text) =>
    RegExp(r'\{[A-Za-z_]*\}').allMatches(text).map((m) => m[0]!).toSet();

const _pluralForms = {'zero', 'one', 'two', 'few', 'many', 'other'};

/// Keys with plural forms folded into their parent: languages use different
/// forms (Russian adds few/many, Japanese only needs other).
Set<String> _messageKeys(Map<String, String> flat) => {
  for (final key in flat.keys)
    _pluralForms.contains(key.split('.').last)
        ? key.substring(0, key.lastIndexOf('.'))
        : key,
};

void main() {
  final english = _load('en');

  test('English has strings', () {
    expect(english, isNotEmpty);
  });

  for (final locale in AppLocales.supported) {
    final stem = AppLocales.fileStem(locale);
    if (stem == 'en') continue;

    group(stem, () {
      final file = File('assets/translations/$stem.json');

      test('file exists', () => expect(file.existsSync(), isTrue));

      test('has exactly the English keys', () {
        final translated = _load(stem);
        final keys = _messageKeys(translated);
        final source = _messageKeys(english);
        expect(keys.difference(source), isEmpty, reason: 'extra keys');
        expect(source.difference(keys), isEmpty, reason: 'missing keys');
        // Every plural message keeps its catch-all form.
        final plurals = english.keys
            .where((k) => k.endsWith('.other'))
            .where((k) => !translated.containsKey(k));
        expect(plurals, isEmpty, reason: 'plural without "other"');
      });

      test('has no empty strings', () {
        final empty = _load(stem).entries
            .where((e) => e.value.trim().isEmpty)
            .map((e) => e.key);
        expect(empty, isEmpty);
      });

      test('keeps every placeholder', () {
        final translated = _load(stem);
        // Named arguments must survive; `{}` count slots may be dropped
        // where a language spells the number out (e.g. a "one" form).
        Set<String> named(String text) =>
            _placeholders(text).where((p) => p != '{}').toSet();
        final broken = [
          for (final entry in english.entries)
            if (translated.containsKey(entry.key) &&
                !named(translated[entry.key]!).containsAll(named(entry.value)))
              entry.key,
        ];
        expect(broken, isEmpty);
      });
    });
  }
}
