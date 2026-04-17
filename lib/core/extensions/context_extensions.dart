import 'package:flutter/material.dart';

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

  void showSnackBar(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final hasAction =
        actionLabel != null && actionLabel.isNotEmpty && onAction != null;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
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
