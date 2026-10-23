import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating bottom tab bar, ported from baeble-flutter's `FloatingTabChrome`.
///
/// A slim stadium-shaped pill on a neutral surface with a hairline border.
/// Each destination shows its icon and label; the selected tab sits on an
/// accent-tinted indicator pill.
class FloatingTabChrome extends StatelessWidget {
  const FloatingTabChrome({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final List<FloatingTabDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  static const double barHeight = 64;

  /// Same slot for every destination so the pill wraps with even spacing.
  static const double tabSlotWidth = 100;

  /// Matches Baeble: tab-switch duration and curve.
  static const Duration motionDuration = Duration(milliseconds: 250);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// Bottom inset tab screens reserve so the bar never covers the last item:
  /// bar height, a small gap, and the system safe area.
  static double bottomInset(BuildContext context) =>
      barHeight + 16 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: _FloatingPillBar(
            destinations: destinations,
            currentIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ),
    );
  }
}

class FloatingTabDestination {
  const FloatingTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _FloatingPillBar extends StatelessWidget {
  const _FloatingPillBar({
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final List<FloatingTabDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final background = dark
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLowest;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: background.withValues(alpha: 0.96),
        shape: StadiumBorder(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 1 : 0.9),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Container(
            height: FloatingTabChrome.barHeight,
            padding: const EdgeInsets.all(6),
            child: Stack(
              children: [
                // One indicator that glides to the selected slot.
                AnimatedPositioned(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: currentIndex * FloatingTabChrome.tabSlotWidth,
                  top: 0,
                  bottom: 0,
                  width: FloatingTabChrome.tabSlotWidth,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: scheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      SizedBox(
                        width: FloatingTabChrome.tabSlotWidth,
                        child: _FloatingTabButton(
                          spec: destinations[i],
                          selected: i == currentIndex,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onDestinationSelected(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingTabButton extends StatelessWidget {
  const _FloatingTabButton({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final FloatingTabDestination spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FloatingTabChrome.motionDuration;

    return Tooltip(
      message: spec.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: spec.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: selected ? null : onTap,
            customBorder: const StadiumBorder(),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: duration,
              curve: FloatingTabChrome.motionCurve,
              builder: (context, tint, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1 : 0.92,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: Icon(
                      selected ? spec.selectedIcon : spec.icon,
                      size: 22,
                      color: tint,
                      semanticLabel: spec.label,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tint,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.1,
                    ),
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

/// Direction-aware slide + fade for tab switches (from Baeble).
///
/// Higher index slides in from the right, lower from the left. [child] stays
/// mounted so tab state is preserved. Reduced-motion users get an instant swap.
class TabSwitchTransition extends StatefulWidget {
  const TabSwitchTransition({
    super.key,
    required this.currentIndex,
    required this.child,
  });

  final int currentIndex;
  final Widget child;

  @override
  State<TabSwitchTransition> createState() => _TabSwitchTransitionState();
}

class _TabSwitchTransitionState extends State<TabSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FloatingTabChrome.motionDuration,
    value: 1,
  );
  late Animation<Offset> _slide = const AlwaysStoppedAnimation(Offset.zero);
  late Animation<double> _fade = const AlwaysStoppedAnimation(1);

  @override
  void didUpdateWidget(TabSwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == oldWidget.currentIndex) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final direction = widget.currentIndex > oldWidget.currentIndex ? 1.0 : -1.0;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: FloatingTabChrome.motionCurve,
    );
    _slide = Tween<Offset>(
      begin: Offset(0.12 * direction, 0),
      end: Offset.zero,
    ).animate(curved);
    _fade = Tween<double>(begin: 0.4, end: 1).animate(curved);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
