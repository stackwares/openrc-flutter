import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Rows inside one rounded card with inset hairline dividers (non-lazy).
class GroupedCard extends StatelessWidget {
  const GroupedCard({
    super.key,
    required this.children,
    this.dividerIndent = AppSpace.md,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
  });

  final List<Widget> children;
  final double dividerIndent;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: dividerIndent),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Lazy version of [GroupedCard] for long lists inside a [CustomScrollView].
class GroupedSliverList extends StatelessWidget {
  const GroupedSliverList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = AppSpace.md,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    const radius = Radius.circular(AppRadius.card);
    return SliverPadding(
      padding: padding,
      sliver: DecoratedSliver(
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: context.appColors.hairline),
          ),
        ),
        sliver: SliverList.separated(
          itemCount: itemCount,
          separatorBuilder: (_, _) => Divider(indent: dividerIndent),
          itemBuilder: (context, index) {
            // Rows paint ink on their own transparent Material (the
            // decoration sits above the scaffold's), clipped to the corners.
            return ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: index == 0 ? radius : Radius.zero,
                bottom: index == itemCount - 1 ? radius : Radius.zero,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: itemBuilder(context, index),
              ),
            );
          },
        ),
      ),
    );
  }
}
