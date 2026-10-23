import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating bottom tab bar, ported from baeble-flutter's `FloatingTabChrome`.
///
/// A stadium-shaped Material pill of icon-only destinations (labels live in
/// tooltips and semantics). The selected tab grows a NavigationBar-style
/// indicator. Colors come from the theme's [NavigationBarTheme], falling back
/// to the color scheme, so it follows revenuecat's FlexColorScheme theme.
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

  static const double barHeight = 68;

  /// Matches Baeble: tab-switch duration and curve.
  static const Duration motionDuration = Duration(milliseconds: 250);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// Bottom inset tab screens reserve so the bar never covers the last item:
  /// bar + chrome padding + breathing room + system safe area.
  static double bottomInset(BuildContext context) =>
      barHeight + 20 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
    final navTheme = NavigationBarTheme.of(context);

    return Material(
      color: navTheme.backgroundColor ?? scheme.surfaceContainer,
      elevation: navTheme.elevation ?? 3.0,
      shadowColor: navTheme.shadowColor,
      surfaceTintColor: navTheme.surfaceTintColor,
      shape: const StadiumBorder(),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Container(
          height: FloatingTabChrome.barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < destinations.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _FloatingTabButton(
                  spec: destinations[i],
                  selected: i == currentIndex,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onDestinationSelected(i);
                  },
                ),
              ],
            ],
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
    final navTheme = NavigationBarTheme.of(context);

    final iconColor = selected
        ? (navTheme.iconTheme?.resolve({WidgetState.selected})?.color ??
              scheme.onSecondaryContainer)
        : (navTheme.iconTheme?.resolve({})?.color ?? scheme.onSurfaceVariant);
    // Baeble falls back to onSecondary; secondaryContainer is the M3 indicator
    // color and keeps contrast with onSecondaryContainer in revenuecat's theme.
    final indicatorColor = navTheme.indicatorColor ?? scheme.secondaryContainer;
    final indicatorShape = navTheme.indicatorShape ?? const StadiumBorder();
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
            overlayColor: navTheme.overlayColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Center(
                child: AnimatedContainer(
                  duration: duration,
                  curve: FloatingTabChrome.motionCurve,
                  width: selected ? 60 : 48,
                  height: 40,
                  decoration: ShapeDecoration(
                    shape: indicatorShape,
                    color: selected ? indicatorColor : Colors.transparent,
                  ),
                  child: Center(
                    child: Icon(
                      selected ? spec.selectedIcon : spec.icon,
                      size: 22,
                      color: iconColor,
                      semanticLabel: spec.label,
                    ),
                  ),
                ),
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
