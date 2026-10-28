import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_display.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_names.dart';
import 'package:openrc/features/ask/ask_launch.dart';
import 'package:openrc/services/push/push_web_stub.dart'
    if (dart.library.js_interop) 'package:openrc/services/push/push_web.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('PushNotifications');

/// Firebase Cloud Messaging, started at launch when the build has Firebase
/// settings ([PushConfig]). Only messaging is used: no Firebase sign-in,
/// database or analytics.
abstract final class PushNotifications {
  static bool _started = false;
  static bool _supported = true;

  /// True once Firebase is up; Settings offers notifications only then.
  static bool get isAvailable => _started;

  /// False in browsers that can't receive pushes, such as Safari on iPhone
  /// outside a Home Screen app.
  static bool get isSupported => _supported;

  static Future<void> start() async {
    final options = PushConfig.firebaseOptions;
    if (options == null || _started) return;
    try {
      await Firebase.initializeApp(options: options);
      if (kIsWeb) {
        _supported = await FirebaseMessaging.instance.isSupported();
      } else {
        // iOS and macOS also show banners while the app is open. Android
        // doesn't, so the app reloads its list instead.
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              sound: true,
            );
      }
      _started = true;
    } catch (e, st) {
      _log.warning('Firebase setup failed', e, st);
    }
  }

  /// Notifications that arrive while the app is open.
  static Stream<RemoteMessage> get onMessage =>
      _started && !kIsWeb ? FirebaseMessaging.onMessage : const Stream.empty();

  /// Notifications tapped while the app was in the background.
  static Stream<RemoteMessage> get onMessageOpenedApp => _started && !kIsWeb
      ? FirebaseMessaging.onMessageOpenedApp
      : const Stream.empty();

  /// The notification tapped to launch the app, if any.
  static Future<RemoteMessage?> initialMessage() async {
    if (!_started || kIsWeb) return null;
    try {
      return await FirebaseMessaging.instance.getInitialMessage();
    } catch (e) {
      _log.fine('No initial message: $e');
      return null;
    }
  }

  /// On the web: notification clicks while a tab was open (the service
  /// worker, `web/push/sw.js`, passes them on).
  static Stream<AskLaunch> get webOpens =>
      _started && kIsWeb ? webPushOpens() : const Stream.empty();

  /// On the web: `?ask=` / `?transaction=` from a notification or bookmark.
  static AskLaunch? get webLaunch {
    if (!kIsWeb) return null;
    final launch = AskLaunch.fromQuery(Uri.base.queryParameters);
    return launch.isEmpty ? null : launch;
  }
}

/// What the app needs from Cloud Messaging; tests use a fake. Subscribing
/// puts this device on [secret]'s topic (see [PushChannel]).
abstract class PushMessaging {
  /// Asks to show notifications. True when the system allows them.
  Future<bool> requestPermission();

  Future<void> subscribe(String secret);

  Future<void> unsubscribe(String secret);
}

class FirebasePushMessaging implements PushMessaging {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> subscribe(String secret) async {
    await _waitForApns();
    await _messaging.subscribeToTopic(PushChannel.topicFor(secret));
  }

  @override
  Future<void> unsubscribe(String secret) async {
    await _waitForApns();
    await _messaging.unsubscribeFromTopic(PushChannel.topicFor(secret));
  }

