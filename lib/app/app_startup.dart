import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/utilities_service.dart';

final _log = Logger('AppStartup');

class AppStartup {
  final ProviderContainer container;

  AppStartup(this.container);

  Future<void> initialize() async {
    _log.info('App startup initialization started');

    final themeMode = await container
        .read(utilitiesServiceProvider)
        .loadThemeMode();
    container.read(themeModeProvider.notifier).state = themeMode;
    final colorScheme = await container
        .read(utilitiesServiceProvider)
        .loadColorScheme();
    container.read(colorSchemeProvider.notifier).state = colorScheme;
    container.read(appLanguageProvider.notifier).state = await container
        .read(utilitiesServiceProvider)
        .loadLanguage();

    final hasSession = await container.read(rcAuthServiceProvider).restoreSession();
    _log.info('Session restored: $hasSession');

    _log.info('App startup initialization completed');
  }
}
