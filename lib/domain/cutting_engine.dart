import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'cut_optimiser_models.dart';

class LinearStick {
  LinearStick(this.index, this.cuts, this.used, this.stockLength,
      {this.stockName = 'Stock', this.stockId = ''});

  String stockName;
  String stockId;
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
      diagram.stockId,
      diagram.stockName,
      diagram.stockLength,
      trimFor(diagram),
      for (final part in diagram.cuts)
        [
          part.assemblyName,
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
      this.assemblyName = '',
      this.partId = '',
      this.pieceIndex = 0,
      this.isCut = false});

  final String name;
  final double x, y, w, h;
  final bool rotated;
  final String assemblyName;
  final String partId;
  final int pieceIndex;
  final bool isCut;

  String get cutKey => '$partId:$pieceIndex';
}

class SheetLayout {
  SheetLayout(
      this.index, this.placements, this.stockW, this.stockH, this.usedArea,
      {this.stockName = 'Stock', this.stockId = ''});

  final String stockName;
  final String stockId;
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
      diagram.stockId,
      diagram.stockName,
      diagram.stockW,
      diagram.stockH,
      trimFor(diagram),
      for (final part in diagram.placements)
        [
          part.assemblyName,
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
      final assigned = project.demandParts
          .where((part) => part.stockId == stock.id)
          .toList();
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
          layout.stockId = stock.id;
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
            stockId: stock.id,
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
          assemblyName: part.assemblyName,
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
      'Waste priority: minimise stock units first, then reduce offcut fragmentation. Heuristic result; global optimality is not proven.'
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

      selected ??= LinearStick(sticks.length + 1, [], 0, project.stock.width,
          stockName: project.stock.name, stockId: project.stock.id);
      if (!sticks.contains(selected)) sticks.add(selected);

      final x = project.trim +
          selected.used +
          (selected.cuts.isEmpty ? 0 : project.kerf);
      selected.cuts.add(PlacedPart(item.name, x, 0, item.a, 1,
          assemblyName: item.assemblyName,
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
            rotate: part.rotate,
            assemblyName: part.assemblyName));
      }
    }

    final usableW = project.stock.width - 2 * project.trim;
    final usableH = project.stock.height - 2 * project.trim;
    final orders = _sheetOrders(parts);

    final candidates = orders
        .map((order) => _packSheets(order, project, usableW, usableH))
        .toList()
      ..sort((left, right) {
        final count = left.length.compareTo(right.length);
        if (count != 0) return count;
        final compactness = _sheetCompactnessScore(left)
            .compareTo(_sheetCompactnessScore(right));
        if (compactness != 0) return compactness;
        return _sheetEdgeWasteScore(left)
            .compareTo(_sheetEdgeWasteScore(right));
      });

    final sheets = candidates.first;
    final demandArea =
        parts.fold<double>(0, (sum, part) => sum + part.a * part.b);
    final totalArea = sheets.length * usableW * usableH;
    final notes = <String>[
      'Waste priority: minimise sheet count first, then choose the most compact layout from multiple deterministic part orderings. Global optimality is not proven.',
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

  static List<List<Part>> _sheetOrders(List<Part> parts) {
    final orders = <List<Part>>[];
    final comparators = <int Function(Part, Part)>[
      (a, b) => (b.a * b.b).compareTo(a.a * a.b),
      (a, b) => math.max(b.a, b.b).compareTo(math.max(a.a, a.b)),
      (a, b) => math.min(b.a, b.b).compareTo(math.min(a.a, a.b)),
      (a, b) => (b.a + b.b).compareTo(a.a + a.b),
      (a, b) => b.a.compareTo(a.a),
      (a, b) => b.b.compareTo(a.b),
      (a, b) => _aspectRatio(b).compareTo(_aspectRatio(a)),
    ];

    for (final compare in comparators) {
      final ordered = [...parts]..sort((a, b) {
          final primary = compare(a, b);
          if (primary != 0) return primary;
          final longSide = math.max(b.a, b.b).compareTo(math.max(a.a, a.b));
          if (longSide != 0) return longSide;
          final area = (b.a * b.b).compareTo(a.a * a.b);
          return area != 0 ? area : a.name.compareTo(b.name);
        });
      orders.add(ordered);
      orders.add(ordered.reversed.toList());
    }

    return orders;
  }

  static double _aspectRatio(Part part) {
    final shortSide = math.min(part.a, part.b);
    return shortSide <= 0 ? 0 : math.max(part.a, part.b) / shortSide;
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
        selectedSheet = SheetLayout(
            sheets.length + 1, [], project.stock.width, project.stock.height, 0,
            stockName: project.stock.name, stockId: project.stock.id);
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
          assemblyName: part.assemblyName,
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

  static double _sheetEdgeWasteScore(List<SheetLayout> sheets) =>
      sheets.fold<double>(0, (score, sheet) {
        var maxX = 0.0;
        var maxY = 0.0;
        for (final part in sheet.placements) {
          maxX = math.max(maxX, part.x + part.w);
          maxY = math.max(maxY, part.y + part.h);
        }
        final boundingWaste = math.max(0, maxX * maxY - sheet.usedArea);
        final edgeSlack = (sheet.stockW - maxX) * (sheet.stockH - maxY);
        return score + boundingWaste + edgeSlack;
      });

  static PlacedPart? _findSpot(List<PlacedPart> placed, Part part, double maxW,
      double maxH, double kerf) {
    final candidates = <Offset>[const Offset(0, 0)];
    for (final existing in placed) {
      candidates.add(Offset(existing.x + existing.w + kerf, existing.y));
      candidates.add(Offset(existing.x, existing.y + existing.h + kerf));
    }
    PlacedPart? best;
    var bestScore = double.infinity;
    for (final point in candidates) {
      for (final rotated in [false, true]) {
        if (rotated && (!part.rotate || part.a == part.b)) continue;
        final w = rotated ? part.b : part.a;
        final h = rotated ? part.a : part.b;
        if (point.dx + w > maxW || point.dy + h > maxH) continue;

        final rect = Rect.fromLTWH(point.dx, point.dy, w + kerf, h + kerf);
        final collision = placed.any((old) => rect
            .overlaps(Rect.fromLTWH(old.x, old.y, old.w + kerf, old.h + kerf)));
        if (collision) continue;

        var boundsW = point.dx + w;
        var boundsH = point.dy + h;
        for (final old in placed) {
          boundsW = math.max(boundsW, old.x + old.w);
          boundsH = math.max(boundsH, old.y + old.h);
        }
        final boundsArea = boundsW * boundsH;
        final shortSideSlack =
            math.min(maxW - point.dx - w, maxH - point.dy - h);
        final score = boundsArea + shortSideSlack * 0.001;
        if (score >= bestScore) continue;
        bestScore = score;
        best = PlacedPart(part.name, point.dx, point.dy, w, h,
            rotated: rotated,
            partId: part.id,
            pieceIndex: part.pieceIndex ?? 0);
      }
    }
    return best;
  }
}
