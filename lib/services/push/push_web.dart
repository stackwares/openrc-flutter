import 'dart:async';
import 'dart:js_interop';

import 'package:openrc/features/ask/ask_launch.dart';

@JS('navigator.serviceWorker')
external _ServiceWorkerContainer? get _serviceWorker;

extension type _ServiceWorkerContainer(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

StreamController<AskLaunch>? _opens;

/// Notification clicks while a tab is open: the push service worker
/// (`web/push/sw.js`) focuses the tab and posts
/// `{type: 'openrc-push-open', transaction, ask}`.
Stream<AskLaunch> webPushOpens() {
  final existing = _opens;
  if (existing != null) return existing.stream;
  final opens = _opens = StreamController<AskLaunch>.broadcast();
  _serviceWorker?.addEventListener(
    'message',
    ((_MessageEvent event) {
      final data = event.data.dartify();
      if (data is! Map || data['type'] != 'openrc-push-open') return;
      final transaction = data['transaction'] is String
          ? data['transaction'] as String
          : null;
      opens.add(
        AskLaunch(
          transactionId: AskLaunch.boundedId(transaction),
          openAsk: data['ask'] == true,
        ),
      );
    }).toJS,
  );
  return opens.stream;
}
