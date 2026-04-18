import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/features/home/home_screen.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';

/// Selected tab index for [MainShell]
/// (`0` = transactions, `1` = revenue, `2` = charts, `3` = settings).
final mainShellTabIndexProvider = StateProvider<int>((ref) => 0);

const _mainShellTabLabels = [
  'Transactions',
  'Revenue',
  'Charts',
  'Settings',
];

final _mainShellTabBarRadius = BorderRadius.circular(28);

/// Width of the floating tab bar (content + padding), not full-bleed.
double mainShellTabBarWidth(BuildContext context) {
  final theme = Theme.of(context);
  final baseStyle = theme.textTheme.labelSmall;
  if (baseStyle == null) return 320;
  final style = baseStyle.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    height: 1.05,
  );
  final textScaler = MediaQuery.textScalerOf(context);
  const outerHorizontalPadding = 8.0 * 2;
  const tabHorizontalPadding = 10.0 * 2;
  const iconSize = 22.0;
  const betweenTabs = 4.0;
  final textDir = Directionality.of(context);

  var sum = outerHorizontalPadding;
  for (var i = 0; i < _mainShellTabLabels.length; i++) {
    if (i > 0) sum += betweenTabs;
    final tp = TextPainter(
      text: TextSpan(text: _mainShellTabLabels[i], style: style),
      textDirection: textDir,
      maxLines: 1,
      textScaler: textScaler,
    )..layout();
    final textW = tp.width;
    final colW = tabHorizontalPadding + (textW > iconSize ? textW : iconSize);
    sum += colW;
  }

  final maxW = MediaQuery.sizeOf(context).width - 2 * 12;
  // Small cushion for glyph/layout differences vs [TextPainter].
  return (sum + 6).clamp(120.0, maxW);
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _screens = [
    TransactionsScreen(),
    RealtimeTransactionsScreen(),
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(transactionsProvider.notifier).fetchInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainShellTabIndexProvider);
    final barW = mainShellTabBarWidth(context);

    return Scaffold(
      extendBody: true,
      body: BottomBar(
        fit: StackFit.expand,
        clip: Clip.none,
        hideOnScroll: false,
        showIcon: false,
        width: barW,
        offset: 12,
        borderRadius: _mainShellTabBarRadius,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        barColor: Colors.transparent,
        barDecoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: _mainShellTabBarRadius,
        ),
        barAlignment: Alignment.bottomCenter,
        body: (context, scrollController) {
          // Full-bleed content; tab bar is painted above in [BottomBar]'s Stack.
          // Cross-fade between tabs while keeping every screen mounted (state).
          final tabFadeDuration = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260);
          return SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: tabFadeDuration,
                      curve: Curves.easeOutCubic,
                      opacity: currentIndex == i ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: currentIndex != i,
                        child: _screens[i],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        child: _GlassTabBarChrome(
          borderRadius: _mainShellTabBarRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MainShellTabButton(
                    selected: currentIndex == 0,
                    label: _mainShellTabLabels[0],
                    icon: Icons.receipt_long_outlined,
                    selectedIcon: Icons.receipt_long_rounded,
                    onTap: () {
                      ref.read(mainShellTabIndexProvider.notifier).state = 0;
                    },
                  ),
                  const SizedBox(width: 4),
                  _MainShellTabButton(
                    selected: currentIndex == 1,
                    label: _mainShellTabLabels[1],
                    icon: Icons.payments_outlined,
                    selectedIcon: Icons.payments_rounded,
                    onTap: () {
                      ref.read(mainShellTabIndexProvider.notifier).state = 1;
                    },
                  ),
                  const SizedBox(width: 4),
                  _MainShellTabButton(
                    selected: currentIndex == 2,
                    label: _mainShellTabLabels[2],
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard_rounded,
                    onTap: () {
                      ref.read(mainShellTabIndexProvider.notifier).state = 2;
                    },
                  ),
                  const SizedBox(width: 4),
                  _MainShellTabButton(
                    selected: currentIndex == 3,
                    label: _mainShellTabLabels[3],
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings_rounded,
                    onTap: () {
                      ref.read(mainShellTabIndexProvider.notifier).state = 3;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted blur + translucent layers for a floating “glass” tab bar.
class _GlassTabBarChrome extends StatelessWidget {
  const _GlassTabBarChrome({
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sigma = reduceMotion ? 0.0 : 22.0;

    final frost = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLow.withValues(alpha: isDark ? 0.42 : 0.50),
            scheme.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.36 : 0.40,
            ),
          ],
        ),
        border: Border.all(
          width: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.62),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, 14),
            spreadRadius: -10,
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: isDark ? 0.12 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: child,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: sigma == 0
          ? frost
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: frost,
            ),
    );
  }
}

class _MainShellTabButton extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onTap;

  const _MainShellTabButton({
    required this.selected,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.05,
        );

    final pillRadius = BorderRadius.circular(18);

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: selected
              ? BoxDecoration(
                  borderRadius: pillRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primary.withValues(alpha: isDark ? 0.22 : 0.18),
                      scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                    ],
                  ),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                      spreadRadius: -2,
                    ),
                  ],
                )
              : null,
          child: Material(
            color: Colors.transparent,
            borderRadius: pillRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: pillRadius,
              splashColor: scheme.primary.withValues(alpha: 0.12),
              highlightColor: scheme.primary.withValues(alpha: 0.06),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      color: color,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: textStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
