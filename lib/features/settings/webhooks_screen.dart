import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/models/rc_webhook.dart';
import 'package:revenuecat/services/push_registration_service.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/services/rc_api_service.dart';

/// Webhook URL registered in RevenueCat for this device’s Firebase anonymous user.
String expectedRelayWebhookUrl(String firebaseUid) {
  final relay = AppConstants.rcWebhookRelayUrl.trim();
  if (relay.isEmpty || firebaseUid.isEmpty) return '';
  final uri = Uri.parse(relay);
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'userId': firebaseUid,
  }).toString();
}

bool _webhookMatchesRelay(RcWebhook w, String firebaseUid) {
  final expected = expectedRelayWebhookUrl(firebaseUid);
  if (expected.isEmpty) return false;
  return w.url == expected;
}

class WebhooksScreen extends ConsumerStatefulWidget {
  const WebhooksScreen({super.key});

  @override
  ConsumerState<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends ConsumerState<WebhooksScreen> {
  final Map<String, _ProjectWebhookState> _state = {};
  var _loadingAll = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    final projectsAsync = ref.read(rcAccountProjectsProvider);
    final projects = projectsAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <RcProject>[],
    );

    if (user == null) {
      setState(() {
        _loadingAll = false;
        _error = 'Push account not ready. Restart the app.';
      });
      return;
    }

    if (AppConstants.rcWebhookRelayUrl.trim().isEmpty) {
      setState(() {
        _loadingAll = false;
        _error = null;
        _state.clear();
      });
      return;
    }

    setState(() {
      _loadingAll = true;
      _error = null;
    });

    final api = ref.read(rcApiServiceProvider);
    final next = <String, _ProjectWebhookState>{};

    for (final p in projects) {
      final id = p.id;
      if (id == null || id.isEmpty) continue;
      try {
        final list = await api.listWebhooks(id);
        RcWebhook? ours;
        for (final w in list) {
          if (_webhookMatchesRelay(w, user.uid)) {
            ours = w;
            break;
          }
        }
        next[id] = ours != null
            ? _ProjectWebhookState.active(ours)
            : const _ProjectWebhookState.inactive();
      } catch (e) {
        next[id] = _ProjectWebhookState.error(e);
      }
    }

    if (!mounted) return;
    setState(() {
      _state.clear();
      _state.addAll(next);
      _loadingAll = false;
    });
  }

  Future<void> _toggle(RcProject project) async {
    final id = project.id;
    if (id == null) return;
    final user = FirebaseAuth.instance.currentUser;
    final relay = AppConstants.rcWebhookRelayUrl.trim();
    if (user == null || relay.isEmpty) return;

    final api = ref.read(rcApiServiceProvider);
    final cur = _state[id] ?? const _ProjectWebhookState.inactive();

    setState(() {
      _state[id] = const _ProjectWebhookState.loading();
    });

    try {
      if (cur is _ActiveWebhook) {
        final wid = cur.webhook.id;
        if (wid == null || wid.isEmpty) {
          throw StateError('Webhook missing id');
        }
        await api.deleteWebhook(projectId: id, webhookId: wid);
        if (!mounted) return;
        setState(() {
          _state[id] = const _ProjectWebhookState.inactive();
        });
      } else {
        final name = _webhookDisplayName(user.uid);
        final url = expectedRelayWebhookUrl(user.uid);
        final created = await api.createWebhook(
          projectId: id,
          request: RcCreateWebhookRequest(
            name: name,
            url: url,
            environment: 'production',
          ),
        );
        if (!mounted) return;
        setState(() {
          _state[id] = _ProjectWebhookState.active(created);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state[id] = _ProjectWebhookState.error(e);
      });
    }
  }

  String _webhookDisplayName(String uid) {
    final short = uid.length > 8 ? uid.substring(0, 8) : uid;
    if (kIsWeb) return 'RevenueCat client / web / $short';
    return 'RevenueCat client / ${defaultTargetPlatform.name} / $short';
  }

  Future<void> _test(RcProject project, RcWebhook webhook) async {
    final id = project.id;
    final wid = webhook.id;
    if (id == null || wid == null) return;
    final api = ref.read(rcApiServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.testWebhook(projectId: id, webhookId: wid);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Test webhook sent')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Test failed: $e')),
      );
    }
  }

  Future<void> _resetPushUser(List<RcProject> projects) async {
    final user = FirebaseAuth.instance.currentUser;
    final relay = AppConstants.rcWebhookRelayUrl.trim();
    if (user == null || relay.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset notification ID?'),
        content: const Text(
          'Creates a new Firebase anonymous user and updates every active relay '
          'webhook URL to match. Use if you share this device or rotated secrets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final oldUid = user.uid;
    final newUser = await PushRegistrationService.instance.rotatePushUser();
    if (newUser == null || !mounted) return;

    final api = ref.read(rcApiServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    for (final p in projects) {
      final pid = p.id;
      if (pid == null) continue;
      try {
        final list = await api.listWebhooks(pid);
        for (final w in list) {
          if (_webhookMatchesRelay(w, oldUid) && w.id != null) {
            await api.updateWebhook(
              projectId: pid,
              webhookId: w.id!,
              request: RcUpdateWebhookRequest(
                name: _webhookDisplayName(newUser.uid),
                url: expectedRelayWebhookUrl(newUser.uid),
                environment: 'production',
              ),
            );
          }
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Update failed for ${p.name}: $e')),
        );
      }
    }

    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Notification ID reset')),
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(rcAccountProjectsProvider);
    final projects = projectsAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <RcProject>[],
    );
    final user = FirebaseAuth.instance.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final relay = AppConstants.rcWebhookRelayUrl.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase alerts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingAll ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + mainShellFloatingTabBarScrollPadding(context),
        ),
        children: [
          Text(
            'RevenueCat webhooks',
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            relay.isEmpty
                ? 'Build the app with RC_WEBHOOK_RELAY_URL pointing at your deployed '
                    'revenueCatWebhook function (see docs/WEBHOOK_FCM_SETUP.md).'
                : 'Toggle a webhook per project to send subscription events to your relay, '
                    'then FCM delivers a notification to this device.',
            style: tt.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (user != null && relay.isNotEmpty) ...[
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Device notification ID',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      user.uid,
                      style: tt.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _resetPushUser(projects),
                      child: const Text('Reset notification ID'),
                    ),
                  ],
                ),
              ),
            ).appCardEntrance(),
            const SizedBox(height: 16),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: tt.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          if (projectsAsync.isLoading || _loadingAll)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else
            for (var i = 0; i < projects.length; i++)
              _ProjectWebhookTile(
                project: projects[i],
                state: projects[i].id != null
                    ? (_state[projects[i].id!] ??
                          const _ProjectWebhookState.loading())
                    : const _ProjectWebhookState.inactive(),
                relayConfigured: relay.isNotEmpty,
                onToggle: () => _toggle(projects[i]),
                onTest: (w) => _test(projects[i], w),
              ).appCardEntrance(
                delay: Duration(milliseconds: 40 + i * 40),
              ),
        ],
      ),
    );
  }
}

