import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/features/sign_in/widgets/code_input.dart';
import 'package:openrc/features/sign_in/widgets/sign_in_help_sheet.dart';
import 'package:openrc/models/rc_error_response.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:openrc/widgets/shake.dart';

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
      return 'signIn.invalidCredentials'.tr();
    case AppConstants.rcErrorInvalidOtp:
      return 'signIn.invalidCode'.tr();
    case AppConstants.rcErrorTooManyRequests:
      return 'signIn.tooManyAttempts'.tr();
  }
  return friendlyApiErrorMessage(error, serverMessage: rcError?.message);
}

const int _kCodeLength = 6;

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _codeSheetOpen = false;
  bool _obscurePassword = true;
  String? _error;
  int _errorTick = 0;

  @override
  void initState() {
    super.initState();
    Telemetry.screen('Sign in');
    _prefillEmail();
    // The field card lights up while either field has focus.
    _emailFocus.addListener(_onFieldFocus);
    _passwordFocus.addListener(_onFieldFocus);
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

  void _onFieldFocus() => setState(() {});

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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

  /// What's missing before RevenueCat is asked, or null when ready.
  String? _credentialsProblem() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty && password.isEmpty) {
      return 'signIn.enterEmailAndPassword'.tr();
    }
    if (email.isEmpty) return 'signIn.enterEmail'.tr();
    if (!_isValidEmail(email)) return 'signIn.invalidEmail'.tr();
    // Any length: RevenueCat decides what a valid password is.
    if (password.isEmpty) return 'signIn.enterPassword'.tr();
    return null;
  }

  Future<void> _submitCredentials() async {
    if (_loading) return;
    final problem = _credentialsProblem();
    if (problem != null) {
      _fail(problem);
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

  /// The two-factor code: a bottom sheet on phones, a dialog on larger windows.
  Future<void> _showCodeSheet() async {
    if (_codeSheetOpen) return;
    _codeSheetOpen = true;
    setState(() => _error = null);
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _TwoFactorSheet(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        onBadCredentials: _fail,
      ),
    );
    _codeSheetOpen = false;
    // Closed without finishing: ready for another attempt.
    if (mounted && ref.read(signInProvider) != SignInStatus.success) {
      ref.read(signInProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(signInProvider);
    final loading = status == SignInStatus.loading;
    final sessionExpired =
        ref.watch(signOutReasonProvider) == SignOutReason.sessionExpired;

    // Success needs no navigation here: signing in flips isSignedInProvider
    // and OpenRcApp swaps this screen for the main shell.
    ref.listen<SignInStatus>(signInProvider, (prev, next) {
      if (next == SignInStatus.requires2Fa) _showCodeSheet();
    });

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          // One centered column on every screen, like the system's own
          // account sign-in.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _buildCredentials(context, loading, sessionExpired),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCredentials(
    BuildContext context,
    bool loading,
    bool sessionExpired,
  ) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _AppIconMark()),
          const SizedBox(height: 24),
          Text(
            'signIn.title'.tr(namedArgs: {'app': AppConstants.appName}),
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sessionExpired
                ? 'signIn.sessionEnded'.tr()
                : 'signIn.useRevenueCatAccount'.tr(),
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          Shake(
            trigger: _errorTick,
            child: _FieldGroup(
              focused: _emailFocus.hasFocus || _passwordFocus.hasFocus,
              hasError: _error != null,
              children: [
                TextField(
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
                  onChanged: (_) => _clearError(),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  decoration: _fieldDecoration('signIn.emailHint'.tr()),
                ),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  readOnly: loading,
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) => _clearError(),
                  onSubmitted: (_) => _submitCredentials(),
                  decoration: _fieldDecoration(
                    'signIn.passwordHint'.tr(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      color: scheme.onSurfaceVariant,
                      tooltip: _obscurePassword
                          ? 'signIn.showPassword'.tr()
                          : 'signIn.hidePassword'.tr(),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedReveal(
            visible: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? '',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(
                    color: context.appColors.negative,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: 'signIn.signInButton'.tr(),
            busyLabel: 'signIn.signingIn'.tr(),
            busy: loading,
            onPressed: _submitCredentials,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => openRevenueCatSignIn(context),
              child: Text('signIn.forgotPassword'.tr()),
            ),
          ),
          const SizedBox(height: 32),
          const _PrivacyFootnote(),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String placeholder, {Widget? suffix}) {
    return InputDecoration(
      hintText: placeholder,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: EdgeInsets.fromLTRB(16, 16, suffix == null ? 16 : 4, 16),
      suffixIcon: suffix,
    );
  }
}

/// The app icon, raised slightly off the page like on a home screen.
class _AppIconMark extends StatelessWidget {
  const _AppIconMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const AppLogo(size: 76),
    );
  }
}

/// Email and password in one inset card with a hairline between them.
class _FieldGroup extends StatelessWidget {
  const _FieldGroup({
    required this.children,
    required this.focused,
    required this.hasError,
  });

  final List<Widget> children;
  final bool focused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final colors = context.appColors;
    final borderColor = hasError
        ? colors.negative
        : focused
        ? scheme.primary
        : colors.hairline;
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.fast),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: borderColor,
          width: focused || hasError ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, color: colors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Where the password goes, and where to get help.
class _PrivacyFootnote extends StatelessWidget {
  const _PrivacyFootnote();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Column(
      children: [
        Icon(Icons.lock_rounded, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(height: 6),
        Text(
          'signIn.passwordPrivacy'.tr(),
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        TextButton(
          onPressed: () => showSignInHelpSheet(context),
          style: TextButton.styleFrom(textStyle: tt.bodySmall),
          child: Text('signIn.troubleSigningIn'.tr()),
        ),
      ],
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
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
          textStyle: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
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

/// The two-factor code step, shown in an adaptive sheet over the sign-in form.
class _TwoFactorSheet extends ConsumerStatefulWidget {
  const _TwoFactorSheet({
    required this.email,
    required this.password,
    required this.onBadCredentials,
  });

  final String email;
  final String password;

  /// Called after the sheet closes when RevenueCat rejects the email or
  /// password instead of the code.
  final void Function(String message) onBadCredentials;

  @override
  ConsumerState<_TwoFactorSheet> createState() => _TwoFactorSheetState();
}

class _TwoFactorSheetState extends ConsumerState<_TwoFactorSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  int _errorTick = 0;

  @override
  void initState() {
    super.initState();
    // A new attempt clears the last code's error.
    _controller.addListener(() {
      if (_error != null && _controller.text.isNotEmpty) {
        setState(() => _error = null);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _loading => ref.read(signInProvider) == SignInStatus.loading;

  void _fail(String message) {
    HapticFeedback.mediumImpact();
    _controller.clear();
    setState(() {
      _error = message;
      _errorTick++;
    });
    _focus.requestFocus();
  }

  Future<void> _submit(String code) async {
    if (_loading || code.length != _kCodeLength) return;
    setState(() => _error = null);
    try {
      await ref
          .read(signInProvider.notifier)
          .signIn(
            email: widget.email,
            password: widget.password,
            otpCode: code,
          );
      if (!mounted) return;
      final status = ref.read(signInProvider);
      if (status == SignInStatus.success) {
        Navigator.of(context).pop();
      } else if (status == SignInStatus.requires2Fa) {
        // Asked for a code again: the one given wasn't accepted.
        _fail(
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
        final message = signInErrorMessage(e, rcError);
        Navigator.of(context).pop();
        widget.onBadCredentials(message);
        return;
      }
      _fail(signInErrorMessage(e, rcError));
    } catch (e) {
      if (!mounted) return;
      _fail(signInErrorMessage(e, null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final loading = ref.watch(signInProvider) == SignInStatus.loading;
    // A dialog already makes room for the keyboard; a sheet doesn't.
    final keyboard = context.windowSize == WindowSize.compact
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + keyboard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 34,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'signIn.twoFactorTitle'.tr(),
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'signIn.enterCodePrompt'.tr(),
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (widget.email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.email,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Shake(
            trigger: _errorTick,
            child: VerificationCodeInput(
              controller: _controller,
              focusNode: _focus,
              length: _kCodeLength,
              enabled: !loading,
              hasError: _error != null,
              onCompleted: _submit,
            ),
          ),
          AnimatedReveal(
            visible: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? '',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(
                    color: context.appColors.negative,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _PrimaryButton(
              label: 'signIn.verify'.tr(),
              busyLabel: 'signIn.verifying'.tr(),
              busy: loading,
              onPressed: _controller.text.length == _kCodeLength
                  ? () => _submit(_controller.text)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => openRevenueCatSignIn(context),
              child: Text(
                'signIn.lostAuthenticator'.tr(),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
