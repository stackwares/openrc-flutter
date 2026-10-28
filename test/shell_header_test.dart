import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/shell_header.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    double Function(double width)? contentMaxWidth,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ShellHeader(
            title: 'Today',
            contentMaxWidth: contentMaxWidth,
            actions: [
              HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  double titleLeft(WidgetTester tester) =>
      tester.getTopLeft(find.text('Today')).dx;
  double actionRight(WidgetTester tester) =>
      tester.getTopRight(find.byType(IconButton)).dx;

  testWidgets('wide windows line the title and actions up with the content', (
    tester,
  ) async {
    await pump(tester, width: 1600, contentMaxWidth: (_) => 1000);
    // (1600 - 1000) / 2 on each side, then the usual spacing.
    expect(titleLeft(tester), 300 + 20);
    expect(actionRight(tester), 1600 - 300 - 12 - 3);
  });

  testWidgets('the width rule gets the header width', (tester) async {
    await pump(
      tester,
      width: 1600,
      contentMaxWidth: AppBreakpoints.dashboardTabMaxWidth,
    );
    expect(
      titleLeft(tester),
      (1600 - AppBreakpoints.dashboardMaxWidth) / 2 + 20,
    );
  });

  testWidgets('narrower than the content, nothing moves', (tester) async {
    await pump(tester, width: 800, contentMaxWidth: (_) => 1000);
    expect(titleLeft(tester), 20);
    expect(actionRight(tester), 800 - 12 - 3);
  });

  testWidgets('without a content width the header spans the window', (
    tester,
  ) async {
    await pump(tester, width: 1600);
    expect(titleLeft(tester), 20);
    expect(actionRight(tester), 1600 - 12 - 3);
  });
}
