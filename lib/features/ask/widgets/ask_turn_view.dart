import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/ask/ask_notifier.dart';
import 'package:openrc/features/ask/ask_providers.dart';
import 'package:openrc/features/ask/ask_thread_store.dart';
import 'package:openrc/features/ask/widgets/agent_block_view.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_block_payload.dart';
import 'package:openrc/theme/app_tokens.dart';

/// One question and its answer: the question as a bubble on the right, the
/// answer full width below so charts and tables get the room.
class AskTurnView extends ConsumerWidget {
  const AskTurnView({super.key, required this.turn, required this.isLast});

  final AgentTurn turn;

  /// Only the latest turn offers retry and follow-ups, and animates in.
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(askNotifierProvider.notifier);
    final error = turn.errorKey;
    final Widget answer;
    if (turn.isRunning) {
      answer = _Working(statusKey: turn.statusLine!);
    } else if (error == kAgentStoppedKey) {
      answer = _Stopped(onRetry: isLast ? notifier.retryLast : null);
    } else if (error != null) {
      final keyProblem =
          error == 'agent.errors.badKey' || error == 'agent.errors.noKey';
      answer = _ErrorPanel(
        errorKey: error,
        onRetry: isLast ? notifier.retryLast : null,
        onEditKey: isLast && keyProblem
            ? () => ref.read(askEditingKeyProvider.notifier).state = true
            : null,
      );
    } else {
      answer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < turn.blocks.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.md),
              child: isLast
                  ? AgentBlockView(block: turn.blocks[i]).appCardEntrance(
                      delay: AppMotion.staggerDelay(i * 4),
                    )
                  : AgentBlockView(block: turn.blocks[i]),
            ),
          _AnswerFooter(turn: turn, isLast: isLast),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuestionBubble(text: turn.userPrompt),
        const SizedBox(height: AppSpace.md),
        AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.fast),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey(
              turn.isRunning ? 'running' : (error ?? 'answer'),
            ),
            child: answer,
          ),
        ),
      ],
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: dark ? 0.24 : 0.12),
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(20),
                topEnd: Radius.circular(20),
                bottomStart: Radius.circular(20),
                bottomEnd: Radius.circular(6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: 11,
              ),
              child: Text(
                text,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the model is doing right now, over a placeholder for the answer.
class _Working extends StatelessWidget {
  const _Working({required this.statusKey});

  final String statusKey;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget sparkle = Icon(
      Icons.auto_awesome_rounded,
      size: 18,
      color: scheme.primary,
    );
    Widget status = Text(
      statusKey.tr(),
      key: ValueKey(statusKey),
      style: context.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
    Widget placeholder = _AnswerPlaceholder(color: scheme.onSurface);
    if (!still) {
      sparkle = sparkle
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.8, end: 1.1, duration: 700.ms, curve: Curves.easeInOut)
          .fade(begin: 0.55, end: 1, duration: 700.ms);
      status = status.animate(onPlay: (c) => c.repeat()).shimmer(
            duration: 1600.ms,
            color: scheme.primary.withValues(alpha: 0.7),
          );
      placeholder = placeholder.animate(onPlay: (c) => c.repeat()).shimmer(
            duration: 1600.ms,
            color: scheme.surface.withValues(alpha: 0.6),
          );
    }
    return Semantics(
      liveRegion: true,
      label: statusKey.tr(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                sparkle,
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.fast),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: status,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            placeholder,
          ],
        ),
      ),
    );
  }
}

class _AnswerPlaceholder extends StatelessWidget {
  const _AnswerPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: 12,
            margin: const EdgeInsets.only(bottom: AppSpace.xs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(0.92), bar(0.74), bar(0.48)],
    );
  }
}

class _Stopped extends StatelessWidget {
  const _Stopped({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = context.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.stop_circle_outlined, size: 18, color: muted),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            kAgentStoppedKey.tr(),
            style: context.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('agent.retry'.tr()),
          ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.errorKey,
    required this.onRetry,
    required this.onEditKey,
  });

  final String errorKey;
  final VoidCallback? onRetry;
  final VoidCallback? onEditKey;

  IconData get _icon => switch (errorKey) {
        'agent.errors.badKey' || 'agent.errors.noKey' => Icons.key_off_rounded,
        'agent.errors.network' => Icons.wifi_off_rounded,
        'agent.errors.quota' => Icons.hourglass_bottom_rounded,
        'agent.errors.relay' ||
        'agent.errors.customWeb' =>
          Icons.cloud_off_rounded,
        _ => Icons.error_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final accent = scheme.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: AppRadius.tileAll,
          border: Border.all(color: accent.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, size: 20, color: accent),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    errorKey.tr(),
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (onRetry != null || onEditKey != null) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  if (onEditKey != null)
                    FilledButton.tonalIcon(
                      onPressed: onEditKey,
                      icon: const Icon(Icons.key_rounded, size: 18),
                      label: Text('agent.editKey'.tr()),
                    ),
                  if (onRetry != null && onEditKey != null)
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('agent.retry'.tr()),
                    )
                  else if (onRetry != null)
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('agent.retry'.tr()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Copy for text answers; follow-ups that fit what the answer showed.
class _AnswerFooter extends ConsumerWidget {
  const _AnswerFooter({required this.turn, required this.isLast});

  final AgentTurn turn;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = [
      for (final b in turn.blocks)
        if (b.type == AgentPresentationType.markdown)
          (b.payload['markdown'] as String? ?? '').trim(),
    ].where((t) => t.isNotEmpty).join('\n\n');
    final views = [
      for (final b in turn.blocks)
        AgentBlockPayload(b.payload).resolveView(b.type),
    ];
    final hasChart = views.contains(AgentPresentationType.lineChart);
    final hasTable = views.contains(AgentPresentationType.dataTable);
    final hasCards = views.contains(AgentPresentationType.metricCards);
    final notifier = ref.read(askNotifierProvider.notifier);

    final chips = <Widget>[
      if (isLast && hasChart && !hasTable)
        _FollowUp(
          icon: Icons.table_rows_outlined,
          label: 'agent.followUp.showTable'.tr(),
          onPressed: notifier.presentLastChartAsTable,
        ),
      if (isLast && hasChart)
        _FollowUp(
          icon: Icons.date_range_rounded,
          label: 'agent.followUp.last30'.tr(),
          onPressed: () => notifier.submit('agent.followUp.last30Prompt'.tr()),
        ),
      if (isLast && (hasChart || hasCards))
        _FollowUp(
          icon: Icons.insights_rounded,
          label: 'agent.followUp.openCharts'.tr(),
          onPressed: () =>
              ref.read(mainShellTabIndexProvider.notifier).state = 2,
        ),
    ];
    if (text.isEmpty && chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (text.isNotEmpty) _CopyButton(text: text),
          ...chips,
        ],
      ),
    );
  }
}

class _FollowUp extends StatelessWidget {
  const _FollowUp({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: context.colorScheme.primary),
      label: Text(label),
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return IconButton(
      tooltip: MaterialLocalizations.of(context).copyButtonLabel,
      onPressed: _copy,
      visualDensity: VisualDensity.compact,
      icon: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.content_copy_rounded,
          key: ValueKey(_copied),
          size: 18,
          color: _copied ? context.appColors.positive : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
