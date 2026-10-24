import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// The macOS menu bar. Its shortcuts work from any screen, Settings
/// included, and its items dim while signed out.
class MacMenuBar extends ConsumerWidget {
  const MacMenuBar({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    VoidCallback? whenSignedIn(VoidCallback action) => signedIn ? action : null;

    void backToShell() =>
        navigatorKey.currentState?.popUntil((route) => route.isFirst);

    void showTab(int index) {
      backToShell();
      ref.read(mainShellTabIndexProvider.notifier).state = index;
    }

    void stepDay(int delta) {
      showTab(0);
      stepTransactionsDay(ref, delta);
    }

    PlatformMenuItem item(
      String label,
      LogicalKeyboardKey key,
      VoidCallback action, {
      bool shift = false,
    }) => PlatformMenuItem(
      label: label,
      shortcut: SingleActivator(key, meta: true, shift: shift),
      onSelected: whenSignedIn(action),
    );

    PlatformMenuItem provided(PlatformProvidedMenuItemType type) =>
        PlatformProvidedMenuItem(type: type);

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: AppConstants.appName,
          menus: [
            PlatformMenuItemGroup(
              members: [provided(PlatformProvidedMenuItemType.about)],
            ),
            PlatformMenuItemGroup(
              members: [
                item('shell.menu.settings'.tr(), LogicalKeyboardKey.comma, () {
                  backToShell();
                  final navigatorContext = navigatorKey.currentContext;
                  if (navigatorContext != null) {
                    SettingsScreen.open(navigatorContext);
                  }
                }),
              ],
            ),
            PlatformMenuItemGroup(
              members: [provided(PlatformProvidedMenuItemType.servicesSubmenu)],
            ),
            PlatformMenuItemGroup(
              members: [
                provided(PlatformProvidedMenuItemType.hide),
                provided(PlatformProvidedMenuItemType.hideOtherApplications),
                provided(PlatformProvidedMenuItemType.showAllApplications),
              ],
            ),
            PlatformMenuItemGroup(
              members: [provided(PlatformProvidedMenuItemType.quit)],
            ),
          ],
        ),
        PlatformMenu(
          label: 'shell.menu.view'.tr(),
          menus: [
            PlatformMenuItemGroup(
              members: [
                item('shell.tabs.transactions'.tr(), LogicalKeyboardKey.digit1, () {
                  showTab(0);
                }),
                item(
                  'shell.tabs.revenue'.tr(),
                  LogicalKeyboardKey.digit2,
                  () => showTab(1),
                ),
                item(
                  'shell.tabs.charts'.tr(),
                  LogicalKeyboardKey.digit3,
                  () => showTab(2),
                ),
                item(
                  'shell.tabs.ask'.tr(),
                  LogicalKeyboardKey.digit4,
                  () => showTab(3),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                item(
                  'shell.menu.previousDay'.tr(),
                  LogicalKeyboardKey.bracketLeft,
                  () => stepDay(-1),
                ),
                item(
                  'shell.menu.nextDay'.tr(),
                  LogicalKeyboardKey.bracketRight,
                  () {
                    stepDay(1);
                  },
                ),
                item(
                  'shell.menu.askAboutDay'.tr(),
                  LogicalKeyboardKey.keyK,
                  () => openAskAboutSelectedDay(ref),
                  shift: true,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                item('shell.menu.refresh'.tr(), LogicalKeyboardKey.keyR, () {
                  refreshShellTab(ref);
                }),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                provided(PlatformProvidedMenuItemType.toggleFullScreen),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'shell.menu.window'.tr(),
          menus: [
            provided(PlatformProvidedMenuItemType.minimizeWindow),
            provided(PlatformProvidedMenuItemType.zoomWindow),
            provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ],
        ),
        PlatformMenu(
          label: 'shell.menu.help'.tr(),
          menus: [
            PlatformMenuItem(
              label: 'shell.menu.onGitHub'.tr(
                namedArgs: {'app': AppConstants.appName},
              ),
              onSelected: () => launchUrl(Uri.parse(AppConstants.repoUrl)),
            ),
            PlatformMenuItem(
              label: 'shell.menu.reportIssue'.tr(),
              onSelected: () => launchUrl(Uri.parse(AppConstants.newIssueUrl)),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
