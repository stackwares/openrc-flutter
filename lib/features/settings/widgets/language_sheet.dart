import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/l10n/app_locales.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/services/telemetry.dart';

/// The Language row's value: the chosen language's own name, or "System".
String languageLabel(String? stem) => stem == null
    ? 'settings.languageSystem'.tr()
    : AppLocales.nativeNames[stem] ?? stem;

/// Lets people pick the app's language, or follow the device.
Future<void> showLanguageSheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.8,
    builder: (_) => const _LanguageSheet(),
  );
}

Future<void> _apply(BuildContext context, WidgetRef ref, String? stem) async {
  UtilitiesService.hapticSelection();
  final l10n = EasyLocalization.of(context);
  final navigator = Navigator.of(context);
  ref.read(appLanguageProvider.notifier).state = stem;
  await ref.read(utilitiesServiceProvider).saveLanguage(stem);
  if (l10n != null) {
    final locale = stem == null ? null : AppLocales.fromStem(stem);
    if (locale == null) {
      await l10n.resetLocale();
      await l10n.deleteSaveLocale();
    } else {
      await l10n.setLocale(locale);
      Telemetry.preferenceChanged(setting: 'language');
    }
  }
  navigator.pop();
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appLanguageProvider);
    final tt = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'settings.language'.tr(),
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              _LanguageOption(
                title: 'settings.languageSystem'.tr(),
                subtitle: 'settings.languageSystemHint'.tr(),
                selected: selected == null,
                onTap: () => _apply(context, ref, null),
              ),
              const Divider(indent: 16, endIndent: 16),
              for (final locale in AppLocales.supported)
                () {
                  final stem = AppLocales.fileStem(locale);
                  return _LanguageOption(
                    title: AppLocales.nativeNames[stem] ?? stem,
                    selected: selected == stem,
                    onTap: () => _apply(context, ref, stem),
                  );
                }(),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: selected,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected
          ? Icon(Icons.check_rounded, color: scheme.primary)
          : null,
      onTap: selected ? () => Navigator.of(context).pop() : onTap,
    );
  }
}
