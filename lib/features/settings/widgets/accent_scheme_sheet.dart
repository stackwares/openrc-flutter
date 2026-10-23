import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/search_field_decoration.dart';

/// Saves and applies an accent palette.
Future<void> setAccentScheme(WidgetRef ref, FlexScheme scheme) async {
  ref.read(colorSchemeProvider.notifier).state = scheme;
  await ref.read(utilitiesServiceProvider).saveColorScheme(scheme);
}

/// Every built-in palette, searchable. The app recolors as you pick.
Future<void> showAccentSchemeSheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.8,
    builder: (_) => const _AccentSchemeSheet(),
  );
}

class _AccentSchemeSheet extends ConsumerStatefulWidget {
  const _AccentSchemeSheet();

  @override
  ConsumerState<_AccentSchemeSheet> createState() => _AccentSchemeSheetState();
}

class _AccentSchemeSheetState extends ConsumerState<_AccentSchemeSheet> {
  String _query = '';

  static final List<FlexScheme> _schemes = [
    for (final scheme in FlexScheme.values)
      if (scheme != FlexScheme.custom) scheme,
  ];

  bool _matches(FlexScheme scheme) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final data = scheme.data;
    return data.name.toLowerCase().contains(query) ||
        data.description.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(colorSchemeProvider);
    final brightness = Theme.of(context).brightness;
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final options = [
      for (final item in _schemes)
        if (_matches(item)) item,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.accentColor'.tr(),
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'settings.accentSheetBody'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: searchFieldDecoration(
                  scheme,
                  'settings.searchPalettes'.tr(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: options.isEmpty
              ? Center(
                  child: Text(
                    'settings.noPalettes'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottom),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final item = options[index];
                    final colors = item.colors(brightness);
                    final isSelected = item == selected;
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: Material(
                        color: isSelected
                            ? scheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setAccentScheme(ref, item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                SchemeSwatch(
                                  primary: colors.primary,
                                  secondary: colors.secondary,
                                  tertiary: colors.tertiary,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.data.name,
                                        style: tt.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        item.data.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tt.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: isSelected
                                      ? Icon(
                                          Icons.check_rounded,
                                          color: scheme.primary,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Three overlapping dots: primary, secondary, tertiary.
class SchemeSwatch extends StatelessWidget {
  const SchemeSwatch({
    super.key,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          width: 1.5,
        ),
      ),
    );
    return SizedBox(
      width: 44,
      height: 28,
      child: Stack(
        children: [
          Positioned(left: 0, child: dot(primary, 28)),
          Positioned(left: 16, top: 2, child: dot(secondary, 22)),
          Positioned(left: 28, top: 6, child: dot(tertiary, 16)),
        ],
      ),
    );
  }
}
