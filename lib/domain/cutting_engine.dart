import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'cut_optimiser_models.dart';

class LinearStick {
  LinearStick(this.index, this.cuts, this.used, this.stockLength,
      {this.stockName = 'Stock'});

  String stockName;
  int index;
  List<PlacedPart> cuts;
  double used;
  double stockLength;

  double offcutLength(double trim) =>
      math.max(0, stockLength - 2 * trim - used);
}

List<List<LinearStick>> groupLinearDiagrams(
    List<LinearStick> diagrams, double Function(LinearStick) trimFor) {
  final groups = <String, List<LinearStick>>{};
  for (final diagram in diagrams) {
    final key = jsonEncode([
      diagram.stockName,
      diagram.stockLength,
      trimFor(diagram),
      for (final part in diagram.cuts)
        [
          part.name,
          part.x,
          part.w,
          part.isCut,
        ],
    ]);
    groups.putIfAbsent(key, () => []).add(diagram);
  }
  return groups.values.toList();
}

class PlacedPart {
  PlacedPart(this.name, this.x, this.y, this.w, this.h,
      {this.rotated = false,
      this.partId = '',
      this.pieceIndex = 0,
      this.isCut = false});

  final String name;
  final double x, y, w, h;
  final bool rotated;
  final String partId;
  final int pieceIndex;
  final bool isCut;

  String get cutKey => '$partId:$pieceIndex';
}

class SheetLayout {
  SheetLayout(
      this.index, this.placements, this.stockW, this.stockH, this.usedArea,
      {this.stockName = 'Stock'});

  final String stockName;
  final int index;
  final List<PlacedPart> placements;
  final double stockW, stockH;
  double usedArea;

  double unusedArea(double trim) =>
      math.max(0, (stockW - 2 * trim) * (stockH - 2 * trim) - usedArea);
}

List<List<SheetLayout>> groupSheetDiagrams(
    List<SheetLayout> diagrams, double Function(SheetLayout) trimFor) {
  final groups = <String, List<SheetLayout>>{};
  for (final diagram in diagrams) {
    final key = jsonEncode([
      diagram.stockName,
      diagram.stockW,
      diagram.stockH,
      trimFor(diagram),
      for (final part in diagram.placements)
        [
          part.name,
          part.x,
          part.y,
          part.w,
          part.h,
          part.rotated,
          part.isCut,
        ],
    ]);
    groups.putIfAbsent(key, () => []).add(diagram);
  }
  return groups.values.toList();
}

class SolveResult {
  SolveResult(
      {required this.mode,
      required this.linear,
      required this.sheets,
      required this.demandArea,
      required this.totalStockArea,
      required this.notes});

  final CutMode mode;
  final List<LinearStick> linear;
  final List<SheetLayout> sheets;
  final double demandArea, totalStockArea;
  final List<String> notes;

  int get stockCount => mode == CutMode.linear ? linear.length : sheets.length;

  double get waste =>
      totalStockArea <= 0 ? 0 : math.max(0, 1 - demandArea / totalStockArea);
}

class CuttingEngine {
  static SolveResult solve(Project project) {
    final allLinear = <LinearStick>[];
    final allSheets = <SheetLayout>[];
    final notes = <String>[];
    var demand = 0.0;
    var stockArea = 0.0;

    for (final stock in project.stocks) {
      final assigned =
          project.parts.where((part) => part.stockId == stock.id).toList();
      if (assigned.isEmpty) continue;

      final sub = Project(
        name: project.name,
        mode: project.mode,
        material: project.material,
        variant: project.variant,
        unit: project.unit,
        kerf: stock.kerf,
        trim: stock.trim,
        parts: assigned,
        stock: stock,
        cutPieces: project.cutPieces,
      );

      final result =
          project.mode == CutMode.linear ? _linear(sub) : _sheets(sub);
      demand += result.demandArea;
      stockArea += result.totalStockArea;
      notes.addAll(result.notes.map((note) => '${stock.name}: $note'));

      if (project.mode == CutMode.linear) {
        for (var index = 0; index < result.linear.length; index++) {
          final layout = result.linear[index];
          layout.stockName = stock.name;
          layout.index = allLinear.length + 1;
          allLinear.add(layout);
        }
      } else {
        for (var index = 0; index < result.sheets.length; index++) {
          final layout = result.sheets[index];
          final combined = SheetLayout(
            allSheets.length + 1,
            layout.placements,
            layout.stockW,
            layout.stockH,
            layout.usedArea,
            stockName: stock.name,
          );
          allSheets.add(combined);
        }
      }
    }

    return SolveResult(
      mode: project.mode,
      linear: allLinear,
      sheets: allSheets,
      demandArea: demand,
      totalStockArea: stockArea,
      notes: notes,
    );
  }

