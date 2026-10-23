import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Six boxes for an authenticator code, backed by one hidden text field so
/// typing, pasting ("123 456" works) and iOS code autofill all just work.
/// Calls [onCompleted] as soon as the last digit is entered.
class VerificationCodeInput extends StatefulWidget {
  const VerificationCodeInput({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.focusNode,
    this.length = 6,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final FocusNode? focusNode;
  final int length;

  /// False while a code is being checked: input is ignored but focus (and
  /// the keyboard) stays, so a retry needs no extra tap.
  final bool enabled;
  final bool hasError;
  final bool autofocus;

  @override
  State<VerificationCodeInput> createState() => _VerificationCodeInputState();
}

class _VerificationCodeInputState extends State<VerificationCodeInput> {
  late final FocusNode _ownFocus = FocusNode();

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.removeListener(_onFocus);
    _ownFocus.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  String _lastCompleted = '';

  void _onChanged() {
    setState(() {});
    final code = widget.controller.text;
    if (code.length == widget.length && code != _lastCompleted) {
      _lastCompleted = code;
      widget.onCompleted(code);
    } else if (code.length < widget.length) {
      _lastCompleted = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final focused = _focus.hasFocus;
    final half = widget.length ~/ 2;

    final boxes = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) SizedBox(width: i == half ? 18 : 8),
          Flexible(
            child: _CodeBox(
              digit: i < code.length ? code[i] : null,
              active: focused && widget.enabled && i == code.length,
              hasError: widget.hasError,
            ),
          ),
        ],
      ],
    );

    return Semantics(
      label: 'signIn.verificationCode'.tr(),
      value: 'signIn.codeProgress'.tr(
        namedArgs: {'entered': '${code.length}', 'total': '${widget.length}'},
      ),
      textField: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(child: boxes),
          // The real input: invisible, covering the boxes so a tap focuses
          // it and a long press offers Paste.
          Positioned.fill(
            child: Opacity(
              opacity: 0.011,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                readOnly: !widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                autocorrect: false,
                enableSuggestions: false,
                showCursor: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                style: const TextStyle(color: Colors.transparent),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final String? digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final colors = context.appColors;
    final duration = AppMotion.of(context, AppMotion.fast);
    final borderColor = hasError
        ? colors.negative
        : active
        ? scheme.primary
        : digit != null
        ? scheme.outline
        : colors.hairline;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      height: 58,
      constraints: const BoxConstraints(maxWidth: 50),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.row),
        border: Border.all(color: borderColor, width: active ? 2 : 1.2),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: duration,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: digit == null
            ? (active ? _Caret(color: scheme.primary) : const SizedBox.shrink())
            : Text(
                digit!,
                key: ValueKey(digit),
                style: AppText.amount(context, size: 24),
              ),
      ),
    );
  }
}

/// Blinking caret in the active empty box.
class _Caret extends StatefulWidget {
  const _Caret({required this.color});

  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink
        ..stop()
        ..value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        opacity: _blink.value < 0.5 ? 1 : 0,
        child: Container(width: 2, height: 26, color: widget.color),
      ),
    );
  }
}
