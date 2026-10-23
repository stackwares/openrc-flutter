import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:skeletonizer/skeletonizer.dart';

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

final signInProvider =
    StateNotifierProvider<SignInNotifier, SignInStatus>((ref) {
  return SignInNotifier(ref);
});

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _otpSheetOpen = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$')
        .hasMatch(email);
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _errorMessage = null);
    UtilitiesService.hapticLight();

    try {
      await ref.read(signInProvider.notifier).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on DioException catch (e) {
      final rcError = ref.read(rcApiServiceProvider).parseError(e);
      final code = rcError?.code;
      if (code == AppConstants.rcErrorInvalidEmailOrPassword) {
        setState(() => _errorMessage = 'Invalid email or password.');
      } else if (code == AppConstants.rcErrorInvalidOtp) {
        setState(() => _errorMessage = 'Invalid verification code.');
      } else if (code == AppConstants.rcErrorTooManyRequests) {
        setState(() => _errorMessage = 'Too many requests. Please try again later.');
      } else {
        setState(() => _errorMessage = rcError?.message ?? 'Sign in failed.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'An unexpected error occurred.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(signInProvider);
    final isLoading = status == SignInStatus.loading;

    ref.listen<SignInStatus>(signInProvider, (prev, next) {
      if (next == SignInStatus.requires2Fa &&
          prev != SignInStatus.requires2Fa) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openOtpSheet();
        });
      } else if (next == SignInStatus.success) {
        context.go('/');
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 32),
                  _buildEmailField(isLoading),
                  const SizedBox(height: 16),
                  _buildPasswordField(isLoading),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorMessage(context),
                  ],
                  const SizedBox(height: 24),
                  _buildSignInButton(context, isLoading),
                  if (status == SignInStatus.requires2Fa) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: isLoading ? null : _openOtpSheet,
                      child: const Text('Enter verification code'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.account_balance_wallet_rounded,
          size: 64,
          color: context.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          AppConstants.appName,
          style: context.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to your RevenueCat account',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEmailField(bool isLoading) {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enabled: !isLoading,
      decoration: InputDecoration(
        labelText: 'Email',
        prefixIcon: const Icon(Icons.email_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Email is required';
        }
        if (!_isValidEmail(value.trim())) {
          return 'Enter a valid email address';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField(bool isLoading) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      enabled: !isLoading,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Password is required';
        }
        if (value.length < 8) {
          return 'Password must be at least 8 characters';
        }
        return null;
      },
    );
  }

  Future<void> _openOtpSheet() async {
    if (_otpSheetOpen || !mounted) return;
    _otpSheetOpen = true;
    final codeController = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          var submitting = false;
          String? sheetError;
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> submit() async {
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  setSheetState(() => sheetError = 'Enter the verification code.');
                  return;
                }
                setSheetState(() {
                  submitting = true;
                  sheetError = null;
                });
                try {
                  await ref.read(signInProvider.notifier).signIn(
                    email: _emailController.text.trim(),
                    password: _passwordController.text,
                    otpCode: code,
                  );
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                } on DioException catch (e) {
                  final rcError = ref.read(rcApiServiceProvider).parseError(e);
                  final message = switch (rcError?.code) {
                    AppConstants.rcErrorInvalidOtp => 'Invalid verification code.',
                    AppConstants.rcErrorTooManyRequests =>
                      'Too many requests. Please try again later.',
                    _ => rcError?.message ?? 'Sign in failed.',
                  };
                  if (context.mounted) {
                    setSheetState(() {
                      submitting = false;
                      sheetError = message;
                    });
                  }
                } catch (_) {
                  if (context.mounted) {
                    setSheetState(() {
                      submitting = false;
                      sheetError = 'An unexpected error occurred.';
                    });
                  }
                }
              }

              final bottom = MediaQuery.viewInsetsOf(context).bottom;
              return Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Verification code',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the code sent to ${_emailController.text.trim()}.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: codeController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      enabled: !submitting,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Code',
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        sheetError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: submitting ? null : submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      codeController.dispose();
      _otpSheetOpen = false;
    }
  }

  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: context.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInButton(BuildContext context, bool isLoading) {
    return FilledButton(
      onPressed: isLoading ? null : _handleSignIn,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Skeletonizer(
        enabled: isLoading,
        child: const Text('Sign In'),
      ),
    );
  }
}
