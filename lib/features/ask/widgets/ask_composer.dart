import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Hardware keyboards send with Enter and break lines with Shift+Enter.
bool get _enterSends =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// The question field: grows to a few lines, sends with the round button
/// (or Enter on a hardware keyboard), and turns into Stop while the model
/// works.
class AskComposer extends StatelessWidget {
  const AskComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.running,
    required this.onSend,
    required this.onStop,
    this.onLocked,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// When set, the field is read-only and taps / send open this instead.
  final VoidCallback? onLocked;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enterSends || event is! KeyDownEvent) return KeyEventResult.ignored;
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // An input method still composing (Japanese, Chinese…) owns Enter.
    if (controller.value.composing.isValid) return KeyEventResult.ignored;
    if (onLocked != null) {
      onLocked!();
      return KeyEventResult.handled;
    }
    if (!running) onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final hasText = controller.text.trim().isNotEmpty;
        final locked = onLocked != null;
        final focused = focusNode.hasFocus && !locked;
        return AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: dark
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: focused
                  ? scheme.primary.withValues(alpha: 0.6)
                  : context.appColors.hairline,
              width: focused ? 1.5 : 1,
            ),
            boxShadow: [
              if (!dark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: locked,
                    enableInteractiveSelection: !locked,
                    onTap: locked ? onLocked : null,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: context.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: locked
                          ? 'agent.setup.composerHint'.tr()
                          : 'agent.composerHint'.tr(),
                      hintStyle: context.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        15,
                        AppSpace.xs,
                        15,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.xs - 1),
                child: AnimatedSwitcher(
                  duration: AppMotion.of(context, AppMotion.fast),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: running
                      ? _RoundButton(
                          key: const ValueKey('stop'),
                          tooltip: 'agent.stop'.tr(),
                          icon: Icons.stop_rounded,
                          background: scheme.onSurface,
                          foreground: scheme.surface,
                          onPressed: onStop,
                        )
                      : _RoundButton(
                          key: const ValueKey('send'),
                          tooltip: 'agent.send'.tr(),
                          icon: Icons.arrow_upward_rounded,
                          background: scheme.primary,
                          foreground: scheme.onPrimary,
                          onPressed: locked
                              ? onLocked
                              : hasText
                              ? onSend
                              : null,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.32),
      ),
    );
  }
}
