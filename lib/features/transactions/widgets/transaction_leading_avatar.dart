import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Leading image or fallback to [fallback] inside a tinted rounded square.
class TransactionLeadingAvatar extends StatelessWidget {
  final String? imageUrl;
  final Widget fallback;
  final Color tintColor;
  final double size;
  final double borderRadius;

  /// When set, shown in the bottom-right corner on a small elevated chip.
  final IconData? platformIcon;

  final Color? platformIconColor;

  const TransactionLeadingAvatar({
    super.key,
    required this.imageUrl,
    required this.fallback,
    required this.tintColor,
    this.size = 40,
    this.borderRadius = 10,
    this.platformIcon,
    this.platformIconColor,
  });

  Widget _buildAvatarBody(BuildContext context) {
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

    final cacheDim = (size * 2.5).round().clamp(60, 240);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: tintColor.withValues(alpha: 0.15),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: cacheDim,
          memCacheHeight: cacheDim,
          maxWidthDiskCache: cacheDim,
          maxHeightDiskCache: cacheDim,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, progress) => Skeletonizer.zone(
            child: Bone.square(
              size: size,
              borderRadius: BorderRadius.circular(borderRadius),
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

  @override
  Widget build(BuildContext context) {
    final body = _buildAvatarBody(context);
    final icon = platformIcon;
    if (icon == null) return body;

    final scheme = Theme.of(context).colorScheme;
    final tint = platformIconColor ?? scheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: -3,
            bottom: -3,
            child: Material(
              elevation: 1.5,
              shadowColor: Colors.black.withValues(alpha: 0.22),
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(icon, size: 12, color: tint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
