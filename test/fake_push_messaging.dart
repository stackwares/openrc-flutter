import 'package:openrc/services/push/push_notifications.dart';

/// Cloud Messaging without a device: records topic changes.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.allowed = true});

  bool allowed;
  bool failSubscribe = false;
  final topics = <String>{};

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> subscribe(String topic) async {
    if (failSubscribe) throw StateError('offline');
    topics.add(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    topics.remove(topic);
  }
}
