import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_webhook.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_display.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_api_service.dart';

final _log = Logger('PushWebhooks');

/// This device's webhooks in the account's RevenueCat projects, one per
/// project. RevenueCat masks a webhook's authorization header when it's read
/// back, so devices can't share a webhook: each adds its own. RevenueCat also
/// allows only one webhook per URL in a project, so each device's URL ends in
/// a tag of its secret, which is also how it finds its webhooks again (after
/// a reinstall that kept the secret, too).
class PushWebhooks {
  PushWebhooks(this._api);

  final RcApiService _api;

  /// Stable for a secret without revealing it.
  static String tagFor(String secret) =>
      PushChannel.topicFor(secret).substring('openrc-'.length).substring(0, 6);

  static String nameFor(String secret) {
    final device = kIsWeb
        ? 'Web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.iOS => 'iOS',
            TargetPlatform.android => 'Android',
            TargetPlatform.macOS => 'macOS',
            _ => 'device',
          };
    return 'OpenRC · $device · ${tagFor(secret)}';
  }

  /// This device's webhook URL. The notifier ignores the tag, and only sends
  /// the [kinds] named in `notify` (every kind when it's left out).
  static String urlFor(
    String secret, [
    Set<PushKind>? kinds,
    PushDisplay display = const PushDisplay(),
  ]) {
    final base = '${PushConfig.webhookUrl}/${tagFor(secret)}';
    final notify = kinds == null ? null : PushKind.queryFor(kinds);
    final query = {'notify': ?notify, ...display.query};
    if (query.isEmpty) return base;
    return '$base?${[for (final e in query.entries) '${e.key}=${e.value}'].join('&')}';
  }

  /// Matches whatever kinds the URL asks for, and webhooks from before URLs
  /// had tags, which shared the plain URL and had the tag only in their name.
  static bool isOwn(RcWebhook webhook, String secret) {
    final url = webhook.url?.split('?').first;
    return url == urlFor(secret) ||
        (url == PushConfig.webhookUrl &&
            (webhook.name?.endsWith(' · ${tagFor(secret)}') ?? false));
  }

  static RcWebhookInput inputFor(
    String secret, {
    required bool sandbox,
    required Set<PushKind> kinds,
    PushDisplay display = const PushDisplay(),
  }) => RcWebhookInput(
    name: nameFor(secret),
    url: urlFor(secret, kinds, display),
    authorizationHeader: PushChannel.authorizationHeader(secret),
    environment: sandbox ? null : 'production',
    eventTypes: PushKind.eventTypesFor(kinds),
  );

  Future<List<RcProject>> projects() => _api.projects();

  /// This device's webhook in [projectId], if it has one.
  Future<String?> find(String projectId, String secret) async {
    final webhooks = await _api.webhooks(projectId);
    return webhooks.firstWhereOrNull((w) => isOwn(w, secret))?.id;
  }

  /// Adds this device's webhook to [projectId], or brings an existing one
  /// up to date. Returns its id.
  Future<String> add(
    String projectId,
    String secret, {
    required bool sandbox,
    required Set<PushKind> kinds,
    PushDisplay display = const PushDisplay(),
  }) async {
    final input = inputFor(
      secret,
      sandbox: sandbox,
      kinds: kinds,
      display: display,
    );
    final existing = await find(projectId, secret);
    if (existing != null) {
      await _api.updateWebhook(projectId, existing, input);
      return existing;
    }
    final id = (await _api.createWebhook(projectId, input)).id;
    if (id == null) throw StateError('RevenueCat returned no webhook id');
    return id;
  }

  Future<void> update(
    String projectId,
    String webhookId,
    String secret, {
    required bool sandbox,
    required Set<PushKind> kinds,
    PushDisplay display = const PushDisplay(),
  }) => _api.updateWebhook(
    projectId,
    webhookId,
    inputFor(secret, sandbox: sandbox, kinds: kinds, display: display),
  );

  Future<void> remove(String projectId, String webhookId) =>
      _api.deleteWebhook(projectId, webhookId);

  Future<RcWebhookTestResult> test(String projectId, String webhookId) =>
      _api.testWebhook(projectId, webhookId);

  /// This device's webhook in each project that has one, by project id.
  Future<Map<String, String>> findAll(String secret) async {
    final found = <String, String>{};
    final ids = [
      for (final p in await projects())
        if (p.id != null) p.id!,
    ];
    await forEachLimited(ids, (projectId) async {
      final id = await find(projectId, secret);
      if (id != null) found[projectId] = id;
    });
    return found;
  }

  /// What RevenueCat said went wrong, for showing next to a project.
  String? errorMessage(Object error) => _api.parseError(error)?.message;
}

/// Runs [action] on every item, a few at a time, so a long project list
/// doesn't flood RevenueCat. Each action handles its own errors.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  Future<void> Function(T item) action, {
  int width = 4,
}) async {
  final queue = items.toList();
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      await action(queue.removeAt(0));
    }
  }

  await Future.wait([for (var i = 0; i < width; i++) worker()]);
}

/// RevenueCat for this device's webhooks, or null in builds without
/// notifications.
final pushWebhooksProvider = Provider<PushWebhooks?>((ref) {
  if (ref.watch(pushMessagingProvider) == null) return null;
  return PushWebhooks(ref.watch(rcApiServiceProvider));
});