  static SolveResult _linear(Project project) {
    final items = <Part>[];
    for (final part in project.parts) {
      for (var index = 0; index < part.quantity; index++) {
        items.add(Part(
          id: part.id,
          pieceIndex: index,
          name: part.name,
          a: part.a,
        ));
      }
    }

    final usable = project.stock.width - project.trim * 2;
    final orders = <List<Part>>[
      [...items]..sort((a, b) => b.a.compareTo(a.a)),
      [...items]..sort((a, b) => a.a.compareTo(b.a)),
      [...items],
    ];

    final candidates = <List<LinearStick>>[
      for (final order in orders) ...[
        _packLinear(order, project, usable, bestFit: true),
        _packLinear(order, project, usable, bestFit: false),
      ],
    ];

    candidates.sort((left, right) {
      final count = left.length.compareTo(right.length);
      if (count != 0) return count;
      return _linearOffcutScore(left, usable)
          .compareTo(_linearOffcutScore(right, usable));
    });

    final sticks = candidates.first;
    final totalDemand = items.fold<double>(0, (sum, item) => sum + item.a);
    final totalStock = sticks.length * usable;
    final notes = <String>[
      'Heuristic: best-fit/first-fit across descending, ascending and entered demand orders; not a proof of global optimality.'
    ];
    final oversized =
        project.parts.where((part) => part.a > usable || part.a <= 0).toList();
    if (oversized.isNotEmpty) {
      notes.add(
          'Invalid or infeasible parts skipped (non-positive or longer than usable stock): ${oversized.map((part) => part.name).join(', ')}.');
    }
    if (project.stock.quantity > 0 && sticks.length > project.stock.quantity) {
      notes.add(
          'Required stock exceeds configured available quantity (${project.stock.quantity}).');
    }

    return SolveResult(
      mode: CutMode.linear,
      linear: sticks,
      sheets: const [],
      demandArea: totalDemand,
      totalStockArea: totalStock,
      notes: notes,
    );
  }

  static List<LinearStick> _packLinear(
      List<Part> order, Project project, double usable,
      {required bool bestFit}) {
    final sticks = <LinearStick>[];

    for (final item in order) {
      if (item.a <= 0 || item.a > usable) continue;

      LinearStick? selected;
      var bestRemaining = double.infinity;
      for (final stick in sticks) {
        final nextUsed =
            stick.used + item.a + (stick.cuts.isEmpty ? 0 : project.kerf);
        final remaining = usable - nextUsed;
        if (remaining < -0.000001) continue;
        if (selected == null || (bestFit && remaining < bestRemaining)) {
          selected = stick;
          bestRemaining = remaining;
          if (!bestFit) break;
        }
      }

      selected ??= LinearStick(sticks.length + 1, [], 0, project.stock.width);
      if (!sticks.contains(selected)) sticks.add(selected);

      final x = project.trim +
          selected.used +
          (selected.cuts.isEmpty ? 0 : project.kerf);
      selected.cuts.add(PlacedPart(item.name, x, 0, item.a, 1,
          partId: item.id,
          pieceIndex: item.pieceIndex ?? 0,
          isCut: project.cutPieces.contains('${item.id}:${item.pieceIndex}')));
      selected.used += item.a + (selected.cuts.length == 1 ? 0 : project.kerf);
    }

    return sticks;
  }

  static double _linearOffcutScore(List<LinearStick> sticks, double usable) =>
      sticks.fold<double>(
          0,
          (score, stick) =>
              score + math.pow(math.max(0, usable - stick.used), 2).toDouble());

  static SolveResult _sheets(Project project) {
    final parts = <Part>[];
    for (final part in project.parts) {
      for (var index = 0; index < part.quantity; index++) {
        parts.add(Part(
            id: part.id,
            pieceIndex: index,
            name: part.name,
            a: part.a,
            b: part.b,
            rotate: part.rotate));
      }
    }

    final usableW = project.stock.width - 2 * project.trim;
    final usableH = project.stock.height - 2 * project.trim;
    final orders = <List<Part>>[
      [...parts]..sort((a, b) => (b.a * b.b).compareTo(a.a * a.b)),
      [...parts]
        ..sort((a, b) => math.max(b.a, b.b).compareTo(math.max(a.a, a.b))),
      [...parts]..sort((a, b) => b.a.compareTo(a.a)),
      [...parts]..sort((a, b) => b.b.compareTo(a.b)),
      [...parts]..sort((a, b) => (b.a + b.b).compareTo(a.a + a.b)),
    ];

    final candidates = orders
        .map((order) => _packSheets(order, project, usableW, usableH))
        .toList()
      ..sort((left, right) {
        final count = left.length.compareTo(right.length);
        if (count != 0) return count;
        return _sheetCompactnessScore(left)
            .compareTo(_sheetCompactnessScore(right));
      });

    final sheets = candidates.first;
    final demandArea =
        parts.fold<double>(0, (sum, part) => sum + part.a * part.b);
    final totalArea = sheets.length * usableW * usableH;
    final notes = <String>[
      'Heuristic: best layout from area, longest-side, width, height and perimeter orderings; not a proof of global optimality.',
      'Layouts show geometric nesting only. Guillotine cut sequence and machine-specific constraints are not implemented.'
    ];
    final invalid = parts
        .where((part) => !(part.a > 0 &&
            part.b > 0 &&
            ((part.a <= usableW && part.b <= usableH) ||
                (part.rotate && part.b <= usableW && part.a <= usableH))))
        .toList();
    if (invalid.isNotEmpty) {
      notes.add(
          'Parts that do not fit any sheet orientation were skipped: ${invalid.map((part) => part.name).join(', ')}.');
    }
    if (project.stock.quantity > 0 && sheets.length > project.stock.quantity) {
      notes.add(
          'Required sheets exceed configured available quantity (${project.stock.quantity}).');
    }

    return SolveResult(
      mode: CutMode.sheet,
      linear: const [],
      sheets: sheets,
      demandArea: demandArea,
      totalStockArea: totalArea,
      notes: notes,
    );
  }

