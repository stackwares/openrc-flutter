import 'package:flutter/widgets.dart';
import 'package:openrc/app/floating_tab_chrome.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Extra space below scrollable content so [FloatingTabChrome] never covers
/// it. Larger windows navigate from a rail or sidebar, so only the safe area
/// and a little breathing room remain.
double mainShellFloatingTabBarScrollPadding(BuildContext context) =>
    context.windowSize == WindowSize.compact
    ? FloatingTabChrome.bottomInset(context)
    : MediaQuery.paddingOf(context).bottom + 24;
