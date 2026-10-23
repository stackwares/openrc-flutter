import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:url_launcher/url_launcher.dart';

/// RevenueCat's own sign-in page; it has the "Forgot password" link and
/// accepts 2FA recovery codes.
final Uri kRevenueCatSignInUrl = Uri.parse('https://app.revenuecat.com/login');

/// Opens RevenueCat's sign-in page in the browser.
Future<void> openRevenueCatSignIn(BuildContext context) async {
  final ok = await launchUrl(
    kRevenueCatSignInUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    context.showSnackBar(
      'signIn.couldNotOpenSite'.tr(namedArgs: {'url': 'app.revenuecat.com'}),
    );
  }
}

/// Answers for the usual reasons a sign-in fails.
Future<void> showSignInHelpSheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    builder: (_) => const _SignInHelpSheet(),
  );
}

class _SignInHelpSheet extends StatelessWidget {
  const _SignInHelpSheet();

  @override
  Widget build(BuildContext context) {
    final tt = context.textTheme;
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
            'signIn.troubleSigningIn'.tr(),
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _HelpItem(
            icon: Icons.key_rounded,
            title: 'signIn.helpForgotPasswordTitle'.tr(),
            body: 'signIn.helpForgotPasswordBody'.tr(),
          ),
          _HelpItem(
            icon: Icons.shield_outlined,
            title: 'signIn.twoFactorTitle'.tr(),
            body: 'signIn.helpTwoFactorBody'.tr(),
          ),
          _HelpItem(
            icon: Icons.domain_rounded,
            title: 'signIn.helpSsoTitle'.tr(),
            body: 'signIn.helpSsoBody'.tr(),
          ),
          _HelpItem(
            icon: Icons.lock_outline_rounded,
            title: 'signIn.helpPrivateTitle'.tr(),
            body: 'signIn.helpPrivateBody'.tr(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openRevenueCatSignIn(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              'signIn.openSite'.tr(namedArgs: {'url': 'app.revenuecat.com'}),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  const _HelpItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: scheme.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: tt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
