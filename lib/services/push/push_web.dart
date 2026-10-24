import 'dart:async';
import 'dart:js_interop';

@JS('navigator.serviceWorker')
external _ServiceWorkerContainer? get _serviceWorker;

extension type _ServiceWorkerContainer(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

StreamController<String>? _opens;

/// Transaction ids of notifications clicked while a tab is open: the push
/// service worker (`web/push/sw.js`) focuses the tab and posts
/// `{type: 'openrc-push-open', transaction}`.
Stream<String> webPushOpens() {
  final existing = _opens;
  if (existing != null) return existing.stream;
  final opens = _opens = StreamController<String>.broadcast();
  _serviceWorker?.addEventListener(
    'message',
    ((_MessageEvent event) {
      final data = event.data.dartify();
      if (data is Map &&
          data['type'] == 'openrc-push-open' &&
          data['transaction'] is String) {
        opens.add(data['transaction'] as String);
      }
    }).toJS,
  );
  return opens.stream;
}
