import 'package:flutter/widgets.dart';
import 'package:revenuecat/app/floating_tab_chrome.dart';

/// Extra space below scrollable content so [FloatingTabChrome] never covers it.
double mainShellFloatingTabBarScrollPadding(BuildContext context) =>
    FloatingTabChrome.bottomInset(context);
