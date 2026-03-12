import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingScrollPosition extends ScrollPositionWithSingleContext {
  _TrackingScrollPosition({required super.physics, required super.context, super.oldPosition});

  int goBallisticCallCount = 0;
  int didStartScrollCallCount = 0;
  int didEndScrollCallCount = 0;

  @override
  void goBallistic(double velocity) {
    goBallisticCallCount++;
    super.goBallistic(velocity);
  }

  @override
  void didStartScroll() {
    didStartScrollCallCount++;
    super.didStartScroll();
  }

  @override
  void didEndScroll() {
    didEndScrollCallCount++;
    super.didEndScroll();
  }
}

class _TrackingScrollController extends ScrollController {
  _TrackingScrollPosition? trackingPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    trackingPosition = _TrackingScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
    );
    return trackingPosition!;
  }
}

class _DelegatingScrollBehavior extends MaterialScrollBehavior {
  @override
  bool get delegateOverscroll => true;
}

Widget _buildTestWidget({
  required ScrollController outerController,
  required ScrollController innerController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ScrollConfiguration(
        behavior: _DelegatingScrollBehavior(),
        child: CustomScrollView(
          controller: outerController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                child: ListView.builder(
                  controller: innerController,
                  physics: const ClampingScrollPhysics(),
                  itemCount: 20,
                  itemBuilder: (BuildContext context, int index) =>
                      ListTile(title: Text('Item $index')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  // ── Test 1 ──────────────────────────────────────────────────────────────────
  testWidgets(
    'Bug #1: goBallistic() must not be called on every frame during applyDelegatedOverscroll',
    (WidgetTester tester) async {
      final outerController = _TrackingScrollController();
      final innerController = ScrollController();

      await tester.pumpWidget(
        _buildTestWidget(outerController: outerController, innerController: innerController),
      );
      await tester.pumpAndSettle();

      // Move inner list to the very top so upward drag creates overscroll immediately
      innerController.jumpTo(0);
      await tester.pump();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );

      // Reset counter just before the drag sequence to exclude any initial
      // setup calls (like the initial goBallistic(0) from layout).
      outerController.trackingPosition!.goBallisticCallCount = 0;

      // Drag upwards for 10 frames to engage overscroll delegation
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Measure the count BEFORE lifting the finger.
      // Correct behavior: Over 10 frames of continuous dragging,
      // goBallistic() should be called at most once (or zero times during the drag itself).
      final int countDuringDrag = outerController.trackingPosition!.goBallisticCallCount;

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        countDuringDrag,
        lessThanOrEqualTo(1),
        reason:
            'goBallistic() was called $countDuringDrag times during a continuous drag. '
            'Correct behavior: it should be called at most once while the drag is active. '
            'Calling it on every frame constantly resets the BouncingScrollPhysics '
            'simulation, resulting in a jittery animation.',
      );
    },
  );

  // ── Test 2 ──────────────────────────────────────────────────────────────────
  testWidgets(
    'Bug #2: A single gesture must produce exactly one ScrollStart and one ScrollEnd notification',
    (WidgetTester tester) async {
      final outerController = _TrackingScrollController();
      final innerController = ScrollController();

      await tester.pumpWidget(
        _buildTestWidget(outerController: outerController, innerController: innerController),
      );
      await tester.pumpAndSettle();

      innerController.jumpTo(0);
      await tester.pump();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );

      // Drag upwards for 10 frames to engage overscroll delegation
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }

      await gesture.up();
      await tester.pumpAndSettle();

      final _TrackingScrollPosition position = outerController.trackingPosition!;

      // didStartScroll() → dispatches ScrollStartNotification.
      // It should be called exactly once for a single continuous gesture.
      expect(
        position.didStartScrollCallCount,
        1,
        reason:
            'didStartScroll() was called ${position.didStartScrollCallCount} times. '
            'It must be called exactly once for a single gesture. '
            'Excess calls break analytics, animations, and other listeners.',
      );

      // didEndScroll() → dispatches ScrollEndNotification.
      // It should be called exactly once after the gesture ends.
      expect(
        position.didEndScrollCallCount,
        1,
        reason:
            'didEndScroll() was called ${position.didEndScrollCallCount} times. '
            'It must be called exactly once for a single gesture.',
      );
    },
  );
}