sealed class _ProjectWebhookState {
  const _ProjectWebhookState();

  const factory _ProjectWebhookState.loading() = _LoadingWebhook;
  const factory _ProjectWebhookState.inactive() = _InactiveWebhook;
  const factory _ProjectWebhookState.active(RcWebhook webhook) = _ActiveWebhook;
  const factory _ProjectWebhookState.error(Object err) = _ErrorWebhook;
}

class _LoadingWebhook extends _ProjectWebhookState {
  const _LoadingWebhook();
}

class _InactiveWebhook extends _ProjectWebhookState {
  const _InactiveWebhook();
}

class _ActiveWebhook extends _ProjectWebhookState {
  const _ActiveWebhook(this.webhook);
  final RcWebhook webhook;
}

class _ErrorWebhook extends _ProjectWebhookState {
  const _ErrorWebhook(this.error);
  final Object error;
}

class _ProjectWebhookTile extends StatelessWidget {
  const _ProjectWebhookTile({
    required this.project,
    required this.state,
    required this.relayConfigured,
    required this.onToggle,
    required this.onTest,
  });

  final RcProject project;
  final _ProjectWebhookState state;
  final bool relayConfigured;
  final VoidCallback onToggle;
  final void Function(RcWebhook w) onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = project.name ?? project.id ?? 'Project';

    final Widget subtitle;
    final bool busy;
    switch (state) {
      case _LoadingWebhook():
        subtitle = Text(
          'Loading…',
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        );
        busy = true;
      case _InactiveWebhook():
        subtitle = Text(
          relayConfigured ? 'Webhook off' : 'Configure relay URL first',
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        );
        busy = false;
      case _ActiveWebhook(:final webhook):
        subtitle = Text(
          'Active · ${webhook.environment ?? 'production'}',
          style: tt.bodySmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        );
        busy = false;
      case _ErrorWebhook(:final error):
        subtitle = Text(
          '$error',
          style: tt.bodySmall?.copyWith(color: scheme.error),
        );
        busy = false;
    }

    final active = state is _ActiveWebhook;
    final wh = active ? (state as _ActiveWebhook).webhook : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: Text(
                name,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: subtitle,
              value: active,
              onChanged: busy || !relayConfigured
                  ? null
                  : (_) => onToggle(),
            ),
            if (wh != null && wh.id != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => onTest(wh),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Send test notification'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
