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

  testWidgets('part editor updates the name and dimensions',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts list').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byTooltip('Edit part name, dimensions and quantity').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Edited upright');
    await tester.enterText(fields.at(1), '2100');
    await tester.tap(find.text('Save part'));
    await tester.pumpAndSettle();

    expect(find.text('Edited upright'), findsOneWidget);
    expect(find.textContaining('Length 2100.0 mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('part editor can reassign a part to another assembly',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts list').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add assembly').first);
    await tester.pumpAndSettle();
    final assemblyFields = find.byType(TextField);
    await tester.enterText(assemblyFields.at(0), 'Table');
    await tester.enterText(assemblyFields.at(1), '1');
    await tester.tap(find.text('Add assembly').last);
    await tester.pumpAndSettle();

    final editPart =
        find.byTooltip('Edit part name, dimensions and quantity').first;
    await tester.ensureVisible(editPart);
    await tester.tap(editPart);
    await tester.pumpAndSettle();
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save part'));
    await tester.pumpAndSettle();

    expect(find.textContaining('4 parts per assembly • 4 total cuts'),
        findsOneWidget);
    expect(find.text('Upright'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android phone navigation uses a drawer',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<int>), findsNothing);
    expect(
      tester.getTopLeft(find.byTooltip('Open navigation menu')).dy,
      greaterThanOrEqualTo(24),
    );
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

  testWidgets('appearance preference switches and persists dark mode',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cut_optimiser_theme_mode_v1'), 'dark');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
