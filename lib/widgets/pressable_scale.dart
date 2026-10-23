import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shrinks its child slightly while a finger is down, like a physical press.
///
/// Uses a [Listener], so it never competes with the child's own tap handling;
/// a drag past the touch slop (the start of a scroll) releases the press.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  Offset? _downAt;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return Listener(
      onPointerDown: (e) {
        _downAt = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        final start = _downAt;
        if (start != null && (e.position - start).distance > kTouchSlop) {
          _set(false);
        }
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 220),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
