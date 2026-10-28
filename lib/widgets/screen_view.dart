import 'package:flutter/material.dart';
import 'package:openrc/services/telemetry.dart';

/// Reports [name] as a screen view once, when it is first built.
///
/// Screens with state of their own call `Telemetry.screen` in `initState`;
/// this is for the ones that are a single `build`, so a rebuild cannot turn
/// into a second screen view.
class ScreenView extends StatefulWidget {
  const ScreenView({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  @override
  void initState() {
    super.initState();
    Telemetry.screen(widget.name);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
