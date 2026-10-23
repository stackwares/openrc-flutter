/// posthog-js only exists on the web; native builds start PostHog from Dart.
bool initPosthogJs(String token, String host, {required bool optOut}) => true;
