import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/app/floating_tab_chrome.dart';
import 'package:openrc/core/l10n/app_locales.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/features/ask/ask_launch.dart';
import 'package:openrc/features/ask/ask_providers.dart';
import 'package:openrc/features/ask/ask_screen.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/features/charts/home_screen.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/features/revenue/revenue_screen.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/settings/widgets/account_header.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/onboarding_analytics.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/push/push_display.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:openrc/widgets/side_panel.dart';

/// Selected tab index for [MainShell]
/// (`0` = transactions, `1` = revenue, `2` = charts, `3` = ask).
final mainShellTabIndexProvider = StateProvider<int>((ref) => 0);

const _mainShellTabs = <FloatingTabDestination>[
  FloatingTabDestination(
    label: 'shell.tabs.transactions',
    telemetryLabel: 'Transactions',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  FloatingTabDestination(
    label: 'shell.tabs.revenue',
    telemetryLabel: 'Revenue',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
  FloatingTabDestination(
    label: 'shell.tabs.charts',
    telemetryLabel: 'Charts',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
  FloatingTabDestination(
    label: 'shell.tabs.ask',
    telemetryLabel: 'Ask',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome_rounded,
  ),
];

bool get _usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Browsers keep ⌘/Ctrl+number, reload and settings for themselves, so the
/// app only claims them in native builds.
bool get _claimsModifierShortcuts => !kIsWeb;

/// Hints are for a hardware keyboard: desktop apps, not phones or tablets.
bool get _showsShortcutHints =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

String _shortcutLabel(String key) => _usesCommandKey ? '⌘$key' : 'Ctrl+$key';

/// Reloads what the selected tab shows (keyboard shortcut and menu bar).
void refreshShellTab(WidgetRef ref) {
  final index = ref.read(mainShellTabIndexProvider);
  // Ask has nothing to reload; a running answer keeps going.
  if (index == 3) return;
  if (index == 2) {
    ref.read(homeProvider.notifier).fetchData();
  } else if (!ref.read(transactionsProvider).isLoading) {
    ref.read(transactionsProvider.notifier).fetchInitial();
  }
}

/// Jump to Ask and optionally prefill the composer (⌘K from other tabs).
void openAskTab(WidgetRef ref, {String? prefill, String? transactionId}) {
  ref.read(mainShellTabIndexProvider.notifier).state = 3;
  final prompt = prefill?.trim();
  if (prompt != null && prompt.isNotEmpty) {
    ref.read(askPrefillProvider.notifier).state = prompt;
  }
  final id = transactionId?.trim();
  ref.read(askFocusTransactionIdProvider.notifier).state =
      (id != null && id.isNotEmpty) ? id : null;
  ref.read(askFocusTickProvider.notifier).state++;
}

void openAskAboutSelectedDay(WidgetRef ref) {
  openAskTab(
    ref,
    prefill: AskPrefills.selectedDay(
      ref.read(transactionsProvider).selectedDayKey,
    ),
  );
}

/// The signed-in app: a floating tab bar on phones, a navigation rail on
/// tablets and a sidebar on wide windows, around the same four tabs.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _screens = [
    TransactionsScreen(),
    RealtimeTransactionsScreen(),
    HomeScreen(),
    AskScreen(),
  ];

  /// Moves the tabs between layouts on resize without losing their state.
  final _contentKey = GlobalKey();

  late final List<StreamSubscription<Object>> _pushSubscriptions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onboarding = ref.read(onboardingPrefsProvider);
      if (!onboarding.focusApplied) {
        if (onboarding.focus != null) {
          ref.read(mainShellTabIndexProvider.notifier).state =
              onboardingTabIndexForFocus(onboarding.focus);
        }
        unawaited(ref.read(onboardingPrefsProvider.notifier).markFocusApplied());
      }
      if (onboarding.pendingHomeArrived) {
        logOnboardingEvent(onboardingHomeArrivedEvent(), track: true);
        unawaited(ref.read(onboardingPrefsProvider.notifier).markHomeArrived());
      }
      ref.read(transactionsProvider.notifier).fetchInitial();
      Telemetry.screen(
        _mainShellTabs[ref.read(mainShellTabIndexProvider)].telemetryName,
      );
    });
    _pushSubscriptions = [
      PushNotifications.onMessage.listen(_onPushWhileOpen),
      PushNotifications.onMessageOpenedApp.listen(_openFromPush),
      PushNotifications.webOpens.listen(_applyAskLaunch),
    ];
    PushNotifications.initialMessage().then((message) {
      if (message != null && mounted) _openFromPush(message);
    });
    final webLaunch = PushNotifications.webLaunch;
    if (webLaunch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyAskLaunch(webLaunch);
      });
    }
    // Starts notifications (re-subscribing this device) and finishes removing
    // webhooks that an earlier turn-off or log-out couldn't.
    ref.read(pushSettingsProvider.notifier).retryPendingRemovals();
    // Notifications show amounts the way Settings does.
    ref.listenManual(
      displayCurrencyProvider,
      (_, _) => _syncPushDisplay(),
      fireImmediately: true,
    );
    ref.listenManual(commissionSettingsProvider, (_, _) => _syncPushDisplay());
    ref.listenManual(usdExchangeRatesProvider, (_, _) => _syncPushDisplay());
  }

  Timer? _pushDisplayTimer;

  /// The language notifications were last handed.
  String? _pushLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Notifications follow the app's language, picked or the device's.
    final locale = EasyLocalization.of(context)?.locale;
    final language = locale == null ? null : AppLocales.fileStem(locale);
    if (language != null && language != _pushLanguage) {
      _pushLanguage = language;
      _syncPushDisplay();
    }
  }

  /// Hands Settings' language, currency and store fees to notifications.
  /// Waits a moment, so settings still loading at launch arrive as one
  /// change.
  void _syncPushDisplay() {
    _pushDisplayTimer?.cancel();
    _pushDisplayTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final currency = ref.read(displayCurrencyProvider);
      final fees = ref.read(commissionSettingsProvider);
      final previous = ref.read(pushSettingsProvider).display;
      final rate =
          ref.read(usdExchangeRatesProvider).value?[currency.toLowerCase()] ??
          (previous.currency == currency ? previous.rate : null);
      ref
          .read(pushSettingsProvider.notifier)
          .setDisplay(
            PushDisplay(
              currency: currency,
              appleFee: fees.adjustmentEnabled
                  ? fees.appleCommissionPercent
                  : null,
              googleFee: fees.adjustmentEnabled
                  ? fees.googleCommissionPercent
                  : null,
              rate: rate,
              language: _pushLanguage ?? 'en',
            ),
          );
    });
  }

  @override
  void dispose() {
    for (final subscription in _pushSubscriptions) {
      subscription.cancel();
    }
    _pushDisplayTimer?.cancel();
    super.dispose();
  }

  void _reloadTransactions() {
    if (!ref.read(transactionsProvider).isLoading) {
      ref.read(transactionsProvider.notifier).fetchInitial();
    }
  }

  /// A RevenueCat event arrived while the app is open: show it in the list.
  /// iOS and macOS show the banner themselves; Android doesn't.
  void _onPushWhileOpen(RemoteMessage message) {
    _reloadTransactions();
    final title = message.notification?.title;
    if (defaultTargetPlatform != TargetPlatform.android || title == null) {
      return;
    }
    final id = AskLaunch.boundedId(
      message.data['transaction_id'] is String
          ? message.data['transaction_id'] as String
          : null,
    );
    context.showSnackBar(
      title,
      actionLabel: id == null ? null : 'agent.askAbout'.tr(),
      onAction: id == null
          ? null
          : () => openAskTab(
              ref,
              prefill: AskPrefills.sale(),
              transactionId: id,
            ),
    );
  }

  void _openFromPush(RemoteMessage message) {
    final id = message.data['transaction_id'];
    _openTransaction(id is String ? id : null);
  }

  void _applyAskLaunch(AskLaunch launch) {
    if (launch.isEmpty) return;
    if (launch.openAsk) {
      openAskTab(
        ref,
        prefill: launch.prompt ?? AskPrefills.sale(),
        transactionId: launch.transactionId,
      );
      if (launch.transactionId != null) _reloadTransactions();
      return;
    }
    if (launch.transactionId != null) {
      _openTransaction(launch.transactionId);
    }
  }

  /// Tapping a notification opens the transaction it's about, once the
  /// list has it: RevenueCat's list can trail its webhooks by a few seconds.
  Future<void> _openTransaction(String? id) async {
    _select(0);
    final notifier = ref.read(transactionsProvider.notifier);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      if (!ref.read(transactionsProvider).isLoading) {
        await notifier.fetchInitial();
      }
      if (!mounted || id == null) return;
      final transaction = _findTransaction(id);
      if (transaction != null) {
        openDetail(
          context,
          (_) => TransactionDetailScreen(transaction: transaction),
        );
        return;
      }
    }
  }

  RcTransaction? _findTransaction(String storeTransactionId) {
    final state = ref.read(transactionsProvider);
    for (final day in [...state.grouped.values, ...state.jumpedDays.values]) {
      for (final tx in day) {
        if (tx.storeTransactionIdentifier == storeTransactionId) return tx;
      }
    }
    return null;
  }

  /// A running Ask answer keeps going on other tabs and is there on return.
  void _select(int index) {
    ref.read(mainShellTabIndexProvider.notifier).state = index;
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(int currentIndex) {
    SingleActivator withModifier(LogicalKeyboardKey key) =>
        SingleActivator(key, meta: _usesCommandKey, control: !_usesCommandKey);
    return {
      if (_claimsModifierShortcuts) ...{
        withModifier(LogicalKeyboardKey.digit1): () => _select(0),
        withModifier(LogicalKeyboardKey.digit2): () => _select(1),
        withModifier(LogicalKeyboardKey.digit3): () => _select(2),
        withModifier(LogicalKeyboardKey.digit4): () => _select(3),
        withModifier(LogicalKeyboardKey.keyK): () => openAskTab(ref),
        SingleActivator(
          LogicalKeyboardKey.keyK,
          meta: _usesCommandKey,
          control: !_usesCommandKey,
          shift: true,
        ): () => openAskAboutSelectedDay(ref),
        withModifier(LogicalKeyboardKey.keyR): () => refreshShellTab(ref),
        withModifier(LogicalKeyboardKey.comma): () =>
            SettingsScreen.open(context),
      },
      if (currentIndex == 0) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            stepTransactionsDay(ref, -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            stepTransactionsDay(ref, 1),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainShellTabIndexProvider);
    ref.listen<int>(mainShellTabIndexProvider, (previous, next) {
      if (previous != next) Telemetry.screen(_mainShellTabs[next].telemetryName);
    });
    final windowSize = context.windowSize;

    final content = KeyedSubtree(
      key: _contentKey,
      child: TabSwitchTransition(
        currentIndex: currentIndex,
        // Keeps every tab mounted so scroll positions and state survive.
        child: IndexedStack(index: currentIndex, children: _screens),
      ),
    );

    final Widget body = switch (windowSize) {
      // Content extends behind the floating bar; each tab pads its
      // scrollables with [mainShellFloatingTabBarScrollPadding].
      WindowSize.compact => Scaffold(
        extendBody: true,
        // The floating bar stays under the keyboard, as native tab bars do;
        // Ask, the only tab with a field on the page, lifts its composer.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: content),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingTabChrome(
                destinations: _mainShellTabs,
                currentIndex: currentIndex,
                onDestinationSelected: _select,
              ),
            ),
          ],
        ),
      ),
      WindowSize.medium || WindowSize.expanded => Scaffold(
        body: Row(
          children: [
            if (windowSize == WindowSize.medium)
              _ShellRail(currentIndex: currentIndex, onSelected: _select)
            else
              _ShellSidebar(currentIndex: currentIndex, onSelected: _select),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                child: content,
              ),
            ),
          ],
        ),
      ),
    };

    return CallbackShortcuts(
      bindings: _shortcuts(currentIndex),
      child: Focus(autofocus: true, child: body),
    );
  }
}

