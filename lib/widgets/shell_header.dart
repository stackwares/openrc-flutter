import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Top bar for the three main tabs: a bold title, an optional muted subtitle,
/// and round icon actions.
class ShellHeader extends StatelessWidget implements PreferredSizeWidget {
  const ShellHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.onTitleTap,
    this.titleTapTooltip,
    this.contentMaxWidth,
  });

  final String title;
  final String? subtitle;

  /// Makes the title a button (e.g. a date picker), marked with a chevron.
  final VoidCallback? onTitleTap;
  final String? titleTapTooltip;

  /// Shown right after the title (e.g. day navigation).
  final Widget? leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  /// Widest the tab's content grows in a given width. Past it the content
  /// centers, and the title and actions move in with it instead of sitting
  /// at the window's edges.
  final double Function(double width)? contentMaxWidth;

  static const double toolbarHeight = 68;

  /// Phones refresh by pulling; desktop and the web (mouse) can't pull.
  static bool get showsRefreshButton =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 24,
        letterSpacing: -0.4,
        height: 1.15,
        color: scheme.onSurface,
      ),
    );
    // Day / range changes slide the new title in.
    Widget titleBlock = AnimatedSwitcher(
      duration: AppMotion.of(context, const Duration(milliseconds: 240)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey('$title|$subtitle'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTitleTap == null)
            titleText
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: titleText),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
    final onTap = onTitleTap;
    if (onTap != null) {
      // Padded so the press highlight frames the text; the title spacing
      // takes the padding back so it lines up with the other tabs.
      titleBlock = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _titleTapInset,
            vertical: 2,
          ),
          child: titleBlock,
        ),
      );
      final tooltip = titleTapTooltip;
      if (tooltip != null) {
        titleBlock = Tooltip(message: tooltip, child: titleBlock);
      }
    }
    final titleRow = Row(
      children: [
        Flexible(child: titleBlock),
        if (leading != null) ...[const SizedBox(width: 8), leading!],
      ],
    );
    AppBar bar({double inset = 0}) => AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      titleSpacing: inset + (onTitleTap == null ? 20 : 20 - _titleTapInset),
      title: titleRow,
      actions: [...actions, SizedBox(width: 12 + inset)],
      bottom: bottom,
    );
    final maxWidth = contentMaxWidth;
    if (maxWidth == null) return bar();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return bar(
          inset: AppBreakpoints.centeringInset(
            width,
            maxWidth: maxWidth(width),
          ),
        );
      },
    );
  }

  static const double _titleTapInset = 6;
}

/// 36px round icon button used in [ShellHeader].
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Small accent dot (e.g. filters are active).
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            style: IconButton.styleFrom(
              fixedSize: const Size(36, 36),
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              backgroundColor: dark
                  ? scheme.surfaceContainer
                  : scheme.surfaceContainerLowest,
              foregroundColor: scheme.onSurface,
              disabledBackgroundColor:
                  (dark
                          ? scheme.surfaceContainer
                          : scheme.surfaceContainerLowest)
                      .withValues(alpha: 0.5),
              side: BorderSide(color: context.appColors.hairline),
            ),
          ),
          if (badge)
            Positioned(
              top: 6,
              right: 6,
              child: IgnorePointer(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
