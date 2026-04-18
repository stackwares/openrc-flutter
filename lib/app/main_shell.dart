import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/features/home/home_screen.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';

/// Selected tab index for [MainShell] (`0` = transactions, `1` = overview).
final mainShellTabIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _screens = [
    TransactionsScreen(),
    HomeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainShellTabIndexProvider);
    final scheme = Theme.of(context).colorScheme;
    // Wide enough for "Transactions" + "Overview" labels, padding, and font rounding.
    const barWidth = 280.0;

    return Scaffold(
      extendBody: true,
      body: BottomBar(
        fit: StackFit.expand,
        clip: Clip.none,
        hideOnScroll: false,
        showIcon: false,
        width: barWidth,
        offset: 12,
        borderRadius: BorderRadius.circular(28),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        barColor: scheme.surfaceContainerHigh,
        barDecoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.14),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        barAlignment: Alignment.bottomCenter,
        body: (context, scrollController) {
          // Full-bleed content; tab bar is painted above in [BottomBar]'s Stack.
          return SizedBox.expand(
            child: IndexedStack(
              index: currentIndex,
              children: _screens,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MainShellTabButton(
                selected: currentIndex == 0,
                label: 'Transactions',
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long_rounded,
                onTap: () {
                  ref.read(mainShellTabIndexProvider.notifier).state = 0;
                },
              ),
              const SizedBox(width: 4),
              _MainShellTabButton(
                selected: currentIndex == 1,
                label: 'Overview',
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard_rounded,
                onTap: () {
                  ref.read(mainShellTabIndexProvider.notifier).state = 1;
                },
              ),
            ],
          ),
        ),
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
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: -0.15,
        );

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
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
