import 'dart:js_interop';

@JS('posthog')
external _PostHogJs? get _posthog;

extension type _PostHogJs(JSObject _) implements JSObject {
  external void init(String token, JSAny options);
}

/// Starts posthog-js through the loader stub in `web/index.html`, configured
/// like the native SDKs: anonymous, no autocapture of clicks or page views,
/// no session replay. Returns false when the stub is missing.
bool initPosthogJs(String token, String host, {required bool optOut}) {
  final posthog = _posthog;
  if (posthog == null) return false;
  posthog.init(
    token,
    <String, Object>{
      'api_host': host,
      'person_profiles': 'never',
      'autocapture': false,
      'capture_pageview': false,
      'capture_pageleave': false,
      'capture_exceptions': true,
      'disable_session_recording': true,
      'disable_surveys': true,
      'advanced_disable_feature_flags': true,
      'opt_out_capturing_by_default': optOut,
    }.jsify()!,
  );
  return true;
}
