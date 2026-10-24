import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/ask/widgets/agent_connection_form.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/widgets/adaptive_modal.dart';

class AgentSettingsSection extends ConsumerWidget {
  const AgentSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(agentSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroupLabel('settings.agent.title'.tr()),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRow(
                icon: Icons.auto_awesome_outlined,
                title: 'settings.agent.provider'.tr(),
                subtitle: settings.hasKey
                    ? settings.displayName
                    : settings.preset.nameKey.tr(),
                trailing: Text(settings.hasKey ? '••••' : '—'),
                onTap: () => showAgentSettingsSheet(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Provider, model and key, as a sheet on phones and a dialog elsewhere.
Future<void> showAgentSettingsSheet(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showAdaptiveSheet<void>(
    context: context,
    builder: (context) => const _AgentSettingsSheet(),
  );
}

class _AgentSettingsSheet extends ConsumerWidget {
  const _AgentSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(agentSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            settings.hasKey
                ? 'settings.agent.title'.tr()
                : 'agent.setup.title'.tr(),
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          AgentConnectionForm(
            initial: settings,
            requireConsent: !settings.hasKey,
            allowRemoveKey: settings.hasKey,
            onSaved: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
