import 'package:flutter/widgets.dart';

/// The app's root navigator.
///
/// Actions that switch tabs (Ask, sign-out) close anything pushed on top
/// first, so the tab they switch to is what the user sees.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
