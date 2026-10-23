import 'package:flutter/material.dart';
import 'package:openrc/core/shell_insets.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// First-load placeholder mirroring the Transactions / Revenue layout:
/// hero card, two rows of tiles, and grouped rows.
class TransactionsLoadingSkeleton extends StatelessWidget {
  const TransactionsLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = mainShellFloatingTabBarScrollPadding(context);
    Widget tileRow() => Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs),
          const Expanded(
            child: AppCard(
              radius: AppRadius.tile,
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(fontSize: 12, width: 56),
                  SizedBox(height: 8),
                  Bone.text(fontSize: 22, width: 32),
                  SizedBox(height: 10),
                  Bone(
                    height: 3,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    return Skeletonizer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Bone.text(fontSize: 13, width: 90),
                const SizedBox(height: 8),
                const Bone.text(fontSize: 32, width: 150),
                const SizedBox(height: 10),
                const Bone.text(fontSize: 13, width: 180),
                const SizedBox(height: 18),
                SizedBox(
                  height: 44,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in const [
                        24.0,
                        32.0,
                        18.0,
                        40.0,
                        28.0,
                        44.0,
                        20.0,
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Bone(
                              height: h,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          tileRow(),
          const SizedBox(height: 8),
          tileRow(),
          const SizedBox(height: 20),
          const TransactionRowsSkeleton(rows: 5, padding: EdgeInsets.zero),
        ],
      ),
    );
  }
}

/// Placeholder rows in a grouped card (initial load and loading more).
class TransactionRowsSkeleton extends StatelessWidget {
  const TransactionRowsSkeleton({
    super.key,
    required this.rows,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final int rows;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Skeletonizer(
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows; i++) ...[
                if (i > 0) const Divider(indent: 64),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone.square(
                        size: 40,
                        borderRadius: BorderRadius.circular(AppRadius.icon),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Bone.text(fontSize: 15, width: 120),
                            SizedBox(height: 6),
                            Bone.text(fontSize: 12, width: 170),
                            SizedBox(height: 4),
                            Bone.text(fontSize: 12, width: 110),
                          ],
                        ),
                      ),
                      const Bone.text(fontSize: 15, width: 52),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
