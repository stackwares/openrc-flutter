import 'package:flutter/widgets.dart';

/// Extra space below scrollable content when [MainShell] uses a floating tab bar.
double mainShellFloatingTabBarScrollPadding(BuildContext context) {
  const pillHeightAndMargin = 88.0;
  return pillHeightAndMargin + MediaQuery.viewPaddingOf(context).bottom;
}
