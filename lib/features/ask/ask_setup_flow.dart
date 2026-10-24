import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/features/ask/widgets/agent_connection_form.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';

/// Connects an LLM the first time, or edits the connection after the
/// provider rejected the key.
class AskSetupFlow extends StatelessWidget {
  const AskSetupFlow({
    super.key,
    required this.settings,
    required this.onComplete,
    this.onCancel,
    this.bottomPadding = AppSpace.xxl,
  });

  final AgentSettings settings;
  final VoidCallback onComplete;

  /// Back to the thread without saving; null on first setup.
  final VoidCallback? onCancel;

  /// Room for the floating tab bar, or the keyboard gap.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = AppBreakpoints.centeringInset(
          constraints.maxWidth,
          maxWidth: 560,
        );
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter + inset,
            0,
            AppSpace.gutter + inset,
            bottomPadding + AppSpace.md,
          ),
          children: [
            AppStateMessage(
              icon: Icons.auto_awesome_rounded,
              title: 'agent.setup.title'.tr(),
              message: 'agent.setup.subtitle'.tr(),
              shrinkWrap: true,
            ),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: AgentConnectionForm(
                initial: settings,
                requireConsent: !settings.hasKey,
                onSaved: onComplete,
                onCancel: onCancel,
              ),
            ),
          ],
        );
      },
    );
  }
}
