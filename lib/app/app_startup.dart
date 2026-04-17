import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/talker_service.dart';
import 'package:revenuecat/services/utilities_service.dart';

class AppStartup {
  final ProviderContainer container;

  AppStartup(this.container);

  Future<void> initialize() async {
    final talker = container.read(talkerProvider);
    talker.info('App startup initialization started');

    final themeMode = await container
        .read(utilitiesServiceProvider)
        .loadThemeMode();
    container.read(themeModeProvider.notifier).state = themeMode;
    final colorScheme = await container
        .read(utilitiesServiceProvider)
        .loadColorScheme();
    container.read(colorSchemeProvider.notifier).state = colorScheme;

    final hasSession = await container.read(rcAuthServiceProvider).restoreSession();
    talker.info('Session restored: $hasSession');

    talker.info('App startup initialization completed');
  }

  String get initialRoute {
    final isSignedIn = container.read(isSignedInProvider);
    return isSignedIn ? '/transactions' : '/sign-in';
  }
}
