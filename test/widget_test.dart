import 'package:cut_optimiser/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app launches with the sample cutting project',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    expect(find.text('Production overview'), findsOneWidget);
    expect(find.text('Workshop — frame set'), findsOneWidget);
  });

  testWidgets('phone layout does not overflow', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    for (final page in [
      'Projects',
      'Materials & stock',
      'Parts list',
      'Optimisation results',
      'Cutting diagrams',
      'Reports',
      'Dashboard',
      'About',
    ]) {
      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(page).last);
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull, reason: '$page page overflows: $exception');
    }
    expect(find.text('Copyright (C) 2026 Tendai Shoko'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android phone navigation uses a drawer',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<int>), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('Project editor'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    final exception = tester.takeException();
    expect(exception, isNull, reason: '$exception');
    debugDefaultTargetPlatformOverride = null;
  });
}
