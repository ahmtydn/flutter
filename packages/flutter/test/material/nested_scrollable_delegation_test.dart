// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nested scrollable delegation', () {
    testWidgets(
      'OverscrollNotification from descendant can be handled by ancestor with same axis',
      (WidgetTester tester) async {
        final outerController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
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

        outerController.dispose();
      },
    );

    testWidgets('Overscroll does NOT delegate across different axes', (WidgetTester tester) async {
      final pageController = PageController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
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

      pageController.dispose();
    });

    testWidgets('RefreshIndicator still works with nested scroll delegation', (
      WidgetTester tester,
    ) async {
      var refreshCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () async {
                refreshCalled = true;
              },
              child: ListView.builder(
                itemCount: 20,
                itemBuilder: (BuildContext context, int index) {
                  return SizedBox(height: 50, child: Text('Refresh Item $index'));
                },
              ),
            ),
          ),
        ),
      );

      // Pull down from the top to trigger refresh
      await tester.fling(find.text('Refresh Item 0'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // RefreshIndicator should have been triggered
      expect(refreshCalled, isTrue);
    });

    testWidgets('NestedScrollView continues to work correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                return <Widget>[
                  const SliverAppBar(
                    expandedHeight: 200,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(title: Text('NestedScrollView Test')),
                  ),
                ];
              },
              body: ListView.builder(
                itemCount: 30,
                itemBuilder: (BuildContext context, int index) {
                  return ListTile(title: Text('NSV Item $index'));
                },
              ),
            ),
          ),
        ),
      );

      // Find the SliverAppBar
      expect(find.byType(SliverAppBar), findsOneWidget);

      // Scroll down
      await tester.fling(find.text('NSV Item 0'), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();

      // The app bar should have collapsed (still visible due to pinned)
      expect(find.text('NestedScrollView Test'), findsOneWidget);
    });

    testWidgets(
      'Horizontal ListView inside vertical PageView does not trigger page scroll on overscroll',
      (WidgetTester tester) async {
        final pageController = PageController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageView(
                controller: pageController,
                scrollDirection: Axis.vertical, // Vertical PageView
                children: <Widget>[
                  // Page 1: Contains a horizontal ListView
                  Column(
                    children: <Widget>[
                      const Text('Page 1'),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal, // Different axis!
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

        pageController.dispose();
      },
    );
  });
}
