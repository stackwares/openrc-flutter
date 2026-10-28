import 'dart:async';

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
import 'package:openrc/services/push/push_names.dart';
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
  /// the [kinds] named in `notify` (every kind when it's left out). The
  /// [projectName] lets the notifier name the project in the notification,
  /// [names] the products it names in the app, and [projectIcon] the app's
  /// picture, when it has one.
  static String urlFor(
    String secret, [
    Set<PushKind>? kinds,
    PushDisplay display = const PushDisplay(),
    String? projectName,
    PushNames names = const PushNames.empty(),
    String? projectIcon,
  ]) {
    final base = '${PushConfig.webhookUrl}/${tagFor(secret)}';
    final notify = kinds == null ? null : PushKind.queryFor(kinds);
    final name = projectName?.trim();
    final icon = iconParam(projectIcon);
    final query = {
      'notify': ?notify,
      ...display.query,
      ...names.query,
      if (name != null && name.isNotEmpty)
        'project': Uri.encodeQueryComponent(name),
      if (icon != null) iconKey: Uri.encodeQueryComponent(icon),
    };
    if (query.isEmpty) return base;
    return '$base?${[for (final e in query.entries) '${e.key}=${e.value}'].join('&')}';
  }

  /// The query parameter the notifier reads a picture from.
  static const iconKey = 'icon';

  /// Longest icon URL a webhook carries, matching what the notifier reads.
  static const maxIconLength = 1024;

  /// [iconUrl] when a push can show it, else null: only an https address
  /// with no spaces, so the notifier never hands FCM a link it can't use (it
  /// applies the same rule in `notifier/src/display.ts`).
  static String? iconParam(String? iconUrl) {
    final url = iconUrl?.trim();
    if (url == null || url.isEmpty || url.length > maxIconLength) return null;
    if (_iconWhitespace.hasMatch(url)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return url;
  }

  static final _iconWhitespace = RegExp(r'[\s"\x27<>\\]');

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
    String? projectName,
    PushNames names = const PushNames.empty(),
    String? projectIcon,
  }) => RcWebhookInput(
    name: nameFor(secret),
    url: urlFor(secret, kinds, display, projectName, names, projectIcon),
    authorizationHeader: PushChannel.authorizationHeader(secret),
    environment: sandbox ? null : 'production',
    eventTypes: PushKind.eventTypesFor(kinds),
  );

  Future<List<RcProject>> projects() => _api.projects();

  /// This device's webhook in [projectId], if it has one.
  Future<RcWebhook?> webhookFor(String projectId, String secret) async {
    final webhooks = await _api.webhooks(projectId);
    return webhooks.firstWhereOrNull((w) => isOwn(w, secret));
  }

  /// This device's webhook in [projectId], if it has one.
  Future<String?> find(String projectId, String secret) async =>
      (await webhookFor(projectId, secret))?.id;

  /// Adds this device's webhook to [projectId], or brings an existing one
  /// up to date. Returns its id.
  Future<String> add(
    String projectId,
    String secret, {
    required bool sandbox,
    required Set<PushKind> kinds,
    PushDisplay display = const PushDisplay(),
    String? projectName,
    PushNames names = const PushNames.empty(),
    String? projectIcon,
  }) async {
    final input = inputFor(
      secret,
      sandbox: sandbox,
      kinds: kinds,
      display: display,
      projectName: projectName,
      names: names,
      projectIcon: projectIcon,
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
    String? projectName,
    PushNames names = const PushNames.empty(),
    String? projectIcon,
  }) => _api.updateWebhook(
    projectId,
    webhookId,
    inputFor(
      secret,
      sandbox: sandbox,
      kinds: kinds,
      display: display,
      projectName: projectName,
      names: names,
      projectIcon: projectIcon,
    ),
  );

  Future<void> remove(String projectId, String webhookId) =>
      _api.deleteWebhook(projectId, webhookId);

  /// Every webhook in [projectId], marked with who made it.
  Future<List<ProjectWebhook>> allFor(
    String projectId,
    String secret,
  ) async {
    final hooks = await _api.webhooks(projectId);
    final seen = <String>{};
    return [
      for (final hook in hooks)
        if (hook.id == null || seen.add(hook.id!))
          ProjectWebhook(hook, ownerOf(hook, secret)),
    ];
  }

  /// Deletes [ids], counting one RevenueCat no longer has as done. Returns
  /// the ids it couldn't delete.
  Future<List<String>> removeMany(
    String projectId,
    Iterable<String> ids,
  ) async {
    final failed = <String>[];
    await forEachLimited(ids, (id) async {
      try {
        await remove(projectId, id);
      } catch (e) {
        if (!_api.isNotFound(e)) failed.add(id);
      }
    });
    return failed;
  }

  /// Deletes every webhook that isn't [secret]'s, across [projects], leaving
  /// this device's own in place. [onProgress] hears how many went so far.
  Future<SweepResult> sweep(
    String secret, {
    required List<RcProject> projects,
    void Function(int deleted)? onProgress,
  }) async {
    var deleted = 0;
    var failed = 0;
    await forEachLimited(projects, (project) async {
      final id = project.id;
      if (id == null) return;
      final List<ProjectWebhook> hooks;
      try {
        hooks = await allFor(id, secret);
      } catch (e) {
        _log.warning('Reading a project\'s webhooks failed: $e');
        failed++;
        return;
      }
      final others = [
        for (final hook in hooks)
          if (hook.owner != WebhookOwner.thisDevice && hook.id.isNotEmpty)
            hook.id,
      ];
      if (others.isEmpty) return;
      final kept = await removeMany(id, others);
      deleted += others.length - kept.length;
      failed += kept.length;
      onProgress?.call(deleted);
    });
    return SweepResult(deleted: deleted, failed: failed);
  }

  /// Who created [webhook], as far as its URL tells.
  static WebhookOwner ownerOf(RcWebhook webhook, String secret) {
    if (isOwn(webhook, secret)) return WebhookOwner.thisDevice;
    return openRcTagOf(webhook) == null
        ? WebhookOwner.foreign
        : WebhookOwner.openRcOther;
  }

  /// The device tag in an OpenRC notifier URL, or null when it isn't one.
  ///
  /// Matched by path rather than by [PushConfig.webhookUrl]'s host, so
  /// webhooks made against an earlier notifier deployment still count as
  /// OpenRC's: those are the orphans a swept project needs to lose.
  static String? openRcTagOf(RcWebhook webhook) {
    final match = _notifierPath.firstMatch(webhook.path ?? '');
    return match?.group(1);
  }

  static final _notifierPath = RegExp(r'/revenuecat/([A-Za-z0-9_-]{1,64})$');

  Future<RcWebhookTestResult> test(String projectId, String webhookId) =>
      _api.testWebhook(projectId, webhookId);

  /// This device's webhook in each project that has one, by project id.
  Future<Map<String, DeviceWebhook>> findAll(String secret) async {
    final found = <String, DeviceWebhook>{};
    final all = await projects();
    final byId = {
      for (final p in all)
        if (p.id != null) p.id!: p,
    };
    await forEachLimited(byId.keys, (projectId) async {
      final id = await find(projectId, secret);
      final project = byId[projectId];
      if (id != null) {
        found[projectId] = DeviceWebhook(
          id,
          project?.name,
          project?.iconUrl,
        );
      }
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

/// This device's webhook in one RevenueCat project.
class DeviceWebhook {
  const DeviceWebhook(this.id, this.projectName, [this.projectIcon]);

  final String id;
  final String? projectName;

  /// The project's icon in RevenueCat, which its pushes show.
  final String? projectIcon;
}

/// What a sweep across projects did.
class SweepResult {
  const SweepResult({required this.deleted, required this.failed});

  final int deleted;

  /// Webhooks RevenueCat refused to delete.
  final int failed;

  bool get ok => failed == 0;
}

/// Who created a webhook, as far as its URL tells.
enum WebhookOwner {
  /// Made by this device, for the secret it holds.
  thisDevice,

  /// Made by OpenRC, by a device whose secret this one doesn't have: an
  /// earlier install, or a changed notifier deployment.
  openRcOther,

  /// Anything else: another service, or a URL added by hand.
  foreign,
}

/// One webhook in a project, ready to show.
class ProjectWebhook {
  const ProjectWebhook(this.webhook, this.owner);

  final RcWebhook webhook;
  final WebhookOwner owner;

  String get id => webhook.id ?? '';

  /// The webhook's name, or where it points when it has none.
  String get title {
    final name = webhook.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return webhook.host ?? webhook.url ?? '—';
  }

  int get eventTypeCount => webhook.eventTypes?.length ?? 0;
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
    firstLoad = load();
  }

  final Ref _ref;

  /// The sheet's first read; [load] runs again only when asked.
  late final Future<void> firstLoad;

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
      final settings = _ref.read(pushSettingsProvider);
      final names = {
        for (final p in projects)
          if (p.id != null) p.id!: p.name?.trim(),
      };
      final icons = {
        for (final p in projects)
          if (p.id != null) p.id!: p.iconUrl,
      };
      await forEachLimited(state.projects.map((p) => p.id), (id) async {
        try {
          final webhook = await webhooks.webhookFor(id, secret);
          final webhookId = webhook?.id;
          _set(
            id,
            (p) => PushProject(project: p.project, webhookId: webhookId),
          );
          // Webhooks from before URLs named their project, carried product
          // names or showed the project's icon pick them up here, so existing
          // devices read right without changing a setting. Names the settings
          // haven't loaded yet are left alone rather than removed.
          final name = names[id];
          final icon = icons[id];
          final query = Uri.tryParse(webhook?.url ?? '')?.queryParameters;
          final wanted = settings.names.encoded;
          final stale =
              (name != null &&
                  name.isNotEmpty &&
                  query?['project'] != name) ||
              (wanted != null && query?[PushNames.key] != wanted) ||
              (query?[PushWebhooks.iconKey]) != PushWebhooks.iconParam(icon);
          if (webhookId != null && stale) {
            try {
              await webhooks.update(
                id,
                webhookId,
                secret,
                sandbox: settings.sandbox,
                kinds: settings.kindsFor(id),
                display: settings.display,
                projectName: name,
                names: settings.names,
                projectIcon: icon,
              );
            } catch (e) {
              _log.warning('Refreshing a webhook failed: $e');
            }
          }
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
            projectName: current.project.name,
            // Every setting that changes what a notification reads: a param
            // left out here is a push that falls back to the store's own
            // product id, or to US dollars, until something else refreshes
            // the webhook.
            names: settings.names,
            projectIcon: current.project.iconUrl,
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

/// One project's webhooks, for the manager sheet.
final projectWebhooksProvider = StateNotifierProvider.autoDispose
    .family<ProjectWebhooksNotifier, ProjectWebhooksState, String>(
      (ref, projectId) => ProjectWebhooksNotifier(ref, projectId),
    );

class ProjectWebhooksState {
  const ProjectWebhooksState({
    this.loading = true,
    this.failed = false,
    this.error,
    this.webhooks = const [],
    this.deleting = const {},
    this.deleteFailed = false,
  });

  final bool loading;

  /// The list couldn't be read.
  final bool failed;

  /// Why the read failed: RevenueCat's message, or null when it gave none.
  final String? error;

  final List<ProjectWebhook> webhooks;

  /// Ids being deleted.
  final Set<String> deleting;

  /// The last deletion failed.
  final bool deleteFailed;

  List<ProjectWebhook> ownedBy(WebhookOwner owner) => [
    for (final w in webhooks)
      if (w.owner == owner) w,
  ];

  ProjectWebhooksState copyWith({
    bool? loading,
    bool? failed,
    String? error,
    List<ProjectWebhook>? webhooks,
    Set<String>? deleting,
    bool? deleteFailed,
  }) => ProjectWebhooksState(
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    error: error ?? this.error,
    webhooks: webhooks ?? this.webhooks,
    deleting: deleting ?? this.deleting,
    deleteFailed: deleteFailed ?? this.deleteFailed,
  );
}

/// Reading and deleting one project's webhooks.
class ProjectWebhooksNotifier extends StateNotifier<ProjectWebhooksState> {
  ProjectWebhooksNotifier(this._ref, this.projectId)
    : super(const ProjectWebhooksState()) {
    firstLoad = load();
  }

  final Ref _ref;
  final String projectId;

  /// The sheet's first read; [load] runs again only when asked.
  late final Future<void> firstLoad;

  PushWebhooks? get _webhooks => _ref.read(pushWebhooksProvider);

  String? get _secret => _ref.read(pushSettingsProvider).secret;

  Future<void> load() async {
    final webhooks = _webhooks;
    final secret = _secret;
    if (webhooks == null || secret == null) {
      state = const ProjectWebhooksState(loading: false);
      return;
    }
    state = state.copyWith(loading: true, failed: false, deleteFailed: false);
    try {
      final found = await webhooks.allFor(projectId, secret);
      if (!mounted) return;
      state = ProjectWebhooksState(webhooks: found, loading: false);
    } catch (e) {
      _log.warning('Reading a project\'s webhooks failed: $e');
      if (mounted) {
        state = state.copyWith(
          loading: false,
          failed: true,
          error: _webhooks?.errorMessage(e),
        );
      }
    }
  }

  /// Deletes one webhook. True when it went.
  Future<bool> delete(String id) async {
    final owner = state.webhooks
        .firstWhereOrNull((w) => w.id == id)
        ?.owner;
    return _delete([id], owner);
  }

  /// Deletes every webhook [owner] made. True when all of them went.
  Future<bool> deleteOwnedBy(WebhookOwner owner) async {
    final ids = [for (final w in state.ownedBy(owner)) w.id];
    return _delete(ids, owner);
  }

  Future<bool> _delete(List<String> ids, WebhookOwner? owner) async {
    final webhooks = _webhooks;
    if (webhooks == null || ids.isEmpty) return false;
    state = state.copyWith(
      deleting: {...state.deleting, ...ids},
      deleteFailed: false,
    );
    List<String> failed;
    try {
      failed = await webhooks.removeMany(projectId, ids);
    } catch (e) {
      _log.warning('Deleting a webhook failed: $e');
      failed = ids;
    }
    if (!mounted) return failed.isEmpty;
    final gone = {for (final id in ids) if (!failed.contains(id)) id};
    state = state.copyWith(
      webhooks: [
        for (final w in state.webhooks)
          if (!gone.contains(w.id)) w,
      ],
      deleting: {...state.deleting}..removeAll(ids),
      deleteFailed: failed.isNotEmpty,
    );
    // The notification list reads webhooks live, so losing this device's
    // must make it read them again.
    if (gone.isNotEmpty && owner == WebhookOwner.thisDevice) {
      unawaited(_ref.read(pushProjectsProvider.notifier).load());
    }
    return failed.isEmpty;
  }
}

/// Every project's webhooks, for deleting the ones this device didn't make.
final webhookSweepProvider = StateNotifierProvider.autoDispose<
  WebhookSweepNotifier,
  WebhookSweepState
>((ref) => WebhookSweepNotifier(ref));

/// One project, counted for the sweep.
class SweptProject {
  const SweptProject({
    required this.project,
    required this.mine,
    required this.others,
  });

  final RcProject project;

  /// Webhooks this device made, which a sweep keeps.
  final int mine;

  /// Webhooks a sweep deletes.
  final int others;

  String get id => project.id ?? '';
  String get name => project.name ?? id;
}

class WebhookSweepState {
  const WebhookSweepState({
    this.loading = true,
    this.failed = false,
    this.error,
    this.projects = const [],
    this.running = false,
    this.result,
    this.progress = 0,
  });

  final bool loading;

  /// The projects' webhooks couldn't be read.
  final bool failed;

  /// Why the read failed: RevenueCat's message, or null when it gave none.
  final String? error;

  final List<SweptProject> projects;

  /// A sweep is running; [progress] is how many webhooks it has deleted.
  final bool running;
  final int progress;

  /// What the last sweep did.
  final SweepResult? result;

  int get mine =>
      projects.fold(0, (total, project) => total + project.mine);

  int get others =>
      projects.fold(0, (total, project) => total + project.others);
}

/// Counts what a sweep would delete, then deletes it.
class WebhookSweepNotifier extends StateNotifier<WebhookSweepState> {
  WebhookSweepNotifier(this._ref) : super(const WebhookSweepState()) {
    firstLoad = load();
  }

  final Ref _ref;

  /// The sheet's first read; [load] runs again only when asked.
  late final Future<void> firstLoad;

  PushWebhooks? get _webhooks => _ref.read(pushWebhooksProvider);

  String? get _secret => _ref.read(pushSettingsProvider).secret;

  Future<void> load() async {
    final webhooks = _webhooks;
    final secret = _secret;
    if (webhooks == null || secret == null) {
      state = const WebhookSweepState(loading: false);
      return;
    }
    // What the last sweep did, and the counts it left, stay on screen while
    // they're read again, so a refresh can't erase them.
    final result = state.result;
    final known = state.projects;
    state = WebhookSweepState(
      loading: known.isEmpty,
      projects: known,
      result: result,
    );
    final List<RcProject> projects;
    try {
      projects = await webhooks.projects();
    } catch (e) {
      _log.warning('Loading projects for a sweep failed: $e');
      if (mounted) {
        state = WebhookSweepState(
          loading: false,
          failed: true,
          error: webhooks.errorMessage(e),
          projects: known,
          result: result,
        );
      }
      return;
    }
    final counted = <SweptProject>[];
    await forEachLimited(projects, (project) async {
      final id = project.id;
      if (id == null) return;
      try {
        final hooks = await webhooks.allFor(id, secret);
        counted.add(
          SweptProject(
            project: project,
            mine: hooks
                .where((h) => h.owner == WebhookOwner.thisDevice)
                .length,
            others: hooks
                .where((h) => h.owner != WebhookOwner.thisDevice)
                .length,
          ),
        );
      } catch (e) {
        _log.warning('Counting a project\'s webhooks failed: $e');
      }
    });
    if (!mounted) return;
    counted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = WebhookSweepState(
      loading: false,
      projects: counted,
      result: result,
    );
  }

  /// Deletes every webhook that isn't this device's, in every project.
  Future<void> sweep() async {
    final webhooks = _webhooks;
    final secret = _secret;
    if (webhooks == null || secret == null || state.running) return;
    state = WebhookSweepState(
      loading: false,
      projects: state.projects,
      running: true,
    );
    SweepResult result;
    try {
      result = await webhooks.sweep(
        secret,
        projects: [for (final p in state.projects) p.project],
        onProgress: (deleted) {
          if (mounted) state = _running(deleted);
        },
      );
    } catch (e) {
      _log.warning('Sweeping webhooks failed: $e');
      result = const SweepResult(deleted: 0, failed: 1);
    }
    if (!mounted) return;
    state = WebhookSweepState(
      loading: false,
      projects: state.projects,
      result: result,
    );
    // Counts are stale once webhooks are gone, and the project list reads
    // which of them notify this device.
    unawaited(load());
    unawaited(_ref.read(pushProjectsProvider.notifier).load());
  }

  WebhookSweepState _running(int progress) => WebhookSweepState(
    loading: false,
    projects: state.projects,
    running: true,
    progress: progress,
  );
}
