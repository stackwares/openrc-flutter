import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/api_error_message.dart';
import 'package:revenuecat/features/sign_in/widgets/code_input.dart';
import 'package:revenuecat/features/sign_in/widgets/revenue_preview.dart';
import 'package:revenuecat/features/sign_in/widgets/sign_in_help_sheet.dart';
import 'package:revenuecat/models/rc_error_response.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/animated_reveal.dart';
import 'package:revenuecat/widgets/shake.dart';

enum SignInStatus { idle, loading, requires2Fa, success }

class SignInNotifier extends StateNotifier<SignInStatus> {
  final Ref _ref;

  SignInNotifier(this._ref) : super(SignInStatus.idle);

  Future<void> signIn({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    state = SignInStatus.loading;
    try {
      final auth = _ref.read(rcAuthServiceProvider);
      final response = await auth.signIn(
        email: email,
        password: password,
        otpCode: otpCode,
      );
      if (response?.authenticationToken != null) {
        state = SignInStatus.success;
      } else {
        state = SignInStatus.idle;
      }
    } on DioException catch (e) {
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      final code = rcError?.code;
      if (code == AppConstants.rcErrorOtpNeeded) {
        state = SignInStatus.requires2Fa;
      } else {
        state = SignInStatus.idle;
        rethrow;
      }
    } catch (_) {
      state = SignInStatus.idle;
      rethrow;
    }
  }

  void reset() => state = SignInStatus.idle;
}

final signInProvider = StateNotifierProvider<SignInNotifier, SignInStatus>((
  ref,
) {
  return SignInNotifier(ref);
});

/// What to tell the user after a failed sign-in or code check.
String signInErrorMessage(Object error, RcErrorResponse? rcError) {
  switch (rcError?.code) {
    case AppConstants.rcErrorInvalidEmailOrPassword:
      return 'That email and password don\u2019t match a RevenueCat account.';
    case AppConstants.rcErrorInvalidOtp:
      return 'That code didn\u2019t work. Codes change every 30 seconds, so '
          'use the newest one.';
    case AppConstants.rcErrorTooManyRequests:
      return 'Too many attempts. Wait a minute, then try again.';
  }
  return friendlyApiErrorMessage(error, serverMessage: rcError?.message);
}

enum _Step { credentials, code }

const int _kCodeLength = 6;

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _codeFocus = FocusNode();

