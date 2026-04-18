import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Leading image or fallback to [fallback] inside a tinted rounded square.
class TransactionLeadingAvatar extends StatelessWidget {
  final String? imageUrl;
  final Widget fallback;
  final Color tintColor;
  final double size;
  final double borderRadius;

  const TransactionLeadingAvatar({
    super.key,
    required this.imageUrl,
    required this.fallback,
    required this.tintColor,
    this.size = 40,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tintColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: tintColor.withValues(alpha: 0.15),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, progress) => Center(
            child: SizedBox(
              width: size * 0.35,
              height: size * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tintColor,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: tintColor.withValues(alpha: 0.15),
            alignment: Alignment.center,
            child: fallback,
          ),
        ),
      ),
    );
  }
}
