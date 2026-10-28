import 'package:flutter/material.dart';
import 'package:openrc/theme/app_colors.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  EdgeInsets get padding => mediaQuery.padding;
  bool get isDark => theme.brightness == Brightness.dark;
  AppColors get appColors => AppColors.of(this);

  /// Shows [message] above the bottom of the screen, and takes it down again
  /// by itself after [duration]: a few seconds for a plain message, longer
  /// when there's an action to read and tap.
  ///
  /// Material keeps a snackbar with an action on screen until it's dismissed
  /// by hand (`SnackBar.persist` defaults to `action != null`), so the toasts
  /// this app shows with an action would never go away on their own;
  /// [SnackBar.persist] is therefore always false here.
  ///
  /// Material queues snackbars; [replace] takes the current one down first, so
  /// a message about what just happened is not read after a stale one.
  void showSnackBar(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
    bool replace = false,
    Duration? duration,
  }) {
    final hasAction =
        actionLabel != null && actionLabel.isNotEmpty && onAction != null;
    final messenger = ScaffoldMessenger.of(this);
    if (replace) messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        persist: false,
        duration: duration ?? Duration(seconds: hasAction ? 6 : 4),
        action: hasAction
            ? SnackBarAction(
                label: actionLabel,
                onPressed: onAction,
                textColor: isError ? colorScheme.onError : null,
              )
            : null,
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? colorScheme.error : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
