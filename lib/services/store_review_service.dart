import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

/// Placeholder Microsoft Store Product ID until reserved in Partner Center.
const String kMicrosoftStoreProductId = '9PJMK832HJ1R';

/// Opens a store review prompt for the current platform.
///
/// On Windows, `in_app_review` is unsupported, so this opens the Microsoft
/// Store review deep link via `url_launcher`.
abstract final class StoreReviewService {
  static Uri microsoftStoreReviewUri([
    String productId = kMicrosoftStoreProductId,
  ]) => Uri.parse('ms-windows-store://review/?ProductId=$productId');

  static Future<bool> requestReview({
    Future<bool> Function(Uri uri)? launchUri,
    String microsoftStoreProductId = kMicrosoftStoreProductId,
  }) async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final uri = microsoftStoreReviewUri(microsoftStoreProductId);
      final launcher =
          launchUri ??
          (target) => launchUrl(target, mode: LaunchMode.externalApplication);
      try {
        return await launcher(uri);
      } catch (_) {
        return false;
      }
    }
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