  /// On Apple platforms FCM can't subscribe until APNs has given the device
  /// a token, which takes a moment after launch or a permission prompt.
  Future<void> _waitForApns() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    for (var attempt = 0; attempt < 20; attempt++) {
      if (await _messaging.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('APNs gave no device token');
  }
}

/// Browsers can't join FCM topics themselves, so the notifier does it: the
/// browser registers the push service worker (`web/push/sw.js`) and sends its
/// registration id with the device's secret.
class WebPushMessaging extends FirebasePushMessaging {
  WebPushMessaging([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: PushConfig.notifierUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;
  String? _registration;

  static const _serviceWorker = 'push/sw.js';

  @override
  Future<void> subscribe(String secret) => _send('/subscribe', secret);

  @override
  Future<void> unsubscribe(String secret) => _send('/unsubscribe', secret);

  Future<void> _send(String path, String secret) async {
    await _dio.post<void>(
      path,
      data: {'registration': await _register()},
      options: Options(
        headers: {'Authorization': PushChannel.authorizationHeader(secret)},
      ),
    );
  }

  /// This browser's Firebase installation id, or failing that its FCM token.
  Future<String> _register() async {
    final known = _registration;
    if (known != null) return known;
    final messaging = FirebaseMessaging.instance;
    final registered = messaging.onRegistered.first.timeout(
      const Duration(seconds: 20),
    );
    try {
      await messaging.register(
        vapidKey: PushConfig.vapidKey,
        serviceWorkerScriptPath: _serviceWorker,
      );
      return _registration = await registered;
    } catch (e) {
      registered.ignore();
      _log.fine('Registering failed, using a token instead: $e');
      // ignore: deprecated_member_use
      final token = await messaging.getToken(
        vapidKey: PushConfig.vapidKey,
        serviceWorkerScriptPath: _serviceWorker,
      );
      if (token == null) throw StateError('The browser gave no push token');
      return _registration = token;
    }
  }
}

/// Cloud Messaging for this build, or null when it has no notifications.
final pushMessagingProvider = Provider<PushMessaging?>((ref) {
  if (!PushNotifications.isAvailable || !PushNotifications.isSupported) {
    return null;
  }
  return kIsWeb ? WebPushMessaging() : FirebasePushMessaging();
});

class PushSettings {
  const PushSettings({
    this.enabled = false,
    this.secret,
    this.blocked = false,
    this.sandbox = false,
    this.knownProjects = const {},
    Set<PushKind>? kinds,
    this.projectKinds = const {},
    this.display = const PushDisplay(),
    this.names = const PushNames.empty(),
  }) : kinds = kinds ?? const {...PushKind.values};

  /// This device is subscribed to [secret]'s notifications.
  final bool enabled;

  /// What RevenueCat must send; see [PushChannel].
  final String? secret;

  /// The system refused permission the last time it was asked.
  final bool blocked;

  /// Webhooks also send sandbox (test) purchases, not only production ones.
  final bool sandbox;

  /// Projects the user has been offered, so Settings can point out new ones.
  final Set<String> knownProjects;

  /// What notifies, for every project without its own choice.
  final Set<PushKind> kinds;

  /// Projects with their own choice, by project id.
  final Map<String, Set<PushKind>> projectKinds;

  /// The currency and fees notifications show amounts with.
  final PushDisplay display;

  /// The names Settings gave to store products, so a push calls a product
  /// what the app calls it.
  final PushNames names;

  Set<PushKind> kindsFor(String projectId) => projectKinds[projectId] ?? kinds;

  PushSettings copyWith({
    bool? enabled,
    String? secret,
    bool? blocked,
    bool? sandbox,
    Set<String>? knownProjects,
    Set<PushKind>? kinds,
    Map<String, Set<PushKind>>? projectKinds,
    PushDisplay? display,
    PushNames? names,
  }) => PushSettings(
    enabled: enabled ?? this.enabled,
    secret: secret ?? this.secret,
    blocked: blocked ?? this.blocked,
    sandbox: sandbox ?? this.sandbox,
    knownProjects: knownProjects ?? this.knownProjects,
    kinds: kinds ?? this.kinds,
    projectKinds: projectKinds ?? this.projectKinds,
    display: display ?? this.display,
    names: names ?? this.names,
  );
}

enum PushEnableResult { enabled, blocked, failed }

final pushSettingsProvider =
    StateNotifierProvider<PushSettingsNotifier, PushSettings>((ref) {
      return PushSettingsNotifier(
        ref.watch(pushMessagingProvider),
        ref.watch(pushWebhooksProvider),
      );
    });

class PushSettingsNotifier extends StateNotifier<PushSettings> {
  PushSettingsNotifier(this._messaging, [this._webhooks])
    : super(const PushSettings()) {
    _hydrated = _messaging == null ? Future.value() : _hydrate();
  }

  final PushMessaging? _messaging;
  final PushWebhooks? _webhooks;
  late final Future<void> _hydrated;

  static const _enabledKey = 'push_enabled_v1';
  static const _sandboxKey = 'push_sandbox_v1';
  static const _knownProjectsKey = 'push_known_projects_v1';
  static const _kindsKey = 'push_kinds_v1';
  static const _projectKindsKey = 'push_project_kinds_v1';
  static const _displayKey = 'push_display_v1';
  static const _namesKey = 'push_names_v1';
  static const _secretKey = 'push_secret_v1';

  /// Secrets whose webhooks couldn't all be removed (offline, say), retried
  /// by [retryPendingRemovals].
  static const _pendingKey = 'push_pending_removals_v1';

  // Same options as the session token (see RcAuthService).
  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secret = PushChannel.parse(
        await _secureStorage.read(key: _secretKey) ?? '',
      );
      final enabled = (prefs.getBool(_enabledKey) ?? false) && secret != null;
      final savedKinds = PushKind.fromIds(
        prefs.getStringList(_kindsKey) ?? const [],
      );
      state = PushSettings(
        enabled: enabled,
        secret: secret,
        sandbox: prefs.getBool(_sandboxKey) ?? false,
        knownProjects: (prefs.getStringList(_knownProjectsKey) ?? []).toSet(),
        kinds: savedKinds.isEmpty ? null : savedKinds,
        projectKinds: _decodeProjectKinds(prefs.getString(_projectKindsKey)),
        display: _decodeDisplay(prefs.getString(_displayKey)),
        names: _decodeNames(prefs.getString(_namesKey)),
      );
      // A topic subscription belongs to the device's FCM registration, which
      // can change (a restore, a reinstall); subscribing on each launch keeps
      // it current. It is harmless when nothing changed.
      if (enabled) {
        unawaited(
          _messaging!
              .subscribe(secret)
              .catchError((Object e) => _log.warning('Resubscribing: $e')),
        );
      }
    } catch (e, st) {
      _log.warning('Restoring notifications failed', e, st);
    }
  }

