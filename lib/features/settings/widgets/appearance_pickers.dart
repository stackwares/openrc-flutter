import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:revenuecat/widgets/pressable_scale.dart';

/// System / Light / Dark as three miniature previews of the app.
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({
    super.key,
    required this.mode,
    required this.scheme,
    required this.onChanged,
  });

  final ThemeMode mode;
  final FlexScheme scheme;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final light = AppTheme.light(scheme).colorScheme;
    final dark = AppTheme.dark(scheme).colorScheme;
    Widget tile(ThemeMode m, String label, Widget preview) => Expanded(
      child: _ThemeModeTile(
        label: label,
        selected: mode == m,
        onTap: () => onChanged(m),
        preview: preview,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile(
          ThemeMode.system,
          'System',
          Stack(
            fit: StackFit.expand,
            children: [
              _MiniApp(colors: light),
              ClipPath(
                clipper: const _DiagonalHalfClipper(),
                child: _MiniApp(colors: dark),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        tile(ThemeMode.light, 'Light', _MiniApp(colors: light)),
        const SizedBox(width: 10),
        tile(ThemeMode.dark, 'Dark', _MiniApp(colors: dark)),
      ],
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final duration = AppMotion.of(context, AppMotion.fast);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label appearance',
      excludeSemantics: true,
      child: PressableScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selected ? null : onTap,
          child: Column(
            children: [
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? scheme.primary
                        : context.appColors.hairline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(aspectRatio: 0.8, child: preview),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(selected),
                      size: 16,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: context.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny sketch of the app (header, hero card with bars, tiles, tab bar)
/// in the given colors.
class _MiniApp extends StatelessWidget {
  const _MiniApp({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final card = colors.surfaceContainerLow;
    final ink = colors.onSurface.withValues(alpha: 0.22);
    final muted = colors.onSurface.withValues(alpha: 0.10);
    Widget line(double w, Color c, {double h = 4}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(h),
      ),
    );
    BoxDecoration cardBox() => BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: colors.outlineVariant, width: 0.6),
    );
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 8, 7, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(22, ink, h: 5),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(5),
              decoration: cardBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(26, ink, h: 5),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, h) in const [
                        6.0,
                        9.0,
                        5.0,
                        11.0,
                        7.0,
                      ].indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: i == 4 ? colors.primary : muted,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: Container(height: 14, decoration: cardBox())),
                ],
              ],
            ),
            const Spacer(),
            Center(
              child: Container(
                width: 34,
                height: 9,
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: colors.outlineVariant, width: 0.6),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 11,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-hand side of a diagonal split (dark half of the System preview).
class _DiagonalHalfClipper extends CustomClipper<Path> {
  const _DiagonalHalfClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * 0.62, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * 0.38, size.height)
    ..close();

  @override
  bool shouldReclip(_DiagonalHalfClipper oldClipper) => false;
}

/// Accent palettes offered as one-tap swatches (the rest live in "More").
const List<FlexScheme> kSuggestedAccentSchemes = [
  FlexScheme.indigoM3,
  FlexScheme.blueM3,
  FlexScheme.tealM3,
  FlexScheme.greenM3,
  FlexScheme.orangeM3,
  FlexScheme.redM3,
  FlexScheme.pinkM3,
  FlexScheme.purpleM3,
];

/// Accent color swatches plus a "More" button for the full list.
class AccentSwatchRow extends StatelessWidget {
  const AccentSwatchRow({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final FlexScheme selected;
  final ValueChanged<FlexScheme> onSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final options = [
      if (!kSuggestedAccentSchemes.contains(selected)) selected,
      ...kSuggestedAccentSchemes,
    ];
    // Fade the trailing edge so it reads as scrollable.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        colors: [Colors.black, Colors.black, Colors.transparent],
        stops: [0, 0.88, 1],
      ).createShader(rect),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final s in options) ...[
              _Swatch(
                color: s.colors(brightness).primary,
                name: s.data.name,
                selected: s == selected,
                onTap: () => onSelected(s),
              ),
              const SizedBox(width: 8),
            ],
            _MoreSwatch(onTap: onMore),
            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context, AppMotion.fast);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name accent',
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        child: PressableScale(
          scale: 0.9,
          child: GestureDetector(
            onTap: selected ? null : onTap,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              padding: EdgeInsets.all(selected ? 4 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: AnimatedOpacity(
                  duration: duration,
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_rounded, size: 20, color: onColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreSwatch extends StatelessWidget {
  const _MoreSwatch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Semantics(
      button: true,
      label: 'More accent colors',
      excludeSemantics: true,
      child: Tooltip(
        message: 'More colors',
        child: PressableScale(
          scale: 0.9,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHigh,
                border: Border.all(color: context.appColors.hairline),
              ),
              child: Icon(
                Icons.palette_outlined,
                size: 20,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
