// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PR 181761 Reproduction Tests', () {
    testWidgets('ISSUE 1: Redundant Start/End notifications on parent', (
      WidgetTester tester,
    ) async {
      final outerController = ScrollController();
      var parentStartNotifications = 0;
      var parentEndNotifications = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(delegateOverscroll: true),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  if (notification is ScrollStartNotification) {
                    parentStartNotifications++;
                  } else if (notification is ScrollEndNotification) {
                    parentEndNotifications++;
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: outerController,
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 100, child: Text('Header')),
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: 1,
                        itemBuilder: (context, index) =>
                            const SizedBox(height: 100, child: Text('Inner Item')),
                      ),
                    ),
                    const SizedBox(height: 600, child: Text('Footer')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Move to a steady state at the boundary.
      await tester.drag(find.text('Inner Item'), const Offset(0, -50));
      await tester.pumpAndSettle();
      parentStartNotifications = 0; // Reset any initial noise

      // 2. Start a continuous gesture.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Inner Item')),
      );

      // Move 1: Triggers delegation.
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(parentStartNotifications, 1, reason: 'Parent should start scrolling.');

      // Move 2: Continuous drag.
      // BUG: applyScrollDeltaWithPhysics calls didStartScroll again here.
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(
        parentStartNotifications,
        1,
        reason: 'Parent should NOT trigger a second StartNotification during a single gesture.',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('ISSUE 2: Partial overscroll consumption loss', (WidgetTester tester) async {
      final rootController = ScrollController();
      final intermediateController = ScrollController();
      const innerKey = Key('inner');

      // Setup: Intermediate has 150px of scrollable room.
      // We will scroll it to 100px, leaving exactly 50px left.
      // Then we will delegate 100px of overscroll.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(delegateOverscroll: true),
            child: SingleChildScrollView(
              controller: rootController,
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 100, child: Text('RootHeader')),
                  SizedBox(
                    height: 150,
                    child: SingleChildScrollView(
                      controller: intermediateController,
                      child: const SizedBox(height: 300, child: Text('IntermediateContent')),
                    ),
                  ),
                  const SizedBox(height: 500, child: Text('RootFooter')),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. Manually set intermediate to 100/150.
      intermediateController.jumpTo(100.0);
      await tester.pumpAndSettle();

      expect(intermediateController.offset, 100.0);
      expect(rootController.offset, 0.0);

      // 2. Dispatch a manual overscroll notification from the child.
      // This simulates the inner child overscrolling by 100px.
      final ScrollableState scrollableState = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      final metrics = ScrollMetricsNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 0,
          pixels: 0,
          viewportDimension: 100,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1.0,
        ),
        context: scrollableState.context,
      );

      // We use the internal handler to simulate the exact notification flow.
      final notification = OverscrollNotification(
        metrics: metrics.metrics,
        context: scrollableState.context,
        overscroll: 100.0, // Child overscrolled by 100
      );

      // Bubble the notification.
      notification.dispatch(tester.element(find.text('IntermediateContent')));
      await tester.pumpAndSettle();

      // Math:
      // Intermediate takes 50px (to reach its max of 150).
      // Root SHOULD take the remaining 50px.
      // BUG: The PR returns 'true' (consumed) in ScrollableState._handleDescendantOverscroll,
      // stopping the bubble even though 50px was unhandled.

      expect(intermediateController.offset, 150.0, reason: 'Intermediate should be at max.');
      expect(
        rootController.offset,
        50.0,
        reason: 'Root should have received the remaining 50px delta.',
      );
    });
  });
}
