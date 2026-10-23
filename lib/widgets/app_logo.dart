import 'package:flutter/material.dart';

/// The OpenRC mark: a cat hugging a database, on its red rounded square.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/openrc-mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
