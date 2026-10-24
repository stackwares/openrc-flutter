import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A navigator inside a dialog, so screens and pickers opened from it slide
/// in on top with a back button, the way they do on a phone, rather than
/// opening more dialogs over the app.
///
/// Inside it, [MediaQuery] reports the dialog's size, so pages lay
/// themselves out for its width rather than the window's.
class DialogNavigator extends StatefulWidget {
  const DialogNavigator({super.key, required this.child});

  /// The first page.
  final Widget child;

  /// Whether [context] is inside a [DialogNavigator].
  static bool contains(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_DialogNavigatorScope>() != null;

  @override
  State<DialogNavigator> createState() => _DialogNavigatorState();
}

class _DialogNavigatorState extends State<DialogNavigator> {
  final _navigator = GlobalKey<NavigatorState>();

  /// Pages slide in from the side on every platform, as on iOS.
  static final _slide = PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: const CupertinoPageTransitionsBuilder(),
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: constraints.biggest),
        child: Theme(
          data: theme.copyWith(pageTransitionsTheme: _slide),
          child: _DialogNavigatorScope(
            // Back (Android, Esc on some platforms) leaves a pushed page
            // before it closes the dialog.
            child: NavigatorPopHandler<Object?>(
              onPopWithResult: (_) => _navigator.currentState?.maybePop(),
              child: Navigator(
                key: _navigator,
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogNavigatorScope extends InheritedWidget {
  const _DialogNavigatorScope({required super.child});

  @override
  bool updateShouldNotify(_DialogNavigatorScope oldWidget) => false;
}