  /// Asks for permission, then subscribes this device, making its secret on
  /// first use. Projects are added afterwards (see [PushProjectsNotifier]).
  Future<PushEnableResult> enable() async {
    final messaging = _messaging;
    if (messaging == null) return PushEnableResult.failed;
    await _hydrated;
    try {
      if (!await messaging.requestPermission()) {
        state = state.copyWith(blocked: true);
        return PushEnableResult.blocked;
      }
      final secret = state.secret ?? PushChannel.newSecret();
      await _secureStorage.write(key: _secretKey, value: secret);
      await messaging.subscribe(secret);
      await _saveBool(_enabledKey, true);
      // Its webhooks are about to be added again, not removed.
      await _updatePending((secrets) => secrets..remove(secret));
      state = state.copyWith(enabled: true, secret: secret, blocked: false);
      return PushEnableResult.enabled;
    } catch (e, st) {
      _log.warning('Turning on notifications failed', e, st);
      return PushEnableResult.failed;
    }
  }

  /// Stops notifications on this device and removes its webhooks from every
  /// project. The secret stays, so turning them back on finds the same
  /// webhooks if some couldn't be removed.
  Future<void> disable() async {
    await _hydrated;
    final PushSettings(:secret, :enabled) = state;
    state = state.copyWith(enabled: false);
    await _saveBool(_enabledKey, false);
    if (secret == null) return;
    if (enabled) {
      try {
        await _messaging?.unsubscribe(secret);
      } catch (e, st) {
        _log.warning('Unsubscribing failed', e, st);
      }
    }
    if (!await _removeWebhooks(secret)) {
      await _updatePending((secrets) => secrets..add(secret));
    }
  }