  _Step _step = _Step.credentials;
  bool _obscurePassword = true;
  bool _submitted = false;
  String? _error;
  String? _codeError;
  int _errorTick = 0;
  int _codeErrorTick = 0;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
    // A new attempt clears the last code's error.
    _codeController.addListener(() {
      if (_codeError != null && _codeController.text.isNotEmpty) {
        setState(() => _codeError = null);
      }
    });
  }

  /// Fills in the last account's email; after an expired session, jumps
  /// straight to the password.
  Future<void> _prefillEmail() async {
    final email = await RcAuthService.lastSignInEmail();
    if (!mounted || email == null || _emailController.text.isNotEmpty) return;
    setState(() => _emailController.text = email);
    if (ref.read(signOutReasonProvider) == SignOutReason.sessionExpired) {
      _passwordFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$',
    ).hasMatch(email);
  }

  bool get _loading => ref.read(signInProvider) == SignInStatus.loading;

  void _fail(String message) {
    HapticFeedback.mediumImpact();
    setState(() {
      _error = message;
      _errorTick++;
    });
  }

  void _failCode(String message) {
    HapticFeedback.mediumImpact();
    _codeController.clear();
    setState(() {
      _codeError = message;
      _codeErrorTick++;
    });
    _codeFocus.requestFocus();
  }

  Future<void> _submitCredentials() async {
    if (_loading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _error = null);
    HapticFeedback.lightImpact();
    try {
      await ref
          .read(signInProvider.notifier)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on DioException catch (e) {
      if (!mounted) return;
      _fail(
        signInErrorMessage(e, ref.read(rcApiServiceProvider).parseError(e)),
      );
    } catch (e) {
      if (!mounted) return;
      _fail(signInErrorMessage(e, null));
    }
  }

  Future<void> _submitCode(String code) async {
    if (_loading || code.length != _kCodeLength) return;
    setState(() => _codeError = null);
    try {
      await ref
          .read(signInProvider.notifier)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            otpCode: code,
          );
      if (!mounted) return;
      // Asked for a code again: the one given wasn't accepted.
      if (ref.read(signInProvider) == SignInStatus.requires2Fa) {
        _failCode(
          signInErrorMessage(
            Exception(),
            const RcErrorResponse(code: AppConstants.rcErrorInvalidOtp),
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final rcError = ref.read(rcApiServiceProvider).parseError(e);
      if (rcError?.code == AppConstants.rcErrorInvalidEmailOrPassword) {
        _backToCredentials();
        _fail(signInErrorMessage(e, rcError));
        return;
      }
      _failCode(signInErrorMessage(e, rcError));
    } catch (e) {
      if (!mounted) return;
      _failCode(signInErrorMessage(e, null));
    }
  }

  void _goToCode() {
    _codeController.clear();
    setState(() {
      _step = _Step.code;
      _codeError = null;
      _error = null;
    });
    // The password field still holds focus during the switch, which would
    // swallow the code field's autofocus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == _Step.code) _codeFocus.requestFocus();
    });
  }

  void _backToCredentials() {
    ref.read(signInProvider.notifier).reset();
    _codeController.clear();
    setState(() {
      _step = _Step.credentials;
      _codeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(signInProvider);
    final loading = status == SignInStatus.loading;
    final sessionExpired =
        ref.watch(signOutReasonProvider) == SignOutReason.sessionExpired;

    // Success needs no navigation here: signing in flips isSignedInProvider
    // and RevenueCatApp swaps this screen for the main shell.
    ref.listen<SignInStatus>(signInProvider, (prev, next) {
      if (next == SignInStatus.requires2Fa && _step == _Step.credentials) {
        _goToCode();
      }
    });

    final step = AnimatedSwitcher(
      duration: AppMotion.of(context, const Duration(milliseconds: 320)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final forward = child.key == const ValueKey(_Step.code);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(forward ? 0.12 : -0.12, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _step == _Step.credentials
          ? KeyedSubtree(
              key: const ValueKey(_Step.credentials),
              child: _buildCredentials(context, loading, sessionExpired),
            )
          : KeyedSubtree(
              key: const ValueKey(_Step.code),
              child: _buildCode(context, loading),
            ),
    );

    return PopScope(
      canPop: _step == _Step.credentials,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToCredentials();
      },
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 760) {
                  return _buildWide(context, step);
                }
                return _buildPhone(context, step);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context, Widget step) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandRow(),
              // The pitch gives way to the form while typing.
              AnimatedReveal(
                visible: _step == _Step.credentials && !keyboardOpen,
                child: const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 4),
                  child: _Pitch(),
                ),
              ),
              const SizedBox(height: 24),
              step,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context, Widget step) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_BrandRow(), SizedBox(height: 28), _Pitch()],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: step,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentials(
    BuildContext context,
    bool loading,
    bool sessionExpired,
  ) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in',
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Use your RevenueCat dashboard email and password.',
              style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            AnimatedReveal(
              visible: sessionExpired,
              child: const Padding(
                padding: EdgeInsets.only(top: 16),
                child: _Notice(
                  icon: Icons.schedule_rounded,
                  message:
                      'Your session ended. Sign in again to pick up where '
                      'you left off.',
                ),
              ),
            ),
            AnimatedReveal(
              visible: _error != null,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Shake(
                  trigger: _errorTick,
                  child: _Notice(
                    icon: Icons.error_outline_rounded,
                    message: _error ?? '',
                    isError: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              readOnly: loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@company.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Enter your email';
                if (!_isValidEmail(v)) return 'That doesn’t look like an email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              readOnly: loading,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onFieldSubmitted: (_) => _submitCredentials(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              // Any length: RevenueCat decides what a valid password is.
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter your password' : null,
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Sign in',
              busyLabel: 'Signing in…',
              busy: loading,
              onPressed: _submitCredentials,
            ),
            const SizedBox(height: 6),
            // Wraps onto two lines with large text.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => openRevenueCatSignIn(context),
                  child: const Text('Forgot password?'),
                ),
                TextButton(
                  onPressed: () => showSignInHelpSheet(context),
                  child: const Text('Need help?'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your password goes straight to RevenueCat and is never '
                    'saved.',
                    style: tt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCode(BuildContext context, bool loading) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : _backToCredentials,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.shield_outlined, size: 32, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Enter your 2FA code',
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Open your authenticator app and enter the 6-digit code for '
          'RevenueCat.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Signing in as $email',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 24),
        Shake(
          trigger: _codeErrorTick,
          child: VerificationCodeInput(
            controller: _codeController,
            focusNode: _codeFocus,
            length: _kCodeLength,
            enabled: !loading,
            hasError: _codeError != null,
            onCompleted: _submitCode,
          ),
        ),
        AnimatedReveal(
          visible: _codeError != null,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _codeError ?? '',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: context.appColors.negative,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: _codeController,
          builder: (context, _) => _PrimaryButton(
            label: 'Verify',
            busyLabel: 'Verifying…',
            busy: loading,
            onPressed: _codeController.text.length == _kCodeLength
                ? () => _submitCode(_codeController.text)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => openRevenueCatSignIn(context),
          child: const Text(
            'Lost your authenticator? Use a recovery code on '
            'app.revenuecat.com',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// App mark and name.
class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.account_balance_wallet_rounded,
            size: 20,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          AppConstants.appName,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Headline, one line of what the app does, and the live example.
class _Pitch extends StatelessWidget {
  const _Pitch();

  @override
  Widget build(BuildContext context) {
    final tt = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Every sale, as it happens.',
          style: tt.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Revenue after store fees, upcoming payouts and sale alerts for '
          'your RevenueCat apps.',
          style: tt.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        const RevenuePreview(),
      ],
    ).appCardEntrance();
  }
}

/// Tinted message above the form: an info notice or an error.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? context.appColors.negative
        : context.colorScheme.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: isError ? color : context.colorScheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width filled button that shows a spinner while [busy].
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: busy
              ? scheme.primary.withValues(alpha: 0.7)
              : null,
          disabledForegroundColor: busy ? scheme.onPrimary : null,
        ),
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.fast),
          child: busy
              ? Row(
                  key: const ValueKey('busy'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(busyLabel),
                  ],
                )
              : Text(label, key: const ValueKey('idle')),
        ),
      ),
    );
  }
}
