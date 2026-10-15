import 'package:cut_optimiser/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('linear best-fit solver returns stock for valid demand', () {
    final project = Project(
      name: 'Test linear',
      mode: CutMode.linear,
      stock: StockConfig(width: 6000),
      parts: [
        Part(name: 'A', a: 3000, quantity: 2),
        Part(name: 'B', a: 1000, quantity: 2)
      ],
    );
    final result = CuttingEngine.solve(project);
    expect(result.stockCount, 2);
    expect(result.linear.expand((s) => s.cuts).length, 4);
  });

  test('linear multi-order heuristic finds a tighter bar packing', () {
    final project = Project(
      name: 'Mixed bar packing',
      mode: CutMode.linear,
      stock: StockConfig(width: 100, kerf: 3, trim: 0),
      parts: [
        Part(name: 'A', a: 40),
        Part(name: 'B', a: 30),
        Part(name: 'C', a: 20),
        Part(name: 'D', a: 35),
        Part(name: 'E', a: 30),
        Part(name: 'F', a: 20),
      ],
    );

    final result = CuttingEngine.solve(project);
    expect(result.stockCount, 2);
    expect(result.linear.expand((stick) => stick.cuts).length, 6);
  });

  test('sheet multi-order heuristic selects a tighter nesting', () {
    final project = Project(
      name: 'Mixed rectangle nesting',
      mode: CutMode.sheet,
      stock: StockConfig(width: 100, height: 100, kerf: 2, trim: 0),
      parts: [
        Part(name: 'A', a: 30, b: 40),
        Part(name: 'B', a: 45, b: 35),
        Part(name: 'C', a: 65, b: 20),
        Part(name: 'D', a: 55, b: 30),
        Part(name: 'E', a: 50, b: 30),
        Part(name: 'F', a: 25, b: 15),
      ],
    );

    final result = CuttingEngine.solve(project);
    expect(result.stockCount, 1);
    expect(result.sheets.single.placements.length, 6);
  });

  test('linear solver optimises each assigned stock type separately', () {
    final stock50 = StockConfig(id: '50', name: '50x50 tube', width: 6000);
    final stock25 = StockConfig(id: '25', name: '25x25 tube', width: 3000);
    final project = Project(
      name: 'Mixed stock frame',
      mode: CutMode.linear,
      stocks: [stock50, stock25],
      parts: [
        Part(name: 'Upright', a: 1800, quantity: 2, stockId: '50'),
        Part(name: 'Rail', a: 900, quantity: 3, stockId: '25'),
      ],
    );
    final result = CuttingEngine.solve(project);
    expect(result.linear.length, 2);
    expect(result.linear.where((s) => s.stockName == '50x50 tube').length, 1);
    expect(result.linear.where((s) => s.stockName == '25x25 tube').length, 1);
    expect(result.linear.expand((s) => s.cuts).length, 5);
  });

  test('legacy single-stock project data migrates and assigns parts', () {
    final project = Project.fromJson({
      'name': 'Legacy',
      'mode': 'linear',
      'kerf': 4,
      'trim': 5,
      'stock': {'name': 'Old bar', 'width': 6000, 'quantity': 0},
      'parts': [
        {'name': 'Cut', 'a': 1000, 'quantity': 1},
      ],
    });
    expect(project.stocks.length, 1);
    expect(project.parts.single.stockId, project.stocks.single.id);
    expect(project.stocks.single.kerf, 4);
    expect(project.stocks.single.trim, 5);
  });

  test('cut status persists and remains attached to individual pieces', () {
    final project = Project(
      name: 'Cut tracking',
      mode: CutMode.sheet,
      stock: StockConfig(width: 100, height: 100, kerf: 0, trim: 0),
      parts: [
        Part(
          id: 'same-name-parts',
          name: 'Panel',
          a: 40,
          b: 40,
          quantity: 2,
        ),
      ],
      cutPieces: {'same-name-parts:1'},
    );

    final restored = Project.fromJson(project.toJson());
    final result = CuttingEngine.solve(restored);
    final placements = result.sheets.expand((sheet) => sheet.placements);

    expect(placements.map((part) => part.pieceIndex).toSet(), {0, 1});
    expect(placements.where((part) => part.isCut).single.cutKey,
        'same-name-parts:1');
    expect(restored.cutPieces, {'same-name-parts:1'});

    final linearProject = Project(
      name: 'Linear cut tracking',
      mode: CutMode.linear,
      stock: StockConfig(width: 100, kerf: 0, trim: 0),
      parts: [
        Part(
          id: 'linear-parts',
          name: 'Rail',
          a: 40,
          quantity: 2,
        ),
      ],
      cutPieces: {'linear-parts:0'},
    );
    final linearResult = CuttingEngine.solve(linearProject);
    final linearPlacements = linearResult.linear.expand((stick) => stick.cuts);
    expect(linearPlacements.where((part) => part.isCut).single.cutKey,
        'linear-parts:0');
    expect(linearResult.linear.single.offcutLength(5), 10);
    expect(result.sheets.single.unusedArea(5), 4900);
  });

  test(
      'identical linear and sheet layouts group while differing layouts stay separate',
      () {
    final firstBar = LinearStick(
      1,
      [PlacedPart('Rail', 0, 0, 40, 1, partId: 'rail', pieceIndex: 0)],
      40,
      100,
      stockName: 'Bar',
    );
    final matchingBar = LinearStick(
      2,
      [PlacedPart('Rail', 0, 0, 40, 1, partId: 'rail', pieceIndex: 1)],
      40,
      100,
      stockName: 'Bar',
    );
    final differentBar = LinearStick(
      3,
      [PlacedPart('Rail', 0, 0, 50, 1, partId: 'rail', pieceIndex: 2)],
      50,
      100,
      stockName: 'Bar',
    );
    final barGroups =
        groupLinearDiagrams([firstBar, matchingBar, differentBar], (_) => 0);
    expect(barGroups.map((group) => group.length), [2, 1]);

    final firstSheet = SheetLayout(
      1,
      [PlacedPart('Panel', 0, 0, 40, 40, partId: 'panel', pieceIndex: 0)],
      100,
      100,
      1600,
      stockName: 'Sheet',
    );
    final matchingSheet = SheetLayout(
      2,
      [PlacedPart('Panel', 0, 0, 40, 40, partId: 'panel', pieceIndex: 1)],
      100,
      100,
      1600,
      stockName: 'Sheet',
    );
    final sheetGroups =
        groupSheetDiagrams([firstSheet, matchingSheet], (_) => 0);
    expect(sheetGroups.single, [firstSheet, matchingSheet]);
  });
}
