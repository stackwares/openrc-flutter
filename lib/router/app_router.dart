import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:revenuecat/features/sign_in/sign_in_screen.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/router/initial_route_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final initialRoute = ref.read(initialRouteProvider);

  return GoRouter(
    initialLocation: initialRoute,
    redirect: (context, state) {
      final isSignedIn = ref.read(isSignedInProvider);
      final isOnSignIn = state.matchedLocation == '/sign-in';

      if (!isSignedIn && !isOnSignIn) return '/sign-in';
      if (isSignedIn && isOnSignIn) return '/transactions';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        name: 'sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/transactions',
        name: 'transactions',
        builder: (context, state) => const TransactionsScreen(),
      ),
    ],
  );
});
