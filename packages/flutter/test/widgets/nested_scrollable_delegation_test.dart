// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widgets_app_tester.dart';

void main() {
  group('Nested scrollable delegation', () {
    testWidgets(
      'OverscrollNotification from descendant can be handled by ancestor with same axis',
      (WidgetTester tester) async {
        final outerController = ScrollController();
        addTearDown(outerController.dispose);

        await tester.pumpWidget(
          TestWidgetsApp(
            home: SingleChildScrollView(
              controller: outerController,
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 100, child: Center(child: Text('Header'))),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: 3,
                      itemBuilder: (BuildContext context, int index) {
                        return SizedBox(height: 100, child: Center(child: Text('Inner $index')));
                      },
                    ),
                  ),
                  const SizedBox(height: 500, child: Center(child: Text('Footer'))),
                ],
              ),
            ),
          ),
        );

        // Initial state: at top
        expect(outerController.offset, 0.0);

        // Find inner ListView - it has exactly 3 items of 100px each = 300px
        // The container is also 300px, so there's no internal scroll
        // Any scroll attempt should delegate to parent

        // Drag down on the inner content area
        await tester.drag(find.text('Inner 1'), const Offset(0, -100));
        await tester.pumpAndSettle();

        // The outer ScrollView should have scrolled since inner has no scroll room
        expect(outerController.offset, greaterThan(0.0));
      },
    );

    testWidgets('Overscroll does NOT delegate across different axes', (WidgetTester tester) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await tester.pumpWidget(
        TestWidgetsApp(
          home: PageView(
            controller: pageController,
            children: <Widget>[
              // Page 1: Contains a vertical ListView
              ListView.builder(
                itemCount: 5,
                itemBuilder: (BuildContext context, int index) {
                  return SizedBox(height: 100, child: Text('V-Item $index'));
                },
              ),
              // Page 2
              const Center(child: Text('Page 2')),
            ],
          ),
        ),
      );

      // Initial state: on page 0
      expect(pageController.page, 0.0);

      // Scroll the ListView to the bottom (vertical scroll)
      await tester.fling(find.text('V-Item 0'), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();

      // Attempt to scroll past the ListView boundary (vertical)
      await tester.fling(find.text('V-Item 4'), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();

      // The PageView should NOT have scrolled because axes are different
      expect(pageController.page, 0.0);
    });

    testWidgets('OverscrollNotification bubbles up to ancestor', (WidgetTester tester) async {
      final notifications = <OverscrollNotification>[];

      await tester.pumpWidget(
        TestWidgetsApp(
          home: NotificationListener<OverscrollNotification>(
            onNotification: (OverscrollNotification notification) {
              notifications.add(notification);
              return false;
            },
            child: ListView.builder(
              itemCount: 20,
              itemBuilder: (BuildContext context, int index) {
                return SizedBox(height: 50, child: Text('Item $index'));
              },
            ),
          ),
        ),
      );

      // Pull down from the top to trigger overscroll
      await tester.fling(find.text('Item 0'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // OverscrollNotification should have been received
      expect(notifications, isNotEmpty);
      expect(notifications.first.overscroll, lessThan(0)); // Negative for overscroll at top/start
    });

    testWidgets('NestedScrollView continues to work correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        TestWidgetsApp(
          home: NestedScrollView(
            headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                const SliverPersistentHeader(
                  delegate: TestDelegate(minHeight: 60.0, maxHeight: 200.0),
                  pinned: true,
                ),
              ];
            },
            body: ListView.builder(
              itemCount: 30,
              itemBuilder: (BuildContext context, int index) {
                return Text('NSV Item $index');
              },
            ),
          ),
        ),
      );

      // Find the SliverPersistentHeader content
      expect(find.text('NestedScrollView Test'), findsOneWidget);

      // Scroll down
      await tester.fling(find.text('NSV Item 0'), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();

      // The header matches
      expect(find.text('NestedScrollView Test'), findsOneWidget);
    });

    testWidgets(
      'Horizontal ListView inside vertical PageView does not trigger page scroll on overscroll',
      (WidgetTester tester) async {
        final pageController = PageController();
        addTearDown(pageController.dispose);

        await tester.pumpWidget(
          TestWidgetsApp(
            home: PageView(
              controller: pageController,
              scrollDirection: Axis.vertical,
              children: <Widget>[
                // Page 1: Contains a horizontal ListView
                Column(
                  children: <Widget>[
                    const Text('Page 1'),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 5,
                        itemBuilder: (BuildContext context, int index) {
                          return SizedBox(width: 100, child: Center(child: Text('H-$index')));
                        },
                      ),
                    ),
                  ],
                ),
                // Page 2
                const Center(child: Text('Page 2')),
              ],
            ),
          ),
        );

        // Initial state: on page 0
        expect(pageController.page, 0.0);

        // Scroll horizontal ListView to the end
        await tester.fling(find.text('H-0'), const Offset(-300, 0), 1000);
        await tester.pumpAndSettle();

        // Continue scrolling horizontally past end
        await tester.fling(find.text('H-4'), const Offset(-100, 0), 1000);
        await tester.pumpAndSettle();

        // The vertical PageView should NOT have scrolled
        expect(pageController.page, 0.0);
      },
    );
  });
}

class TestDelegate extends SliverPersistentHeaderDelegate {
  const TestDelegate({required this.minHeight, required this.maxHeight});

  final double minHeight;
  final double maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      constraints: BoxConstraints(minHeight: minExtent, maxHeight: maxExtent),
      child: const Center(child: Text('NestedScrollView Test')),
    );
  }

  @override
  bool shouldRebuild(TestDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight;
  }
}