  /// Forgets notifications entirely, for logging out: removes this device's
  /// webhooks while the session can still do it, and whoever signs in next
  /// starts with a new secret.
  Future<void> clear() async {
    if (_messaging == null) return;
    await disable();
    try {
      await _secureStorage.delete(key: _secretKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sandboxKey);
      await prefs.remove(_knownProjectsKey);
      await prefs.remove(_kindsKey);
      await prefs.remove(_projectKindsKey);
      await prefs.remove(_displayKey);
      await prefs.remove(_namesKey);
    } catch (e, st) {
      _log.warning('Forgetting notification settings failed', e, st);
    }
    state = const PushSettings();
  }

  /// Sends sandbox purchases too, or production only, updating this device's
  /// webhooks. Returns false when some couldn't be updated.
  Future<bool> setSandbox(bool sandbox) async {
    await _hydrated;
    state = state.copyWith(sandbox: sandbox);
    await _saveBool(_sandboxKey, sandbox);
    return _updateWebhooks((_) => true);
  }

  /// What notifies in every project without its own choice. Updates those
  /// projects' webhooks; false when some couldn't be updated.
  Future<bool> setKinds(Set<PushKind> kinds) async {
    if (kinds.isEmpty) return false;
    await _hydrated;
    state = state.copyWith(kinds: {...kinds});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kindsKey, [for (final k in kinds) k.id]);
    } catch (e, st) {
      _log.warning('Saving notification kinds failed', e, st);
    }
    return _updateWebhooks(
      (projectId) => !state.projectKinds.containsKey(projectId),
    );
  }

  /// Gives [projectId] its own choice of kinds, or with null, the same as
  /// every other project. Updates its webhook; false when that failed.
  Future<bool> setProjectKinds(String projectId, Set<PushKind>? kinds) async {
    if (kinds != null && kinds.isEmpty) return false;
    await _hydrated;
    final projectKinds = {...state.projectKinds};
    kinds == null
        ? projectKinds.remove(projectId)
        : projectKinds[projectId] = {...kinds};
    state = state.copyWith(projectKinds: projectKinds);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _projectKindsKey,
        jsonEncode({
          for (final e in projectKinds.entries)
            e.key: [for (final k in e.value) k.id],
        }),
      );
    } catch (e, st) {
      _log.warning('Saving project notification kinds failed', e, st);
    }
    return _updateWebhooks((id) => id == projectId);
  }

  /// Follows Settings' display currency and store fees. Updates this
  /// device's webhooks when either changed; false when some couldn't be.
  Future<bool> setDisplay(PushDisplay display) async {
    await _hydrated;
    final changed = !state.display.sameAs(display);
    state = state.copyWith(display: display);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayKey, jsonEncode(display.toJson()));
    } catch (e, st) {
      _log.warning('Saving the notification currency failed', e, st);
    }
    return changed ? _updateWebhooks((_) => true) : true;
  }

  /// Follows Settings' product names, which the app sends with every label
  /// change. Updates this device's webhooks when they changed; false when
  /// some couldn't be.
  Future<bool> setNames(PushNames names) async {
    if (_messaging == null) return true;
    await _hydrated;
    if (names.sameAs(state.names)) return true;
    state = state.copyWith(names: names);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_namesKey, jsonEncode(names.toJson()));
    } catch (e, st) {
      _log.warning('Saving product names for notifications failed', e, st);
    }
    return _updateWebhooks((_) => true);
  }

  static PushDisplay _decodeDisplay(String? raw) {
    if (raw == null || raw.isEmpty) return const PushDisplay();
    try {
      return PushDisplay.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PushDisplay();
    }
  }

  static PushNames _decodeNames(String? raw) {
    if (raw == null || raw.isEmpty) return const PushNames.empty();
    try {
      return PushNames.fromJson(jsonDecode(raw));
    } catch (_) {
      return const PushNames.empty();
    }
  }

  /// Brings this device's webhooks in the projects [which] picks up to date
  /// with the current choices.
  Future<bool> _updateWebhooks(bool Function(String projectId) which) async {
    final webhooks = _webhooks;
    final secret = state.secret;
    if (webhooks == null || secret == null || !state.enabled) return true;
    var ok = true;
    try {
      final found = await webhooks.findAll(secret);
      await forEachLimited(found.entries.where((e) => which(e.key)), (
        entry,
      ) async {
        try {
          await webhooks.update(
            entry.key,
            entry.value.id,
            secret,
            sandbox: state.sandbox,
            kinds: state.kindsFor(entry.key),
            display: state.display,
            projectName: entry.value.projectName,
            names: state.names,
            projectIcon: entry.value.projectIcon,
          );
        } catch (e) {
          _log.warning('Updating a webhook failed: $e');
          ok = false;
        }
      });
    } catch (e) {
      _log.warning('Finding webhooks failed: $e');
      ok = false;
    }
    return ok;
  }

  static Map<String, Set<PushKind>> _decodeProjectKinds(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (e.value is List)
            e.key: PushKind.fromIds((e.value as List).whereType<String>()),
      }..removeWhere((_, kinds) => kinds.isEmpty);
    } catch (_) {
      return const {};
    }
  }

  /// Notes the projects the user has seen in the projects sheet.
  Future<void> rememberProjects(Set<String> projectIds) async {
    state = state.copyWith(knownProjects: projectIds);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_knownProjectsKey, projectIds.toList());
    } catch (e, st) {
      _log.warning('Saving projects failed', e, st);
    }
  }

  /// Tries again to remove webhooks that turning off or logging out left
  /// behind. Call while signed in.
  Future<void> retryPendingRemovals() async {
    if (_messaging == null) return;
    await _hydrated;
    final pending = await _readPending();
    if (pending.isEmpty) return;
    final done = <String>{};
    for (final secret in pending) {
      if (state.enabled && secret == state.secret) {
        done.add(secret);
      } else if (await _removeWebhooks(secret)) {
        done.add(secret);
      }
    }
    await _updatePending((secrets) => secrets..removeAll(done));
  }

  /// Removes [secret]'s webhooks from every project. False when any may be
  /// left.
  Future<bool> _removeWebhooks(String secret) async {
    final webhooks = _webhooks;
    if (webhooks == null) return true;
    var ok = true;
    try {
      final found = await webhooks.findAll(secret);
      await forEachLimited(found.entries, (entry) async {
        try {
          await webhooks.remove(entry.key, entry.value.id);
        } catch (e) {
          _log.warning('Removing a webhook failed: $e');
          ok = false;
        }
      });
    } catch (e) {
      _log.warning('Finding webhooks failed: $e');
      ok = false;
    }
    return ok;
  }

  Future<Set<String>> _readPending() async {
    try {
      final raw = await _secureStorage.read(key: _pendingKey);
      if (raw == null || raw.isEmpty) return {};
      return (jsonDecode(raw) as List<dynamic>).whereType<String>().toSet();
    } catch (e) {
      _log.warning('Reading pending removals failed: $e');
      return {};
    }
  }

  Future<void> _updatePending(
    Set<String> Function(Set<String> secrets) change,
  ) async {
    try {
      final secrets = change(await _readPending());
      if (secrets.isEmpty) {
        await _secureStorage.delete(key: _pendingKey);
      } else {
        await _secureStorage.write(
          key: _pendingKey,
          value: jsonEncode(secrets.toList()),
        );
      }
    } catch (e) {
      _log.warning('Saving pending removals failed: $e');
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e, st) {
      _log.warning('Saving a notification setting failed', e, st);
    }
  }
}
