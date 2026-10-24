import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:url_launcher/url_launcher.dart';

final Uri _kRevenueCatDashboardUrl = Uri.parse('https://app.revenuecat.com/');

/// How to add this device's webhook by hand, for a project OpenRC can't
/// change or for anyone who'd rather do it themselves.
Future<void> showPushSetupSheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    builder: (_) => const _PushSetupSheet(),
  );
}

class _PushSetupSheet extends ConsumerWidget {
  const _PushSetupSheet();

  static Future<void> _openDashboard(BuildContext context) async {
    final ok = await launchUrl(
      _kRevenueCatDashboardUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      context.showSnackBar(
        'signIn.couldNotOpenSite'.tr(namedArgs: {'url': 'app.revenuecat.com'}),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final secret = ref.watch(pushSettingsProvider).secret;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'notifications.manualSheet.title'.tr(),
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'notifications.manualSheet.body'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _Step(number: 1, text: 'notifications.manualSheet.step1'.tr()),
          _Step(number: 2, text: 'notifications.manualSheet.step2'.tr()),
          _CopyField(
            label: 'notifications.manualSheet.webhookUrl'.tr(),
            value: secret == null
                ? PushConfig.webhookUrl
                : PushWebhooks.urlFor(secret),
          ),
          if (secret != null) ...[
            const SizedBox(height: 8),
            _CopyField(
              label: 'notifications.manualSheet.authorizationHeader'.tr(),
              value: PushChannel.authorizationHeader(secret),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'notifications.manualSheet.secretHint'.tr(),
                style: tt.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _Step(number: 3, text: 'notifications.manualSheet.step3'.tr()),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _openDashboard(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text('notifications.manualSheet.openRevenueCat'.tr()),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text, style: tt.bodyMedium?.copyWith(height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A value to paste into RevenueCat, with a copy button that confirms in
/// place (a snack bar would sit behind the sheet).
class _CopyField extends StatefulWidget {
  const _CopyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  State<_CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<_CopyField> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    UtilitiesService.hapticLight();
    await UtilitiesService().copyToClipboard(widget.value);
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: tt.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _copied
                ? 'notifications.manualSheet.copied'.tr()
                : 'notifications.manualSheet.copy'.tr(
                    namedArgs: {'label': widget.label},
                  ),
            onPressed: _copy,
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 20,
              color: _copied ? context.appColors.positive : null,
            ),
          ),
        ],
      ),
    );
  }
}
