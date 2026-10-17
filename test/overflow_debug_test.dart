import 'package:cut_optimiser/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('debug page loop', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CutOptimiserApp());
    await tester.pumpAndSettle();

    for (final page in [
      'Projects',
      'Materials & stock',
      'Parts list',
      'Optimisation results',
      'Cutting diagrams',
      'Reports',
      'Dashboard',
    ]) {
      if (kDebugMode) {
        print('PAGE:$page');
      }
      try {
        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(page).last);
        await tester.pumpAndSettle();
      } catch (e) {
        if (kDebugMode) {
          print('TAP_ERR:$e');
        }
      }
      final exception = tester.takeException();
      if (kDebugMode) {
        print('EX:$exception');
      }
    }
  });
}
