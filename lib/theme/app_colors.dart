import 'package:flutter/material.dart';

/// Colors that carry meaning: change direction, transaction types and stores.
///
/// Surfaces stay neutral; these are used for small marks only (dots, status
/// text, deltas, split bars). Read them with `context.appColors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.positive,
    required this.negative,
    required this.neutralDelta,
    required this.warning,
    required this.hairline,
    required this.trial,
    required this.conversion,
    required this.renewal,
    required this.purchase,
    required this.oneTimePurchase,
    required this.refund,
    required this.cancelled,
    required this.apple,
    required this.google,
    required this.web,
    required this.otherStore,
  });

  /// Better than before (more revenue, more trials).
  final Color positive;

  /// Worse than before, refunds, failures.
  final Color negative;

  /// No change.
  final Color neutralDelta;
  final Color warning;

  /// Card borders and dividers.
  final Color hairline;

  final Color trial;
  final Color conversion;
  final Color renewal;
  final Color purchase;
  final Color oneTimePurchase;
  final Color refund;
  final Color cancelled;

  final Color apple;
  final Color google;
  final Color web;
  final Color otherStore;

  static const dark = AppColors(
    positive: Color(0xFF5FD49A),
    negative: Color(0xFFFF7A7A),
    neutralDelta: Color(0xFF9095A0),
    warning: Color(0xFFF0A84A),
    hairline: Color(0xFF25272B),
    trial: Color(0xFFF0A84A),
    conversion: Color(0xFF3CC6B4),
    renewal: Color(0xFF6CCB6C),
    purchase: Color(0xFF6E9BFF),
    oneTimePurchase: Color(0xFFA98BFF),
    refund: Color(0xFFFF7A7A),
    cancelled: Color(0xFFE8875A),
    apple: Color(0xFF4A9BFF),
    google: Color(0xFF3DDC84),
    web: Color(0xFFC49BFF),
    otherStore: Color(0xFF6B7079),
  );

  static const light = AppColors(
    positive: Color(0xFF1E8E5A),
    negative: Color(0xFFD93B3B),
    neutralDelta: Color(0xFF6B7079),
    warning: Color(0xFFB86E00),
    hairline: Color(0xFFE3E5E8),
    trial: Color(0xFFC77700),
    conversion: Color(0xFF0E8C7E),
    renewal: Color(0xFF2E8B3A),
    purchase: Color(0xFF2F6FE4),
    oneTimePurchase: Color(0xFF7A4FE0),
    refund: Color(0xFFD93B3B),
    cancelled: Color(0xFFD0602A),
    apple: Color(0xFF007AFF),
    google: Color(0xFF1FA463),
    web: Color(0xFF8E5BD8),
    otherStore: Color(0xFF8A8F98),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// For code that only has a [ColorScheme] (no [BuildContext]).
  static AppColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AppColors copyWith({
    Color? positive,
    Color? negative,
    Color? neutralDelta,
    Color? warning,
    Color? hairline,
    Color? trial,
    Color? conversion,
    Color? renewal,
    Color? purchase,
    Color? oneTimePurchase,
    Color? refund,
    Color? cancelled,
    Color? apple,
    Color? google,
    Color? web,
    Color? otherStore,
  }) {
    return AppColors(
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      neutralDelta: neutralDelta ?? this.neutralDelta,
      warning: warning ?? this.warning,
      hairline: hairline ?? this.hairline,
      trial: trial ?? this.trial,
      conversion: conversion ?? this.conversion,
      renewal: renewal ?? this.renewal,
      purchase: purchase ?? this.purchase,
      oneTimePurchase: oneTimePurchase ?? this.oneTimePurchase,
      refund: refund ?? this.refund,
      cancelled: cancelled ?? this.cancelled,
      apple: apple ?? this.apple,
      google: google ?? this.google,
      web: web ?? this.web,
      otherStore: otherStore ?? this.otherStore,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      positive: l(positive, other.positive),
      negative: l(negative, other.negative),
      neutralDelta: l(neutralDelta, other.neutralDelta),
      warning: l(warning, other.warning),
      hairline: l(hairline, other.hairline),
      trial: l(trial, other.trial),
      conversion: l(conversion, other.conversion),
      renewal: l(renewal, other.renewal),
      purchase: l(purchase, other.purchase),
      oneTimePurchase: l(oneTimePurchase, other.oneTimePurchase),
      refund: l(refund, other.refund),
      cancelled: l(cancelled, other.cancelled),
      apple: l(apple, other.apple),
      google: l(google, other.google),
      web: l(web, other.web),
      otherStore: l(otherStore, other.otherStore),
    );
  }
}
