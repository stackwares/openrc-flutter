import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

const double _dialogMaxWidth = 560;
const double _dialogMaxHeight = 680;

/// Opens [builder] as a bottom sheet on phones and as a centered dialog on
/// larger windows, so pickers and forms sit where each device expects them.
///
/// [heightFactor] gives list-style content a fixed height: that share of
/// the screen in a sheet, and a comfortable fixed height in a dialog. Leave
/// it null for content that sizes itself.
///
/// [dialogMaxWidth] and [dialogMaxHeight] let content with a wide layout
/// (columns side by side) use more of a large window.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
  double dialogMaxWidth = _dialogMaxWidth,
  double dialogMaxHeight = _dialogMaxHeight,
}) {
  if (context.windowSize == WindowSize.compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final content = SafeArea(top: false, child: builder(context));
        if (heightFactor == null) return content;
        final view = MediaQuery.of(context);
        // The drag handle sits above the content: leave it out, so the
        // whole sheet is [heightFactor] of the screen.
        final sheetHeight =
            (view.size.height - view.viewInsets.bottom) * heightFactor;
        return Padding(
          padding: EdgeInsets.only(bottom: view.viewInsets.bottom),
          child: SizedBox(
            height: sheetHeight - kMinInteractiveDimension,
            child: content,
          ),
        );
      },
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final width = math.min(dialogMaxWidth, size.width - 80);
      final maxHeight = math.min(dialogMaxHeight, size.height * 0.85);
      // Room at the top where a sheet would have its drag handle.
      final content = Padding(
        padding: const EdgeInsets.only(top: 20),
        child: builder(context),
      );
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: heightFactor == null ? null : maxHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: content,
          ),
        ),
      );
    },
  );
}

/// A short form or confirmation: an [AlertDialog] on larger windows, and on
/// phones a bottom sheet with full-width buttons, the main action first.
///
/// [actions] are in dialog order, main action last.
Future<T?> showAdaptiveForm<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder content,
  required List<Widget> Function(BuildContext context) actions,
}) {
  if (context.windowSize != WindowSize.compact) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: content(context),
        actions: actions(context),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              child: content(context),
            ),
            const SizedBox(height: 24),
            for (final action in actions(context).reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(height: 50, child: action),
              ),
          ],
        ),
      ),
    ),
  );
}
