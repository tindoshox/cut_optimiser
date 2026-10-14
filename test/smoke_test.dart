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
}
