import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Opens a detail screen: full screen on phones, and on larger windows as a
/// panel sliding in from the right so the list stays in view. Esc, the back
/// button or a click outside closes it.
Future<void> openDetail(BuildContext context, WidgetBuilder builder) {
  if (context.windowSize == WindowSize.compact) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: builder));
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: AppMotion.of(
      context,
      const Duration(milliseconds: 280),
    ),
    pageBuilder: (context, animation, secondaryAnimation) {
      final width = MediaQuery.sizeOf(context).width;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(480, width * 0.6),
          height: double.infinity,
          child: Material(
            elevation: 12,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(AppRadius.card),
              ),
            ),
            child: builder(context),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
