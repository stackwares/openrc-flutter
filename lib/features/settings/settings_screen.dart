import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/widgets/grouped_list.dart';
import 'package:revenuecat/widgets/search_field_decoration.dart';
import 'package:revenuecat/widgets/section_header.dart';
import 'package:revenuecat/widgets/shell_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  static void open(BuildContext context) {
    Navigator.of(context).pushNamed(routeName);
  }

  static void _showCurrencyBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final view = MediaQuery.of(sheetContext);
        final height = (view.size.height - view.viewInsets.bottom) * 0.72;
        return Padding(
          padding: EdgeInsets.only(bottom: view.viewInsets.bottom),
          child: SizedBox(height: height, child: const _DisplayCurrencySheet()),
        );
      },
    );
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You will need to sign in again to use the app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      await ref.read(rcAuthServiceProvider).signOut();
    }
  }

  static Future<void> _setThemeMode(WidgetRef ref, ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).state = mode;
    await ref.read(utilitiesServiceProvider).saveThemeMode(mode);
  }

  static void _showColorSchemeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final view = MediaQuery.of(sheetContext);
        final height = (view.size.height - view.viewInsets.bottom) * 0.78;
        return Padding(
          padding: EdgeInsets.only(bottom: view.viewInsets.bottom),
          child: SizedBox(height: height, child: const _ColorSchemeSheet()),
        );
      },
    );
  }

  static Future<void> _setColorScheme(WidgetRef ref, FlexScheme scheme) async {
    ref.read(colorSchemeProvider.notifier).state = scheme;
    await ref.read(utilitiesServiceProvider).saveColorScheme(scheme);
  }

  static Future<void> _editCommissionPercent(
    BuildContext context,
    WidgetRef ref, {
    required bool isApple,
  }) async {
    final notifier = ref.read(commissionSettingsProvider.notifier);
    final current = ref.read(commissionSettingsProvider);
    final initial = isApple
        ? current.appleCommissionPercent
        : current.googleCommissionPercent;
    final controller = TextEditingController(
      text: initial == initial.roundToDouble()
          ? initial.toStringAsFixed(0)
          : initial.toStringAsFixed(1),
    );
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isApple ? 'App Store commission' : 'Google Play commission',
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fee',
              suffixText: '%',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (saved == true && context.mounted) {
        final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
        if (v == null) return;
        if (isApple) {
          await notifier.setAppleCommissionPercent(v);
        } else {
          await notifier.setGoogleCommissionPercent(v);
        }
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(displayCurrencyProvider);
    final sym = currencySymbolFor(selected);
    final selectedOption = lookupDisplayCurrencyOption(selected);
    final commission = ref.watch(commissionSettingsProvider);
    final me = ref.watch(rcMeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);
    final schemeColors = colorScheme.colors(Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final valueStyle = tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    String pct(double v) => '${v.toStringAsFixed(1)}%';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          4,
          0,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const _GroupLabel('Preferences'),
          GroupedCard(
            dividerIndent: 56,
            children: [
              _SettingsRow(
                icon: Icons.currency_exchange_rounded,
                title: 'Display currency',
                value: Text(
                  '${selectedOption?.flagEmoji ?? ''} $sym $selected'.trim(),
                  style: valueStyle,
                ),
                onTap: () => _showCurrencyBottomSheet(context),
              ),
              _SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Color scheme',
                value: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SchemeSwatch(
                      primary: schemeColors.primary,
                      secondary: schemeColors.secondary,
                      tertiary: schemeColors.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        colorScheme.data.name,
                        style: valueStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onTap: () => _showColorSchemeSheet(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.contrast_rounded,
                          size: 22,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 18),
                        Text('Appearance', style: tt.bodyLarge),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      style: SegmentedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (next) {
                        if (next.isEmpty) return;
                        _setThemeMode(ref, next.single);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ).appCardEntrance(),
          const _GroupLabel('Store fees'),
          GroupedCard(
            dividerIndent: 56,
            children: [
              _SettingsRow(
                icon: Icons.percent_rounded,
                title: 'Subtract store fees',
                subtitle: 'Show revenue after App Store and Google Play fees',
                value: Switch(
                  value: commission.adjustmentEnabled,
                  onChanged: (v) => ref
                      .read(commissionSettingsProvider.notifier)
                      .setAdjustmentEnabled(v),
                ),
                onTap: () => ref
                    .read(commissionSettingsProvider.notifier)
                    .setAdjustmentEnabled(!commission.adjustmentEnabled),
                showChevron: false,
              ),
              if (commission.adjustmentEnabled) ...[
                _SettingsRow(
                  icon: Icons.apple,
                  title: 'App Store fee',
                  value: Text(
                    pct(commission.appleCommissionPercent),
                    style: valueStyle,
                  ),
                  onTap: () =>
                      _editCommissionPercent(context, ref, isApple: true),
                ),
                _SettingsRow(
                  icon: Icons.android,
                  title: 'Google Play fee',
                  value: Text(
                    pct(commission.googleCommissionPercent),
                    style: valueStyle,
                  ),
                  onTap: () =>
                      _editCommissionPercent(context, ref, isApple: false),
                ),
              ],
            ],
          ).appCardEntrance(delay: const Duration(milliseconds: 60)),
          const _GroupLabel('Account'),
          GroupedCard(
            dividerIndent: 56,
            children: [
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                title: 'Email',
                subtitle: me?.email ?? '\u2014',
                showChevron: false,
              ),
              _SettingsRow(
                icon: Icons.fingerprint_rounded,
                title: 'Distinct ID',
                subtitleWidget: SelectableText(
                  me?.distinctId ?? '\u2014',
                  style: tt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                showChevron: false,
              ),
              _SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Log out',
                destructive: true,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ).appCardEntrance(delay: const Duration(milliseconds: 120)),
          const SizedBox(height: 20),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

/// Small muted heading above a settings group.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: text,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    );
  }
}

/// One row in a settings group: icon, title (+ subtitle), trailing value.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.value,
    this.onTap,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? value;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = destructive ? context.appColors.negative : null;
    final sub =
        subtitleWidget ??
        (subtitle == null
            ? null
            : Text(
                subtitle!,
                style: tt.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color ?? scheme.onSurfaceVariant),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: tt.bodyLarge?.copyWith(
                        color: color,
                        fontWeight: destructive ? FontWeight.w600 : null,
                      ),
                    ),
                    if (sub != null) ...[const SizedBox(height: 2), sub],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: value!,
                ),
              ],
              if (showChevron && onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox(height: 20);
        return Text(
          'Version ${info.version} (${info.buildNumber})',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

class _ColorSchemeSheet extends ConsumerStatefulWidget {
  const _ColorSchemeSheet();

  @override
  ConsumerState<_ColorSchemeSheet> createState() => _ColorSchemeSheetState();
}

class _ColorSchemeSheetState extends ConsumerState<_ColorSchemeSheet> {
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final options = [
      for (final item in _schemes)
        if (_matches(item)) item,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Color scheme',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Built-in FlexColorScheme palettes. The app updates as you pick one.',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: searchFieldDecoration(
                  scheme,
                  'Search color schemes',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: options.isEmpty
              ? Center(
                  child: Text(
                    'No color schemes match that search.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottom),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final item = options[index];
                    final colors = item.colors(brightness);
                    final isSelected = item == selected;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      selected: isSelected,
                      leading: _SchemeSwatch(
                        primary: colors.primary,
                        secondary: colors.secondary,
                        tertiary: colors.tertiary,
                      ),
                      title: Text(
                        item.data.name,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        item.data.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_rounded, color: scheme.primary)
                          : null,
                      onTap: () => SettingsScreen._setColorScheme(ref, item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SchemeSwatch extends StatelessWidget {
  const _SchemeSwatch({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 28,
      child: Stack(
        children: [
          Positioned(left: 0, child: _SwatchDot(color: primary, size: 28)),
          Positioned(
            left: 16,
            top: 2,
            child: _SwatchDot(color: secondary, size: 22),
          ),
          Positioned(
            left: 28,
            top: 6,
            child: _SwatchDot(color: tertiary, size: 16),
          ),
        ],
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}

class _DisplayCurrencySheet extends ConsumerStatefulWidget {
  const _DisplayCurrencySheet();

  @override
  ConsumerState<_DisplayCurrencySheet> createState() =>
      _DisplayCurrencySheetState();
}

class _DisplayCurrencySheetState extends ConsumerState<_DisplayCurrencySheet> {
  String _query = '';

  bool _matches(DisplayCurrencyOption option) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return option.code.toLowerCase().contains(query) ||
        option.label.toLowerCase().contains(query) ||
        currencySymbolFor(option.code).toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(displayCurrencyProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final options = [
      for (final option in kDisplayCurrencyOptions)
        if (_matches(option)) option,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Display currency',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Used for transaction amounts and summaries.',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: searchFieldDecoration(scheme, 'Search currencies'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: options.isEmpty
              ? Center(
                  child: Text(
                    'No currencies match that search.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in options)
                        FilterChip(
                          showCheckmark: false,
                          selected: option.code == selected,
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  option.flagEmoji,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${currencySymbolFor(option.code)} ${option.code}',
                                  style: TextStyle(
                                    fontWeight: option.code == selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onSelected: (_) async {
                            await ref
                                .read(displayCurrencyProvider.notifier)
                                .setCurrency(option.code);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// App bar button that opens [SettingsScreen] on its own route.
class SettingsAppBarAction extends StatelessWidget {
  const SettingsAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    return HeaderIconButton(
      tooltip: 'Settings',
      icon: Icons.settings_outlined,
      onPressed: () => SettingsScreen.open(context),
    );
  }
}
