/// When the signed-in app reloads its data without being asked.
///
/// Coming back after [staleAfter] or longer reloads it; a quick app switch
/// doesn't.
class AutoRefreshPolicy {
  AutoRefreshPolicy({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Time away after which the numbers on screen count as old.
  static const staleAfter = Duration(minutes: 5);

  /// Wait after a push before reloading, so a burst of webhooks (a renewal
  /// and its related events) reloads once, and RevenueCat's list, which can
  /// trail its webhooks by a few seconds, has the sale.
  static const pushSettle = Duration(seconds: 2);

  final DateTime Function() _clock;

  DateTime? _leftAt;

  /// The app went to the background (the first call counts).
  void left() => _leftAt ??= _clock();

  /// The app is back: whether it was away long enough to reload.
  bool returned() {
    final leftAt = _leftAt;
    _leftAt = null;
    return leftAt != null && _clock().difference(leftAt) >= staleAfter;
  }
}
