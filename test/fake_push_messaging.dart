import 'package:openrc/services/push/push_channel.dart';
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
  Future<void> subscribe(String secret) async {
    if (failSubscribe) throw StateError('offline');
    topics.add(PushChannel.topicFor(secret));
  }

  @override
  Future<void> unsubscribe(String secret) async {
    topics.remove(PushChannel.topicFor(secret));
  }
}
