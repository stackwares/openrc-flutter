import 'package:openrc/features/ask/ask_launch.dart';

/// Only browsers get notification clicks from a service worker.
Stream<AskLaunch> webPushOpens() => const Stream.empty();