class PushProject {
  const PushProject({
    required this.project,
    this.webhookId,
    this.busy = false,
    this.error,
  });

  final RcProject project;

  /// This device's webhook in the project, when it notifies.
  final String? webhookId;

  /// Being read or changed.
  final bool busy;

  /// Why the last read or change failed: RevenueCat's message, or empty
  /// when it gave none (offline, for one).
  final String? error;

  bool get connected => webhookId != null;

  String get id => project.id ?? '';
}

class PushProjectsState {
  const PushProjectsState({
    this.loading = true,
    this.failed = false,
    this.projects = const [],
  });

  final bool loading;

  /// The project list couldn't be loaded.
  final bool failed;

  final List<PushProject> projects;

  int get connectedCount => projects.where((p) => p.connected).length;
}

/// The projects sheet: which projects notify this device, and changing that.
final pushProjectsProvider =
    StateNotifierProvider.autoDispose<PushProjectsNotifier, PushProjectsState>(
      (ref) => PushProjectsNotifier(ref),
    );

class PushProjectsNotifier extends StateNotifier<PushProjectsState> {
  PushProjectsNotifier(this._ref) : super(const PushProjectsState()) {
    load();
  }

  final Ref _ref;

  PushWebhooks? get _webhooks => _ref.read(pushWebhooksProvider);

  String? get _secret => _ref.read(pushSettingsProvider).secret;

  Future<void> load() async {
    final webhooks = _webhooks;
    final secret = _secret;
    if (webhooks == null || secret == null) {
      state = const PushProjectsState(loading: false);
      return;
    }
    state = const PushProjectsState();
    try {
      final projects = await webhooks.projects();
      if (!mounted) return;
      state = PushProjectsState(
        projects: [
          for (final p in projects)
            if (p.id != null) PushProject(project: p, busy: true),
        ],
      );
      await forEachLimited(state.projects.map((p) => p.id), (id) async {
        try {
          final webhookId = await webhooks.find(id, secret);
          _set(
            id,
            (p) => PushProject(project: p.project, webhookId: webhookId),
          );
        } catch (e) {
          _log.warning('Reading webhooks failed: $e');
          _set(id, (p) => PushProject(project: p.project, error: _message(e)));
        }
      });
    } catch (e) {
      _log.warning('Loading projects failed: $e');
      if (mounted) {
        state = const PushProjectsState(loading: false, failed: true);
      }
      return;
    }
    if (mounted) {
      state = PushProjectsState(loading: false, projects: state.projects);
    }
  }

  /// Adds this device's webhook to [selected] projects and removes it from
  /// the rest. Returns how many projects failed.
  Future<int> apply(Set<String> selected) async {
    final webhooks = _webhooks;
    final secret = _secret;
    if (webhooks == null || secret == null) return 0;
    final settings = _ref.read(pushSettingsProvider);
    var failures = 0;
    final changes = state.projects.where(
      (p) => !p.busy && p.connected != selected.contains(p.id),
    );
    for (final p in changes) {
      _set(
        p.id,
        (p) =>
            PushProject(project: p.project, webhookId: p.webhookId, busy: true),
      );
    }
    await forEachLimited(changes.map((p) => p.id).toList(), (id) async {
      final current = state.projects.firstWhere((p) => p.id == id);
      try {
        if (selected.contains(id)) {
          final webhookId = await webhooks.add(
            id,
            secret,
            sandbox: settings.sandbox,
            kinds: settings.kindsFor(id),
            display: settings.display,
          );
          _set(
            id,
            (p) => PushProject(project: p.project, webhookId: webhookId),
          );
        } else {
          await webhooks.remove(id, current.webhookId!);
          _set(id, (p) => PushProject(project: p.project));
        }
      } catch (e) {
        _log.warning('Changing a webhook failed: $e');
        failures++;
        _set(
          id,
          (p) => PushProject(
            project: p.project,
            webhookId: p.webhookId,
            error: _message(e),
          ),
        );
      }
    });
    await _ref
        .read(pushSettingsProvider.notifier)
        .rememberProjects(state.projects.map((p) => p.id).toSet());
    return failures;
  }

  /// Turns one project on or off, leaving the others as they are. True when
  /// it worked.
  Future<bool> toggle(String projectId, bool on) async {
    final selected = {
      for (final p in state.projects)
        if (p.connected) p.id,
    };
    on ? selected.add(projectId) : selected.remove(projectId);
    return await apply(selected) == 0;
  }

  /// RevenueCat's test event through one of this device's webhooks. Null
  /// when no project notifies yet.
  Future<RcWebhookTestResult?> sendTest() async {
    final webhooks = _webhooks;
    final project = state.projects.firstWhereOrNull((p) => p.connected);
    if (webhooks == null || project == null) return null;
    return webhooks.test(project.id, project.webhookId!);
  }

  String _message(Object error) => _webhooks?.errorMessage(error) ?? '';

  void _set(String id, PushProject Function(PushProject) change) {
    if (!mounted) return;
    state = PushProjectsState(
      loading: state.loading,
      projects: [for (final p in state.projects) p.id == id ? change(p) : p],
    );
  }
}