  static List<SheetLayout> _packSheets(
      List<Part> order, Project project, double usableW, double usableH) {
    final sheets = <SheetLayout>[];

    for (final part in order) {
      if (part.a <= 0 || part.b <= 0 || usableW <= 0 || usableH <= 0) {
        continue;
      }

      SheetLayout? selectedSheet;
      PlacedPart? selectedSpot;
      var selectedScore = double.infinity;

      for (final sheet in sheets) {
        final spot =
            _findSpot(sheet.placements, part, usableW, usableH, project.kerf);
        if (spot == null) continue;
        final score = _sheetAddedBounds(sheet, spot);
        if (score < selectedScore) {
          selectedSheet = sheet;
          selectedSpot = spot;
          selectedScore = score;
        }
      }

      if (selectedSheet == null) {
        selectedSheet = SheetLayout(sheets.length + 1, [], project.stock.width,
            project.stock.height, 0);
        selectedSpot = _findSpot(
            selectedSheet.placements, part, usableW, usableH, project.kerf);
        if (selectedSpot == null) continue;
        sheets.add(selectedSheet);
      }

      final spot = selectedSpot;
      if (spot == null) continue;

      selectedSheet.placements.add(PlacedPart(
          part.name, spot.x, spot.y, spot.w, spot.h,
          rotated: spot.rotated,
          partId: part.id,
          pieceIndex: part.pieceIndex ?? 0,
          isCut: project.cutPieces.contains('${part.id}:${part.pieceIndex}')));
      selectedSheet.usedArea += part.a * part.b;
    }

    return sheets;
  }

  static double _sheetAddedBounds(SheetLayout sheet, PlacedPart part) {
    var maxX = part.x + part.w;
    var maxY = part.y + part.h;
    for (final old in sheet.placements) {
      maxX = math.max(maxX, old.x + old.w);
      maxY = math.max(maxY, old.y + old.h);
    }
    return maxX * maxY;
  }

  static double _sheetCompactnessScore(List<SheetLayout> sheets) =>
      sheets.fold<double>(0, (score, sheet) {
        var maxX = 0.0;
        var maxY = 0.0;
        for (final part in sheet.placements) {
          maxX = math.max(maxX, part.x + part.w);
          maxY = math.max(maxY, part.y + part.h);
        }
        return score + maxX * maxY;
      });

  static PlacedPart? _findSpot(List<PlacedPart> placed, Part part, double maxW,
      double maxH, double kerf) {
    final candidates = <Offset>[const Offset(0, 0)];
    for (final existing in placed) {
      candidates.add(Offset(existing.x + existing.w + kerf, existing.y));
      candidates.add(Offset(existing.x, existing.y + existing.h + kerf));
    }
    candidates.sort((a, b) {
      final byY = a.dy.compareTo(b.dy);
      return byY != 0 ? byY : a.dx.compareTo(b.dx);
    });

    for (final point in candidates) {
      for (final rotated in [false, true]) {
        if (rotated && (!part.rotate || part.a == part.b)) continue;
        final w = rotated ? part.b : part.a;
        final h = rotated ? part.a : part.b;
        if (point.dx + w > maxW || point.dy + h > maxH) continue;

        final rect = Rect.fromLTWH(point.dx, point.dy, w + kerf, h + kerf);
        final collision = placed.any((old) => rect
            .overlaps(Rect.fromLTWH(old.x, old.y, old.w + kerf, old.h + kerf)));
        if (!collision) {
          return PlacedPart(part.name, point.dx, point.dy, w, h,
              rotated: rotated,
              partId: part.id,
              pieceIndex: part.pieceIndex ?? 0);
        }
      }
    }
    return null;
  }
}
