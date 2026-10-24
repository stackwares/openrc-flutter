import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/shell_insets.dart';
import 'package:openrc/features/ask/ask_notifier.dart';
import 'package:openrc/features/ask/ask_providers.dart';
import 'package:openrc/features/ask/ask_setup_flow.dart';
import 'package:openrc/features/ask/widgets/ask_composer.dart';
import 'package:openrc/features/ask/widgets/ask_turn_view.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/settings/widgets/agent_settings_section.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/services/agent/agent_relay_capability.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:openrc/widgets/shell_header.dart';

/// Phones close the keyboard after sending so the answer has the screen.
bool get _touchFirst =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

const _suggestions = [
  ('agent.suggestions.today', Icons.today_rounded),
  ('agent.suggestions.mrr', Icons.trending_up_rounded),
  ('agent.suggestions.countries', Icons.public_rounded),
  ('agent.suggestions.payout', Icons.payments_outlined),
];

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _composer = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  final _showJump = ValueNotifier(false);

  /// Lets a finished answer scroll its question to the top.
  final _turnKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _composer.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    _showJump.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _showJump.value = pos.maxScrollExtent - pos.pixels > 240;
  }

  bool get _nearEnd {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels < 160;
  }

  void _onTurnsChanged(List<AgentTurn>? previous, List<AgentTurn> next) {
    final before = previous ?? const <AgentTurn>[];
    final ids = {for (final t in next) t.id};
    _turnKeys.removeWhere((id, _) => !ids.contains(id));
    if (next.isEmpty) {
      _showJump.value = false;
      return;
    }
    if (before.isEmpty) {
      // The saved thread just loaded: open at the latest answer.
      _scrollToEnd(animate: false);
    } else if (next.length > before.length) {
      _scrollToEnd();
    } else if (before.last.id == next.last.id) {
      final was = before.last;
      final now = next.last;
      if (was.isRunning && !now.isRunning) {
        _revealTurn(now.id);
      } else if (now.blocks.length > was.blocks.length && _nearEnd) {
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      final duration = AppMotion.of(context, const Duration(milliseconds: 320));
      if (!animate || duration == Duration.zero) {
        pos.jumpTo(pos.maxScrollExtent);
        _settleAtEnd();
        return;
      }
      pos
          .animateTo(
            pos.maxScrollExtent,
            duration: duration,
            curve: AppMotion.curve,
          )
          .then((_) => _settleAtEnd());
    });
  }

  /// The list measures rows as it builds them, so the first jump can stop
  /// short of the real end.
  void _settleAtEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.pixels < pos.maxScrollExtent) pos.jumpTo(pos.maxScrollExtent);
    });
  }

  /// Brings a finished answer's question to the top, unless the user
  /// scrolled away to read something else meanwhile.
  void _revealTurn(String id) {
    if (!_nearEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _turnKeys[id]?.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: AppMotion.of(context, const Duration(milliseconds: 420)),
        curve: AppMotion.curve,
      );
    });
  }

  void _send() {
    final text = _composer.text.trim();
    final notifier = ref.read(askNotifierProvider.notifier);
    if (text.isEmpty || notifier.isRunning) return;
    _composer.clear();
    HapticFeedback.lightImpact();
    if (_touchFirst) _focusNode.unfocus();
    notifier.submit(text);
  }

  void _ask(String prompt) {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(askNotifierProvider.notifier).submit(prompt);
  }

  Future<void> _confirmClear() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'agent.clear'.tr(),
      content: (_) => Text('agent.clearMessage'.tr()),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('settings.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: dialogContext.appColors.negative,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('detail.clear'.tr()),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();
    await ref.read(askNotifierProvider.notifier).clearThread();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(askFocusTickProvider, (_, _) => _focusNode.requestFocus());
    ref.listen<String?>(askPrefillProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      _composer.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      ref.read(askPrefillProvider.notifier).state = null;
    });
    ref.listen<List<AgentTurn>>(askNotifierProvider, _onTurnsChanged);

    final settingsAsync = ref.watch(agentSettingsProvider);
    final settings = settingsAsync.value;
    final editing = ref.watch(askEditingKeyProvider);
    final turns = ref.watch(askNotifierProvider);
    final connected = (settings?.hasKey ?? false) && !editing;

    // The shell leaves the keyboard to this tab on phones: the floating tab
    // bar stays under it and the composer rides on top.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboard > 0
        ? AppSpace.xs
        : mainShellFloatingTabBarScrollPadding(context);

    final Widget body;
    if (settings == null) {
      body = settingsAsync.hasError
          ? AppStateMessage.error(
              message: 'agent.errors.generic'.tr(),
              onRetry: () => ref.invalidate(agentSettingsProvider),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (!connected) {
      void doneEditing() =>
          ref.read(askEditingKeyProvider.notifier).state = false;
      body = AskSetupFlow(
        settings: settings,
        bottomPadding: bottom,
        onComplete: doneEditing,
        onCancel: editing && settings.hasKey ? doneEditing : null,
      );
    } else {
      body = _thread(turns, bottom);
    }

    return Column(
      children: [
        ShellHeader(
          title: 'shell.tabs.ask'.tr(),
          subtitle: connected ? settings!.displayName : null,
          actions: [
            if (connected && turns.isNotEmpty)
              HeaderIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'agent.clear'.tr(),
                onPressed: _confirmClear,
              ),
            if (connected)
              HeaderIconButton(
                icon: Icons.tune_rounded,
                tooltip: 'settings.agent.provider'.tr(),
                onPressed: () => showAgentSettingsSheet(context),
              ),
            const SettingsAppBarAction(),
          ],
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _thread(List<AgentTurn> turns, double bottom) {
    final relayOk = ref.watch(relayLlmCapabilityProvider).value ?? true;
    final running = turns.any((t) => t.isRunning);
    final scheme = context.colorScheme;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            AppSpace.gutter + AppBreakpoints.centeringInset(constraints.maxWidth);
        return Column(
          children: [
            if (kIsWeb && !relayOk)
              Padding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, 0),
                child: _Notice(
                  icon: Icons.cloud_off_rounded,
                  text: 'agent.errors.relay'.tr(),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: turns.isEmpty
                        ? _EmptyThread(side: side, onAsk: _ask)
                        : ListView.builder(
                            controller: _scroll,
                            padding: EdgeInsets.fromLTRB(
                              side,
                              AppSpace.md,
                              side,
                              AppSpace.xl,
                            ),
                            itemCount: turns.length,
                            itemBuilder: (context, i) {
                              final turn = turns[i];
                              final last = i == turns.length - 1;
                              return Padding(
                                key: _turnKeys.putIfAbsent(
                                  turn.id,
                                  GlobalKey.new,
                                ),
                                padding: EdgeInsets.only(
                                  bottom: last ? 0 : AppSpace.xxl,
                                ),
                                child: AskTurnView(turn: turn, isLast: last),
                              );
                            },
                          ),
                  ),
                  // Content fades out above the composer instead of being cut.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: AppSpace.md,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              background.withValues(alpha: 0),
                              background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: AppSpace.sm,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _showJump,
                        builder: (context, show, _) => IgnorePointer(
                          ignoring: !show || turns.isEmpty,
                          child: AnimatedSlide(
                            offset: show ? Offset.zero : const Offset(0, 0.4),
                            duration: AppMotion.of(context, AppMotion.fast),
                            curve: AppMotion.curve,
                            child: AnimatedOpacity(
                              opacity: show && turns.isNotEmpty ? 1 : 0,
                              duration: AppMotion.of(context, AppMotion.fast),
                              child: IconButton.filledTonal(
                                tooltip: 'agent.latest'.tr(),
                                onPressed: _scrollToEnd,
                                icon: const Icon(Icons.arrow_downward_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor: scheme.surfaceContainerHigh,
                                  foregroundColor: scheme.onSurface,
                                  side: BorderSide(
                                    color: context.appColors.hairline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.xxs, side, bottom),
              child: AskComposer(
                controller: _composer,
                focusNode: _focusNode,
                running: running,
                onSend: _send,
                onStop: ref.read(askNotifierProvider.notifier).cancel,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// First open: what Ask is for, and questions to start with.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.side, required this.onAsk});

  final double side;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - AppSpace.md * 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary,
                        Color.lerp(scheme.primary, scheme.tertiary, 0.6)!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 30,
                    color: scheme.onPrimary,
                  ),
                ),
              ).appCardEntrance(),
              const SizedBox(height: AppSpace.lg),
              Text(
                'agent.empty.title'.tr(),
                textAlign: TextAlign.center,
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'agent.empty.subtitle'.tr(),
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              _Suggestions(onAsk: onAsk),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        final cards = [
          for (var i = 0; i < _suggestions.length; i++)
            _SuggestionCard(
              label: _suggestions[i].$1.tr(),
              icon: _suggestions[i].$2,
              onTap: () => onAsk(_suggestions[i].$1.tr()),
            ).appListItemEntrance(i + 1),
        ];
        return Column(
          children: [
            for (var row = 0; row < cards.length; row += columns)
              Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : AppSpace.xs),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = row; c < row + columns; c++) ...[
                        if (c > row) const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: c < cards.length
                              ? cards[c]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return AppCard(
      onTap: onTap,
      radius: AppRadius.tile,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(height: AppSpace.sm),
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: AppRadius.tileAll,
        border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.error),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(text, style: context.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
