import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/app/main_shell.dart';
import 'package:revenuecat/features/sign_in/sign_in_screen.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_auth_service.dart';

final transactionDetailProvider = StateProvider<RcTransaction?>((ref) => null);

final routerProvider = Provider<GoRouter>((ref) {
  final isSignedIn = ref.read(isSignedInProvider);

  return GoRouter(
    initialLocation: isSignedIn ? '/' : '/sign-in',
    redirect: (context, state) {
      final signedIn = ref.read(isSignedInProvider);
      final isOnSignIn = state.matchedLocation == '/sign-in';

      if (!signedIn && !isOnSignIn) return '/sign-in';
      if (signedIn && isOnSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        name: 'sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'main',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/transaction-detail',
        name: 'transaction-detail',
        builder: (context, state) {
          final tx = state.extra as RcTransaction?;
          return TransactionDetailScreen(transaction: tx!);
        },
      ),
    ],
  );
});