/// Hairline-edged column the rail and sidebar sit on.
class _NavSurface extends StatelessWidget {
  const _NavSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: context.appColors.hairline)),
      ),
      child: child,
    );
  }
}

/// Tablets: icons with labels, Settings at the bottom.
class _ShellRail extends StatelessWidget {
  const _ShellRail({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return _NavSurface(
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: currentIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: tt.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: tt.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        leading: const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 20),
          child: AppLogo(),
        ),
        trailingAtBottom: true,
        trailing: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: IconButton(
            tooltip: 'shell.settings'.tr(),
            icon: const Icon(Icons.settings_outlined),
            color: scheme.onSurfaceVariant,
            onPressed: () => SettingsScreen.open(context),
          ),
        ),
        destinations: [
          for (final tab in _mainShellTabs)
            NavigationRailDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: Text(tab.displayLabel),
            ),
        ],
      ),
    );
  }
}

/// Wide windows: logo, the three tabs with their shortcuts, then the
/// signed-in account, which opens Settings.
class _ShellSidebar extends StatelessWidget {
  const _ShellSidebar({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double width = 260;

  @override
  Widget build(BuildContext context) {
    final hints = _showsShortcutHints;
    return _NavSurface(
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Row(
                  children: [
                    const AppLogo(size: 34),
                    const SizedBox(width: 12),
                    Text(
                      AppConstants.appName,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < _mainShellTabs.length; i++)
                _SidebarItem(
                  icon: _mainShellTabs[i].icon,
                  selectedIcon: _mainShellTabs[i].selectedIcon,
                  label: _mainShellTabs[i].displayLabel,
                  selected: i == currentIndex,
                  shortcut: hints ? _shortcutLabel('${i + 1}') : null,
                  onTap: () => onSelected(i),
                ),
              const Spacer(),
              const Divider(height: 1),
              const _SidebarAccount(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.shortcut,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final radius = BorderRadius.circular(AppRadius.row);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        selected ? selectedIcon : icon,
                        size: 22,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyLarge?.copyWith(
                            color: selected ? scheme.primary : scheme.onSurface,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (shortcut != null)
                        Text(
                          shortcut!,
                          style: tt.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: AppText.tabular,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who is signed in; opens Settings.
class _SidebarAccount extends ConsumerWidget {
  const _SidebarAccount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final me = ref.watch(rcMeProvider);
    final name = me?.name?.trim();
    final email = me?.email?.trim();
    final hasName = name != null && name.isNotEmpty;
    final initials = SettingsAccountHeader.initialsFor(name, email);
    final settings = 'shell.settings'.tr();
    return Material(
      type: MaterialType.transparency,
      child: Tooltip(
        // The sidebar has no Settings row, so the shortcut shows here.
        message: _showsShortcutHints
            ? '$settings  ${_shortcutLabel(',')}'
            : settings,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: () => SettingsScreen.open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: initials.isEmpty
                      ? Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: scheme.primary,
                        )
                      : Text(
                          initials,
                          style: tt.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? name : (email ?? 'settings.revenueCatAccount'.tr()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasName && email != null && email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
