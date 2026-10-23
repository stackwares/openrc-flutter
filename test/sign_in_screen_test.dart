import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/features/sign_in/sign_in_screen.dart';
import 'package:revenuecat/features/sign_in/widgets/code_input.dart';
import 'package:revenuecat/models/rc_error_response.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

DioException _rcError(int code) {
  final options = RequestOptions(path: '/login');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 400,
      data: {'code': code, 'message': 'Server message'},
    ),
  );
}

/// Behaves like RevenueCat for an account with 2FA turned on.
class _FakeSignIn extends SignInNotifier {
  _FakeSignIn(super.ref);

  final calls = <({String email, String? code})>[];

  @override
  Future<void> signIn({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    calls.add((email: email, code: otpCode));
    state = SignInStatus.loading;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (password != 'test-password') {
      state = SignInStatus.idle;
      throw _rcError(AppConstants.rcErrorInvalidEmailOrPassword);
    }
    if (otpCode == null) {
      state = SignInStatus.requires2Fa;
      return;
    }
    if (otpCode != '123456') {
      state = SignInStatus.idle;
      throw _rcError(AppConstants.rcErrorInvalidOtp);
    }
    state = SignInStatus.success;
  }
}

void main() {
  late _FakeSignIn fake;

  Future<void> pump(
    WidgetTester tester, {
    SignOutReason? reason,
    Size size = const Size(430, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signInProvider.overrideWith((ref) => fake = _FakeSignIn(ref)),
          signOutReasonProvider.overrideWith((ref) => reason),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          // Still frames: no looping preview or blinking caret.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty fields are explained without calling RevenueCat', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(fake.calls, isEmpty);
  });

  testWidgets('a wrong password says so in plain words', (tester) async {
    await pump(tester);
    await tester.enterText(field('Email'), ' ada@example.com ');
    await tester.enterText(field('Password'), 'nope');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'That email and password don\u2019t match a RevenueCat account.',
      ),
      findsOneWidget,
    );
    expect(fake.calls.single.email, 'ada@example.com');
  });

  testWidgets('2FA: a wrong code is cleared, the right one signs in', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field('Email'), 'ada@example.com');
    await tester.enterText(field('Password'), 'test-password');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('Enter your 2FA code'), findsOneWidget);
    expect(find.text('Signing in as ada@example.com'), findsOneWidget);

    final codeField = find.descendant(
      of: find.byType(VerificationCodeInput),
      matching: find.byType(TextField),
    );
    // Six digits submit on their own, no tap needed.
    await tester.enterText(codeField, '000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('That code didn\u2019t work'), findsOneWidget);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);

    await tester.enterText(codeField, '123 456');
    await tester.pumpAndSettle();
    expect(fake.calls.last.code, '123456');
    expect(fake.state, SignInStatus.success);
  });

  testWidgets('back from the code step returns to the password', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field('Email'), 'ada@example.com');
    await tester.enterText(field('Password'), 'test-password');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your 2FA code'), findsNothing);
    expect(field('Password'), findsOneWidget);
  });

  testWidgets('after an expired session, the email is ready and it says why', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'last_sign_in_email': 'ada@example.com',
    });
    await pump(tester, reason: SignOutReason.sessionExpired);
    expect(find.textContaining('Your session ended'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('Email')).controller!.text,
      'ada@example.com',
    );
  });

  testWidgets('wide screens show the pitch beside the form', (tester) async {
    await pump(tester, size: const Size(1200, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Every sale, as it happens.'), findsOneWidget);
    expect(field('Email'), findsOneWidget);
  });

  test('error messages for the common failures', () {
    String msg(int code) =>
        signInErrorMessage(Exception(), RcErrorResponse(code: code));
    expect(
      msg(AppConstants.rcErrorTooManyRequests),
      'Too many attempts. Wait a minute, then try again.',
    );
    expect(msg(AppConstants.rcErrorInvalidOtp), contains('newest one'));
    expect(
      signInErrorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/login'),
          type: DioExceptionType.connectionError,
        ),
        null,
      ),
      contains('No internet connection'),
    );
  });
}
