import 'dart:convert';

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

  testWidgets('new part defaults to the last part stock type',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final firstStock = StockConfig(
      id: 'stock-first',
      name: 'First profile',
      width: 6000,
    );
    final recentStock = StockConfig(
      id: 'stock-recent',
      name: 'Recent profile',
      width: 3000,
    );
    final project = Project(
      name: 'Stock preference',
      mode: CutMode.linear,
      stocks: [firstStock, recentStock],
      assemblies: [
        Assembly(
          name: 'Frame',
          parts: [
            Part(name: 'Recent rail', a: 800, stockId: recentStock.id),
          ],
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'cut_optimiser_projects_v1': jsonEncode([
        project.toJson(includeStockDefinitions: false),
      ]),
      'cut_optimiser_stocks_v1':
          jsonEncode([firstStock.toJson(), recentStock.toJson()]),
    });

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts list').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add part to assembly'));
    await tester.pumpAndSettle();

    final stockDropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first);
    expect(stockDropdown.initialValue, recentStock.id);
    expect(
        find.text('Mild steel 25×25×1.6 mm — Recent profile'), findsOneWidget);
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

  testWidgets('optimisation results show required stock by stock type',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Optimisation results').last);
    await tester.pumpAndSettle();

    expect(find.text('Required stock by type'), findsOneWidget);
    expect(find.textContaining('bars required'), findsWidgets);
    expect(find.textContaining('available'), findsWidgets);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('projects can be archived and restored',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    final archiveButton = find.byTooltip('Archive project').first;
    await tester.ensureVisible(archiveButton);
    await tester.tap(archiveButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('No active projects.'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('cut_optimiser_projects_v1'),
      contains('"archived":true'),
    );

    await tester.tap(find.text('Show archived'));
    await tester.pumpAndSettle();
    expect(find.text('Workshop — frame set'), findsWidgets);
    final restoreButton = find.byTooltip('Restore project').first;
    await tester.ensureVisible(restoreButton);
    await tester.tap(restoreButton);
    await tester.pumpAndSettle();

    expect(find.text('No archived projects.'), findsOneWidget);
    expect(find.textContaining('Active'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('project deletion requires confirmation',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    final deleteButton = find.byTooltip('Delete project').first;
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete project?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Workshop — frame set'), findsWidgets);

    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('No active projects.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();
    expect(find.text('Workshop — frame set'), findsNothing);
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
