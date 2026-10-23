import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/app/floating_tab_chrome.dart';
import 'package:revenuecat/features/charts/home_screen.dart';
import 'package:revenuecat/features/revenue/revenue_screen.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';

/// Selected tab index for [MainShell]
/// (`0` = transactions, `1` = revenue, `2` = charts).
final mainShellTabIndexProvider = StateProvider<int>((ref) => 0);

const _mainShellTabs = <FloatingTabDestination>[
  FloatingTabDestination(
    label: 'Transactions',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  FloatingTabDestination(
    label: 'Revenue',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
  FloatingTabDestination(
    label: 'Charts',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
];

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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(transactionsProvider.notifier).fetchInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainShellTabIndexProvider);

    // Content extends behind the floating bar; each tab pads its scrollables
    // with [mainShellFloatingTabBarScrollPadding].
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: TabSwitchTransition(
              currentIndex: currentIndex,
              // Keeps every tab mounted so scroll positions and state survive.
              child: IndexedStack(index: currentIndex, children: _screens),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingTabChrome(
              destinations: _mainShellTabs,
              currentIndex: currentIndex,
              onDestinationSelected: (index) {
                ref.read(mainShellTabIndexProvider.notifier).state = index;
              },
            ),
          ),
        ],
      ),
    );
  }
}
