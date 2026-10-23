import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_tokens.dart';
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
    context.showSnackBar('Couldn’t open app.revenuecat.com');
  }
}

/// Answers for the usual reasons a sign-in fails.
Future<void> showSignInHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
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
            'Trouble signing in?',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          const _HelpItem(
            icon: Icons.key_rounded,
            title: 'Forgot your password',
            body:
                'Reset it with “Forgot password” on RevenueCat’s '
                'sign-in page, then come back and sign in here.',
          ),
          const _HelpItem(
            icon: Icons.shield_outlined,
            title: 'Two-factor authentication',
            body:
                'After your password, you’ll be asked for the 6-digit '
                'code from your authenticator app. Lost access to it? Sign in '
                'on RevenueCat’s website with one of your recovery codes.',
          ),
          const _HelpItem(
            icon: Icons.domain_rounded,
            title: 'Single sign-on',
            body:
                'If your organization requires single sign-on, sign in '
                'through it on RevenueCat’s website. This app signs in '
                'with an email and password only.',
          ),
          const _HelpItem(
            icon: Icons.lock_outline_rounded,
            title: 'Your password stays private',
            body:
                'It goes straight to RevenueCat and is never saved. Your '
                'session is kept in this device’s secure storage.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openRevenueCatSignIn(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open app.revenuecat.com'),
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
