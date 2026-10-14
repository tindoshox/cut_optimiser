import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ink = Color(0xFF101B2A);
const panel = Color(0xFF182638);
const orange = Color(0xFFFF812D);
const canvas = Color(0xFFF2F5F8);
const muted = Color(0xFF738195);

void main() => runApp(const CutOptimiserApp());

class CutOptimiserApp extends StatelessWidget {
  const CutOptimiserApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Cut Optimiser',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: canvas,
          colorScheme: ColorScheme.fromSeed(
              seedColor: orange, primary: orange, surface: Colors.white),
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              elevation: 0),
          cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE3E8EE)))),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F9FB),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFDCE3EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFDCE3EA))),
          ),
        ),
        home: const AppShell(),
      );
}

enum CutMode { linear, sheet }

class Part {
  Part(
      {required this.name,
      required this.a,
      this.b = 0,
      this.quantity = 1,
      this.rotate = true,
      this.stockId = ''});
  String name;
  double a;
  double b;
  int quantity;
  bool rotate;
  String stockId;
  Map<String, dynamic> toJson() => {
        'name': name, 'a': a, 'b': b, 'quantity': quantity,
        'rotate': rotate, 'stockId': stockId
      };
  factory Part.fromJson(Map<String, dynamic> j) => Part(
      name: j['name'] ?? 'Part',
      a: (j['a'] as num).toDouble(),
      b: (j['b'] as num? ?? 0).toDouble(),
      quantity: j['quantity'] ?? 1,
      rotate: j['rotate'] ?? true,
      stockId: j['stockId']?.toString() ?? '');
}

class StockConfig {
  StockConfig(
      {String? id,
      this.name = 'Mild steel 25×25×1.6',
      this.width = 6000,
      this.height = 0,
      this.quantity = 0,
      this.price = 0,
      this.kerf = 3,
      this.trim = 0}) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
  String name;
  double width;
  double height;
  int quantity; // zero = calculate required quantity
  double price;
  double kerf;
  double trim;
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'width': width, 'height': height,
        'quantity': quantity, 'price': price, 'kerf': kerf, 'trim': trim
      };
  factory StockConfig.fromJson(Map<String, dynamic> j) => StockConfig(
      id: j['id']?.toString(),
      name: j['name'] ?? 'Stock',
      width: (j['width'] as num? ?? 6000).toDouble(),
      height: (j['height'] as num? ?? 0).toDouble(),
      quantity: j['quantity'] ?? 0,
      price: (j['price'] as num? ?? 0).toDouble(),
      kerf: (j['kerf'] as num? ?? 3).toDouble(),
      trim: (j['trim'] as num? ?? 0).toDouble());
}

class Project {
  Project({
    required this.name,
    this.mode = CutMode.linear,
    this.material = 'Mild steel',
    this.variant = '25×25×1.6 mm',
    this.unit = 'mm',
    this.kerf = 3,
    this.trim = 0,
    List<Part>? parts,
    StockConfig? stock,
    List<StockConfig>? stocks,
    this.updated = '',
  })  : parts = parts ?? [],
        stocks = stocks ?? [stock ?? StockConfig()],
        id = DateTime.now().microsecondsSinceEpoch.toString() {
    _assignDefaultStock();
  }

  Project._({
    required this.id, required this.name, required this.mode,
    required this.material, required this.variant, required this.unit,
    required this.kerf, required this.trim, required this.parts,
    required this.stocks, required this.updated,
  }) { _assignDefaultStock(); }

  final String id;
  String name;
  CutMode mode;
  String material;
  String variant;
  String unit;
  double kerf;
  double trim;
  List<Part> parts;
  List<StockConfig> stocks;
  String updated;

  // Backwards-compatible convenience accessor for legacy UI and saved projects.
  StockConfig get stock => stocks.first;
  set stock(StockConfig value) {
    if (stocks.isEmpty) { stocks = [value]; } else { stocks[0] = value; }
    _assignDefaultStock();
  }

  void _assignDefaultStock() {
    if (stocks.isEmpty) stocks.add(StockConfig());
    for (final part in parts) {
      if (!stocks.any((stock) => stock.id == part.stockId)) {
        part.stockId = stocks.first.id;
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'mode': mode.name, 'material': material,
    'variant': variant, 'unit': unit, 'kerf': kerf, 'trim': trim,
    'parts': parts.map((p) => p.toJson()).toList(),
    'stocks': stocks.map((s) => s.toJson()).toList(),
    // Keep legacy key for compatibility with older app builds.
    'stock': stock.toJson(), 'updated': updated,
  };

  factory Project.fromJson(Map<String, dynamic> j) {
    final stockList = (j['stocks'] as List?)
        ?.map((e) => StockConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final legacyStock = StockConfig.fromJson(
        Map<String, dynamic>.from(j['stock'] ?? {'width': 6000}));
    final stocks = (stockList == null || stockList.isEmpty)
        ? <StockConfig>[legacyStock] : stockList;
    if (stockList == null || stockList.isEmpty) {
      legacyStock.kerf = (j['kerf'] as num? ?? 3).toDouble();
      legacyStock.trim = (j['trim'] as num? ?? 0).toDouble();
    }
    final parts = ((j['parts'] as List?) ?? [])
        .map((e) => Part.fromJson(Map<String, dynamic>.from(e))).toList();
    for (final part in parts) {
      if (part.stockId.isEmpty || !stocks.any((s) => s.id == part.stockId)) {
        part.stockId = stocks.first.id;
      }
    }
    return Project._(
      id: j['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: j['name'] ?? 'Untitled',
      mode: CutMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => CutMode.linear),
      material: j['material'] ?? 'Mild steel', variant: j['variant'] ?? '',
      unit: j['unit'] ?? 'mm', kerf: (j['kerf'] as num? ?? 3).toDouble(),
      trim: (j['trim'] as num? ?? 0).toDouble(), parts: parts,
      stocks: stocks, updated: j['updated'] ?? '',
    );
  }
  int get totalPieces => parts.fold(0, (sum, p) => sum + p.quantity);
}

class LinearStick {
  LinearStick(this.index, this.cuts, this.used, this.stockLength, {this.stockName = 'Stock'});
  String stockName;
  int index;
  List<PlacedPart> cuts;
  double used;
  double stockLength;
}

class PlacedPart {
  PlacedPart(this.name, this.x, this.y, this.w, this.h, {this.rotated = false});
  final String name;
  final double x, y, w, h;
  final bool rotated;
}

class SheetLayout {
  SheetLayout(
      this.index, this.placements, this.stockW, this.stockH, this.usedArea, {this.stockName = 'Stock'});
  final String stockName;
  final int index;
  final List<PlacedPart> placements;
  final double stockW, stockH;
  double usedArea;
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
  static SolveResult solve(Project p) {
    final allLinear = <LinearStick>[];
    final allSheets = <SheetLayout>[];
    final notes = <String>[];
    var demand = 0.0;
    var stockArea = 0.0;
    for (final stock in p.stocks) {
      final assigned = p.parts.where((part) => part.stockId == stock.id).toList();
      if (assigned.isEmpty) continue;
      final sub = Project(name: p.name, mode: p.mode, material: p.material,
        variant: p.variant, unit: p.unit, kerf: stock.kerf, trim: stock.trim,
        parts: assigned, stock: stock);
      final result = p.mode == CutMode.linear ? _linear(sub) : _sheets(sub);
      demand += result.demandArea;
      stockArea += result.totalStockArea;
      notes.addAll(result.notes.map((n) => '${stock.name}: $n'));
      if (p.mode == CutMode.linear) {
        for (var i = 0; i < result.linear.length; i++) {
          final layout = result.linear[i];
          layout.stockName = stock.name;
          layout.index = allLinear.length + 1;
          allLinear.add(layout);
        }
      } else {
        for (var i = 0; i < result.sheets.length; i++) {
          final layout = result.sheets[i];
          // Give sheets a project-wide index while retaining their stock format.
          final combined = SheetLayout(allSheets.length + 1, layout.placements,
              layout.stockW, layout.stockH, layout.usedArea, stockName: stock.name);
          allSheets.add(combined);
        }
      }
    }
    return SolveResult(mode: p.mode, linear: allLinear, sheets: allSheets,
      demandArea: demand, totalStockArea: stockArea, notes: notes);
  }

  static SolveResult _linear(Project p) {
    final items = <Part>[];
    for (final part in p.parts) {
      for (var i = 0; i < part.quantity; i++) {
        items.add(Part(name: part.name, a: part.a));
      }
    }
    items.sort((a, b) => b.a.compareTo(a.a));
    final usable = p.stock.width - p.trim * 2;
    final sticks = <LinearStick>[];
    for (final item in items) {
      if (item.a <= 0 || item.a > usable) continue;
      LinearStick? best;
      var bestRemaining = double.infinity;
      for (final stick in sticks) {
        final nextUsed =
            stick.used + item.a + (stick.cuts.isEmpty ? 0 : p.kerf);
        final rem = usable - nextUsed;
        if (rem >= -0.000001 && rem < bestRemaining) {
          best = stick;
          bestRemaining = rem;
        }
      }
      if (best == null) {
        best = LinearStick(sticks.length + 1, [], 0, p.stock.width);
        sticks.add(best);
      }
      final x = p.trim + best.used + (best.cuts.isEmpty ? 0 : p.kerf);
      best.cuts.add(PlacedPart(item.name, x, 0, item.a, 1));
      best.used += item.a + (best.cuts.length == 1 ? 0 : p.kerf);
    }
    final totalDemand = items.fold<double>(0, (s, i) => s + i.a);
    final totalStock = sticks.length * usable;
    final notes = <String>[
      'Heuristic: best-fit decreasing; not a proof of global optimality.'
    ];
    final oversized = p.parts.where((part) => part.a > usable).toList();
    if (oversized.isNotEmpty) {
      notes.add(
          'Infeasible parts skipped (longer than usable stock): ${oversized.map((e) => e.name).join(', ')}.');
    }
    if (p.stock.quantity > 0 && sticks.length > p.stock.quantity) {
      notes.add(
          'Required stock exceeds configured available quantity (${p.stock.quantity}).');
    }
    return SolveResult(
        mode: CutMode.linear,
        linear: sticks,
        sheets: [],
        demandArea: totalDemand,
        totalStockArea: totalStock,
        notes: notes);
  }

  static SolveResult _sheets(Project p) {
    final parts = <Part>[];
    for (final part in p.parts) {
      for (var i = 0; i < part.quantity; i++) {
        parts.add(
            Part(name: part.name, a: part.a, b: part.b, rotate: part.rotate));
      }
    }
    parts.sort((a, b) => (b.a * b.b).compareTo(a.a * a.b));
    final usableW = p.stock.width - 2 * p.trim;
    final usableH = p.stock.height - 2 * p.trim;
    final sheets = <SheetLayout>[];
    for (final part in parts) {
      if (part.a <= 0 || part.b <= 0 || usableW <= 0 || usableH <= 0) continue;
      var placed = false;
      for (final sheet in sheets) {
        final spot =
            _findSpot(sheet.placements, part, usableW, usableH, p.kerf);
        if (spot != null) {
          sheet.placements.add(PlacedPart(
              part.name, spot.x, spot.y, spot.w, spot.h,
              rotated: spot.rotated));
          sheet.usedArea += part.a * part.b;
          placed = true;
          break;
        }
      }
      if (!placed) {
        final sheet = SheetLayout(
            sheets.length + 1, [], p.stock.width, p.stock.height, 0);
        final spot =
            _findSpot(sheet.placements, part, usableW, usableH, p.kerf);
        if (spot != null) {
          sheet.placements.add(PlacedPart(
              part.name, spot.x, spot.y, spot.w, spot.h,
              rotated: spot.rotated));
          sheet.usedArea += part.a * part.b;
          sheets.add(sheet);
        }
      }
    }
    final demandArea = parts.fold<double>(0, (s, p) => s + p.a * p.b);
    final totalArea = sheets.length * usableW * usableH;
    final notes = <String>[
      'Heuristic: area-sorted bottom-left placement; not a proof of global optimality.',
      'Layouts show geometric nesting only. Guillotine cut sequence and machine-specific constraints are not implemented.'
    ];
    final invalid = parts
        .where((part) => !(part.a <= usableW && part.b <= usableH ||
            (part.rotate && part.b <= usableW && part.a <= usableH)))
        .toList();
    if (invalid.isNotEmpty) {
      notes.add(
          'Parts that do not fit any sheet orientation were skipped: ${invalid.map((e) => e.name).join(', ')}.');
    }
    if (p.stock.quantity > 0 && sheets.length > p.stock.quantity) {
      notes.add(
          'Required sheets exceed configured available quantity (${p.stock.quantity}).');
    }
    return SolveResult(
        mode: CutMode.sheet,
        linear: [],
        sheets: sheets,
        demandArea: demandArea,
        totalStockArea: totalArea,
        notes: notes);
  }

  static PlacedPart? _findSpot(List<PlacedPart> placed, Part part, double maxW,
      double maxH, double kerf) {
    final candidates = <Offset>[const Offset(0, 0)];
    for (final p in placed) {
      candidates.add(Offset(p.x + p.w + kerf, p.y));
      candidates.add(Offset(p.x, p.y + p.h + kerf));
    }
    candidates
        .sort((a, b) => (a.dy * 100000 + a.dx).compareTo(b.dy * 100000 + b.dx));
    for (final point in candidates) {
      for (final rotated in [false, true]) {
        if (rotated && (!part.rotate || part.a == part.b)) continue;
        final w = rotated ? part.b : part.a, h = rotated ? part.a : part.b;
        if (point.dx + w > maxW || point.dy + h > maxH) continue;
        final rect = Rect.fromLTWH(point.dx, point.dy, w + kerf, h + kerf);
        final collision = placed.any((old) => rect
            .overlaps(Rect.fromLTWH(old.x, old.y, old.w + kerf, old.h + kerf)));
        if (!collision) {
          return PlacedPart(part.name, point.dx, point.dy, w, h,
              rotated: rotated);
        }
      }
    }
    return null;
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 0;
  bool _loading = true;
  final List<Project> _projects = [];
  final List<String> _pages = [
    'Dashboard',
    'Projects',
    'Materials & stock',
    'Parts list',
    'Optimisation results',
    'Cutting diagrams',
    'Reports'
  ];
  final List<IconData> _icons = [
    Icons.dashboard_outlined,
    Icons.folder_open_outlined,
    Icons.inventory_2_outlined,
    Icons.view_list_outlined,
    Icons.auto_awesome_outlined,
    Icons.grid_view_outlined,
    Icons.description_outlined
  ];
  Project? _active;
  SolveResult? _result;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cut_optimiser_projects_v1');
    if (raw != null) {
      try {
        _projects.addAll((jsonDecode(raw) as List)
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    if (_projects.isEmpty) {
      final sample = Project(
          name: 'Workshop — frame set',
          mode: CutMode.linear,
          material: 'Mild steel',
          variant: '25×25×1.6 mm',
          stock: StockConfig(name: '6 m bar', width: 6000, quantity: 0),
          parts: [
            Part(name: 'Upright', a: 1800, quantity: 4),
            Part(name: 'Cross rail', a: 920, quantity: 6),
            Part(name: 'Brace', a: 640, quantity: 4),
            Part(name: 'Short tab', a: 280, quantity: 8)
          ]);
      sample.updated = _date();
      _projects.add(sample);
      _active = sample;
      _result = CuttingEngine.solve(sample);
      await _save();
    } else {
      _active = _projects.first;
      _result = CuttingEngine.solve(_active!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cut_optimiser_projects_v1',
        jsonEncode(_projects.map((p) => p.toJson()).toList()));
  }

  String _date() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _newProject() async {
    final name = TextEditingController(text: 'New cutting job');
    var mode = CutMode.linear;

    final result = await showDialog<Project>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Create project'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Project name'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<CutMode>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Cutting mode'),
                  items: const [
                    DropdownMenuItem(
                        value: CutMode.linear,
                        child: Text('Linear stock — bars / profiles')),
                    DropdownMenuItem(
                        value: CutMode.sheet,
                        child: Text('Sheet material — panels / boards')),
                  ],
                  onChanged: (v) => refresh(() => mode = v ?? CutMode.linear),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) {
                  Navigator.pop(
                    context,
                    Project(
                      name: name.text.trim(),
                      mode: mode,
                      material:
                          mode == CutMode.linear ? 'Mild steel' : 'Plywood',
                      variant: mode == CutMode.linear
                          ? '25×25×1.6 mm'
                          : '18 mm birch',
                      stock: mode == CutMode.linear
                          ? StockConfig(name: '6 m bar', width: 6000)
                          : StockConfig(
                              name: '2440 × 1220 sheet',
                              width: 2440,
                              height: 1220),
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _projects.insert(0, result);
        _active = result;
        _result = null;
        _page = 1;
      });
      await _save();
    }
  }

  Future<void> _editProject() async {
    final p = _active;
    if (p == null) return;

    final name = TextEditingController(text: p.name);
    final material = TextEditingController(text: p.material);
    final variant = TextEditingController(text: p.variant);
    final stockName = TextEditingController(text: p.stock.name);
    final w = TextEditingController(text: p.stock.width.toStringAsFixed(0));
    final h = TextEditingController(text: p.stock.height.toStringAsFixed(0));
    final qty = TextEditingController(text: p.stock.quantity.toString());
    final kerf = TextEditingController(text: p.kerf.toString());
    final trim = TextEditingController(text: p.trim.toString());
    final price = TextEditingController(text: p.stock.price.toString());
    var unit = p.unit;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Project, material & stock'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Project name'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: material,
                        decoration:
                            const InputDecoration(labelText: 'Material type'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: variant,
                        decoration: const InputDecoration(
                            labelText: 'Variant / profile'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: stockName,
                  decoration:
                      const InputDecoration(labelText: 'Stock format name'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: w,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: p.mode == CutMode.linear
                              ? 'Stock length ($unit)'
                              : 'Sheet width ($unit)',
                        ),
                      ),
                    ),
                    if (p.mode == CutMode.sheet) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: h,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: 'Sheet height ($unit)'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Available stock qty (0 = auto)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Cost per stock unit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: kerf,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: 'Saw kerf ($unit)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: trim,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: 'Edge trim ($unit)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration:
                      const InputDecoration(labelText: 'Dimension unit'),
                  items: const [
                    DropdownMenuItem(
                        value: 'mm', child: Text('Millimetres (mm)')),
                    DropdownMenuItem(value: 'in', child: Text('Inches (in)')),
                  ],
                  onChanged: (v) => unit = v ?? 'mm',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Stock quantity = 0 lets the solver calculate the requirement. Dimensions use the selected unit consistently.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save changes')),
        ],
      ),
    );

    if (ok == true) {
      p.name = name.text.trim().isEmpty ? p.name : name.text.trim();
      p.material = material.text.trim();
      p.variant = variant.text.trim();
      p.stock.name = stockName.text.trim();
      p.stock.width = _num(w.text, p.stock.width);
      p.stock.height =
          p.mode == CutMode.sheet ? _num(h.text, p.stock.height) : 0;
      p.stock.quantity = int.tryParse(qty.text) ?? 0;
      p.stock.price = _num(price.text, 0);
      p.kerf = _num(kerf.text, 0);
      p.trim = _num(trim.text, 0);
      p.stock.kerf = p.kerf;
      p.stock.trim = p.trim;
      p.unit = unit;
      p.updated = _date();
      setState(() => _result = null);
      await _save();
    }
  }

  double _num(String s, double fallback) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? fallback;

  Future<StockConfig?> _stockEditor(StockConfig? existing) async {
    final original = existing;
    final name = TextEditingController(text: original?.name ?? 'New stock type');
    final width = TextEditingController(text: (original?.width ?? 6000).toString());
    final height = TextEditingController(text: (original?.height ?? (_active?.mode == CutMode.sheet ? 1220 : 0)).toString());
    final quantity = TextEditingController(text: (original?.quantity ?? 0).toString());
    final price = TextEditingController(text: (original?.price ?? 0).toString());
    final kerf = TextEditingController(text: (original?.kerf ?? _active?.kerf ?? 3).toString());
    final trim = TextEditingController(text: (original?.trim ?? _active?.trim ?? 0).toString());
    final p = _active!;
    return showDialog<StockConfig>(context: context, builder: (context) => AlertDialog(
      title: Text(original == null ? 'Add stock type' : 'Edit stock type'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Stock type / profile name')),
        const SizedBox(height: 10),
        TextField(controller: width, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: p.mode == CutMode.linear ? 'Stock length (${p.unit})' : 'Sheet width (${p.unit})')),
        if (p.mode == CutMode.sheet) ...[const SizedBox(height: 10), TextField(controller: height, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Sheet height (${p.unit})'))],
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Available qty (0 = auto)'))), const SizedBox(width: 10), Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost per unit')))]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: kerf, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Cut kerf (${p.unit})'))), const SizedBox(width: 10), Expanded(child: TextField(controller: trim, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Edge trim (${p.unit})')))]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () {
        final w = _num(width.text, 0); final h = p.mode == CutMode.sheet ? _num(height.text, 0) : 0.0;
        final q = int.tryParse(quantity.text) ?? 0;
        if (name.text.trim().isEmpty || w <= 0 || (p.mode == CutMode.sheet && h <= 0) || q < 0) return;
        Navigator.pop(context, StockConfig(id: original?.id, name: name.text.trim(), width: w, height: h, quantity: q, price: _num(price.text, 0), kerf: _num(kerf.text, 0), trim: _num(trim.text, 0)));
      }, child: const Text('Save stock'))],
    ));
  }

  Future<void> _manageStocks() async {
    final p = _active;
    if (p == null) return;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: const Text('Stock types'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: ListView(shrinkWrap: true, children: [for (final stock in p.stocks) ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(stock.name),
          subtitle: Text(p.mode == CutMode.linear ? '${stock.width} ${p.unit} • Qty ${stock.quantity == 0 ? 'auto' : stock.quantity} • Kerf/trim ${stock.kerf}/${stock.trim}' : '${stock.width} × ${stock.height} ${p.unit} • Qty ${stock.quantity == 0 ? 'auto' : stock.quantity} • Kerf/trim ${stock.kerf}/${stock.trim}'),
          trailing: Wrap(children: [IconButton(tooltip: 'Edit stock type', icon: const Icon(Icons.edit_outlined), onPressed: () async { final updated = await _stockEditor(stock); if (updated != null) { final i = p.stocks.indexWhere((s) => s.id == stock.id); if (i >= 0) p.stocks[i] = updated; refresh(() {}); } }), IconButton(tooltip: 'Remove stock type', icon: const Icon(Icons.delete_outline), onPressed: p.stocks.length <= 1 ? null : () { final replacement = p.stocks.firstWhere((s) => s.id != stock.id); for (final part in p.parts.where((part) => part.stockId == stock.id)) { part.stockId = replacement.id; } p.stocks.removeWhere((s) => s.id == stock.id); refresh(() {}); })]),
        )])),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () async { final stock = await _stockEditor(null); if (stock != null) { p.stocks.add(stock); refresh(() {}); } }, icon: const Icon(Icons.add), label: const Text('Add stock type'))),
        const SizedBox(height: 4),
        const Text('Each part is optimised only against its assigned stock type.', style: TextStyle(color: muted, fontSize: 12)),
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
    )));
    p.updated = _date();
    setState(() => _result = null);
    await _save();
  }

  Future<void> _addPart() async {
    final p = _active;
    if (p == null) return;

    final name = TextEditingController(
        text: p.mode == CutMode.linear ? 'Cut length' : 'Panel');
    final a =
        TextEditingController(text: p.mode == CutMode.linear ? '1000' : '600');
    final b =
        TextEditingController(text: p.mode == CutMode.linear ? '0' : '400');
    final q = TextEditingController(text: '1');
    var rotate = true;
    var selectedStockId = p.stocks.first.id;

    final part = await showDialog<Part>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Add part demand'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Part name'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedStockId,
                  decoration: const InputDecoration(labelText: 'Stock type'),
                  items: [for (final stock in p.stocks) DropdownMenuItem(value: stock.id, child: Text(stock.name))],
                  onChanged: (value) => refresh(() => selectedStockId = value ?? p.stocks.first.id),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: a,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: p.mode == CutMode.linear
                              ? 'Length (${p.unit})'
                              : 'Width (${p.unit})',
                        ),
                      ),
                    ),
                    if (p.mode == CutMode.sheet) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: b,
                          keyboardType: TextInputType.number,
                          decoration:
                              InputDecoration(labelText: 'Height (${p.unit})'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: q,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                if (p.mode == CutMode.sheet)
                  CheckboxListTile(
                    value: rotate,
                    onChanged: (v) => refresh(() => rotate = v ?? true),
                    title: const Text('Allow 90° rotation'),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final av = _num(a.text, 0);
                final bv = p.mode == CutMode.sheet ? _num(b.text, 0) : 0.0;
                final qv = int.tryParse(q.text) ?? 0;
                if (name.text.trim().isNotEmpty &&
                    av > 0 &&
                    (p.mode == CutMode.linear || bv > 0) &&
                    qv > 0) {
                  Navigator.pop(
                    context,
                    Part(
                        name: name.text.trim(),
                        a: av,
                        b: bv,
                        quantity: qv,
                        rotate: rotate,
                        stockId: selectedStockId),
                  );
                }
              },
              child: const Text('Add part'),
            ),
          ],
        ),
      ),
    );

    if (part != null) {
      setState(() {
        p.parts.add(part);
        p.updated = _date();
        _result = null;
      });
      await _save();
    }
  }

  Future<void> _optimise() async {
    if (_active == null) return;
    if (_active!.parts.isEmpty) {
      _toast('Add at least one part before optimising.');
      return;
    }
    setState(() => _result = CuttingEngine.solve(_active!));
    await _save();
    setState(() => _page = 4);
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  Future<void> _exportCsv() async {
    final p = _active;
    final r = _result;
    if (p == null || r == null) {
      _toast('Run optimisation first.');
      return;
    }
    final rows = <List<dynamic>>[
      ['Cut Optimiser — production cut list'],
      ['Project', p.name],
      ['Mode', p.mode.name],
      ['Material', p.material],
      ['Variant', p.variant],
      ['Status', 'Heuristic plan — optimality not proven'],
      [],
      [
        'Stock unit',
        'Part',
        'X / start',
        'Y',
        'Width / length',
        'Height',
        'Rotated'
      ]
    ];
    if (r.mode == CutMode.linear) {
      for (final s in r.linear) {
        for (final c in s.cuts) {
          rows.add(['${s.stockName} - Bar ${s.index}', c.name, c.x, 0, c.w, '', false]);
        }
      }
    } else {
      for (final s in r.sheets) {
        for (final c in s.placements) {
          rows.add(['${s.stockName} - Sheet ${s.index}', c.name, c.x, c.y, c.w, c.h, c.rotated]);
        }
      }
    }
    final content = const ListToCsvConverter().convert(rows);
    final location = await getSaveLocation(
        suggestedName:
            '${p.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_cut_list.csv');
    if (location == null) return;
    await XFile.fromData(Uint8List.fromList(utf8.encode(content)),
            mimeType: 'text/csv', name: 'cut_list.csv')
        .saveTo(location.path);
    _toast('CSV exported.');
  }

  Future<void> _exportPdf() async {
    final p = _active;
    final r = _result;
    if (p == null || r == null) {
      _toast('Run optimisation first.');
      return;
    }
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Text('Cut Optimiser — Production Report',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Project: ${p.name}'),
          pw.Text('Material: ${p.material} / ${p.variant}'),
          pw.Text('Mode: ${p.mode.name} • Stock types: ${p.stocks.map((s) => s.name).join(', ')}'),
          pw.Text('Generated: ${DateTime.now().toIso8601String()}'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(
                'Heuristic solution — optimality not proven. Verify all dimensions and machine constraints before cutting.'),
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['Stock units', '${r.stockCount}'],
              [
                'Demand',
                '${r.demandArea.toStringAsFixed(1)} ${p.unit}${p.mode == CutMode.sheet ? '²' : ''}'
              ],
              ['Estimated waste', '${(r.waste * 100).toStringAsFixed(1)}%'],
              ['Stock-specific kerf', p.stocks.map((s) => '${s.name}: ${s.kerf} ${p.unit}').join('; ')],
              ['Stock-specific trim', p.stocks.map((s) => '${s.name}: ${s.trim} ${p.unit}').join('; ')],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('Cut list',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (r.mode == CutMode.linear)
            pw.Table.fromTextArray(
              headers: ['Bar', 'Part', 'Start', 'Length'],
              data: [
                for (final s in r.linear)
                  for (final c in s.cuts)
                    [
                      '${s.stockName} ${s.index}',
                      c.name,
                      c.x.toStringAsFixed(1),
                      c.w.toStringAsFixed(1)
                    ]
              ],
            )
          else
            pw.Table.fromTextArray(
              headers: ['Sheet', 'Part', 'X', 'Y', 'W', 'H', 'Rotated'],
              data: [
                for (final s in r.sheets)
                  for (final c in s.placements)
                    [
                      '${s.stockName} ${s.index}',
                      c.name,
                      c.x.toStringAsFixed(1),
                      c.y.toStringAsFixed(1),
                      c.w.toStringAsFixed(1),
                      c.h.toStringAsFixed(1),
                      c.rotated ? 'Yes' : 'No'
                    ]
              ],
            ),
          pw.SizedBox(height: 12),
          pw.Text('Notes: ${r.notes.join(' ')}'),
        ],
      ),
    );
    await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: '${p.name}_production_report.pdf');
  }

  void _selectPage(int i) {
    setState(() => _page = i);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final content = _buildPage();
    return Scaffold(
        body: Row(children: [
      if (wide) _sidebar(),
      Expanded(
          child: Column(children: [
        if (!wide) _mobileHeader(),
        Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: Colors.white,
            child: Row(children: [
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_pages[_page],
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                    Text(
                        _active == null
                            ? 'Create a project to get started'
                            : '${_active!.name}  •  ${_active!.material} / ${_active!.variant}',
                        style: const TextStyle(color: muted, fontSize: 12),
                        overflow: TextOverflow.ellipsis)
                  ])),
              if (_active != null)
                OutlinedButton.icon(
                    onPressed: _editProject,
                    icon: const Icon(Icons.tune, size: 17),
                    label: const Text('Configure')),
              const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: _newProject,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New project'))
            ])),
        Expanded(
            child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: SingleChildScrollView(
                    key: ValueKey(_page),
                    padding: const EdgeInsets.all(22),
                    child: content)))
      ]))
    ]));
  }

  Widget _mobileHeader() => Container(
      height: 56,
      color: ink,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        const Icon(Icons.cut, color: orange),
        const SizedBox(width: 10),
        const Text('CUT OPTIMISER',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const Spacer(),
        PopupMenuButton<int>(
            iconColor: Colors.white,
            onSelected: _selectPage,
            itemBuilder: (_) => [
                  for (var i = 0; i < _pages.length; i++)
                    PopupMenuItem(value: i, child: Text(_pages[i]))
                ])
      ]));
  Widget _sidebar() => Container(
      width: 230,
      color: ink,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 16, 26),
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: orange, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.cut, color: ink, size: 22)),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('CUT\nOPTIMISER',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: 1.1)))
            ])),
        const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 0, 12),
            child: Text('WORKSPACE',
                style: TextStyle(
                    color: Color(0xFF8B9AAF),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold))),
        for (var i = 0; i < _pages.length; i++)
          InkWell(
              onTap: () => _selectPage(i),
              child: Container(
                  height: 46,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: _page == i
                          ? const Color(0xFF27394D)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: _page == i
                          ? const Border(
                              left: BorderSide(color: orange, width: 3))
                          : null),
                  child: Row(children: [
                    Icon(_icons[i],
                        size: 19,
                        color: _page == i ? orange : const Color(0xFFB4C0CF)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_pages[i],
                            style: TextStyle(
                                color: _page == i
                                    ? Colors.white
                                    : const Color(0xFFB4C0CF),
                                fontWeight: _page == i
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13)))
                  ]))),
        const Spacer(),
        Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: panel, borderRadius: BorderRadius.circular(12)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.offline_bolt_outlined, color: orange),
                  SizedBox(height: 8),
                  Text('OFFLINE-FIRST',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                  SizedBox(height: 4),
                  Text('Local projects saved on this device.',
                      style: TextStyle(
                          color: Color(0xFF9DABBC), fontSize: 11, height: 1.4))
                ]))
      ]));
  Widget _buildPage() {
    switch (_page) {
      case 0:
        return _dashboard();
      case 1:
        return _projectsPage();
      case 2:
        return _materialsPage();
      case 3:
        return _partsPage();
      case 4:
        return _resultsPage();
      case 5:
        return _diagramsPage();
      default:
        return _reportsPage();
    }
  }

  Widget _dashboard() {
    final pieces = _projects.fold<int>(0, (s, p) => s + p.totalPieces);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: SectionTitle('Production overview',
                'A practical workspace for sheet and linear cutting.')),
        FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.add),
            label: const Text('New project'))
      ]),
      const SizedBox(height: 18),
      LayoutBuilder(builder: (context, c) {
        final n = c.maxWidth > 1000
            ? 4
            : c.maxWidth > 600
                ? 2
                : 1;
        return GridView.count(
            crossAxisCount: n,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: n == 1 ? 4.1 : 1.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              MetricCard('Projects', '${_projects.length}',
                  Icons.folder_copy_outlined, orange),
              MetricCard('Part demand', '$pieces pcs', Icons.view_list_outlined,
                  const Color(0xFF2F8D75)),
              MetricCard(
                  'Material types',
                  '${_projects.map((p) => p.material).toSet().length}',
                  Icons.layers_outlined,
                  const Color(0xFF467DC4)),
              MetricCard(
                  'Latest plan',
                  _result == null
                      ? 'Not run'
                      : '${_result!.stockCount} stock units',
                  Icons.auto_awesome_outlined,
                  const Color(0xFF8A65C5))
            ]);
      }),
      const SizedBox(height: 22),
      const SectionTitle(
          'Recent projects', 'Open a job to continue editing or optimise.'),
      const SizedBox(height: 10),
      Card(
          child: Column(children: [
        for (final p in _projects.take(6))
          ListTile(
              leading: CircleAvatar(
                  backgroundColor: p.mode == CutMode.linear
                      ? const Color(0xFFFFE8D8)
                      : const Color(0xFFDDEBFF),
                  child: Icon(
                      p.mode == CutMode.linear
                          ? Icons.linear_scale
                          : Icons.grid_view,
                      color: p.mode == CutMode.linear
                          ? orange
                          : const Color(0xFF467DC4))),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${p.mode == CutMode.linear ? 'Linear' : 'Sheet'} • ${p.material} • ${p.totalPieces} parts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() {
                  _active = p;
                  _result = CuttingEngine.solve(p);
                  _page = 1;
                });
              })
      ])),
      const SizedBox(height: 18),
      const PrototypeNotice()
    ]);
  }

  Widget _projectsPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Project editor',
              'Choose a project, set its cutting mode, and maintain job details.'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: c.maxWidth > 700 ? (c.maxWidth - 14) / 2 : c.maxWidth,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active project',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _active?.id,
                            decoration: const InputDecoration(
                                labelText: 'Select project'),
                            items: [
                              for (final p in _projects)
                                DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name,
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (id) {
                              if (id != null) {
                                setState(() {
                                  _active =
                                      _projects.firstWhere((p) => p.id == id);
                                  _result = CuttingEngine.solve(_active!);
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          _infoLine(
                              'Project mode',
                              _active?.mode == CutMode.linear
                                  ? 'Linear stock'
                                  : 'Sheet nesting'),
                          _infoLine(
                              'Created / updated',
                              _active?.updated.isNotEmpty == true
                                  ? _active!.updated
                                  : 'Local draft'),
                          _infoLine(
                              'Demand lines', '${_active?.parts.length ?? 0}'),
                          _infoLine(
                              'Total pieces', '${_active?.totalPieces ?? 0}'),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _editProject,
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit settings'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _optimise,
                                  icon: const Icon(Icons.bolt),
                                  label: const Text('Optimise'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: c.maxWidth > 700 ? (c.maxWidth - 14) / 2 : c.maxWidth,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Job setup',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          _infoLine('Material', _active?.material ?? '—'),
                          _infoLine(
                              'Variant / profile', _active?.variant ?? '—'),
                          _infoLine('Stock format', _active?.stock.name ?? '—'),
                          _infoLine(
                            'Stock dimensions',
                            _active == null
                                ? '—'
                                : _active!.mode == CutMode.linear
                                    ? '${_active!.stock.width} ${_active!.unit}'
                                    : '${_active!.stock.width} × ${_active!.stock.height} ${_active!.unit}',
                          ),
                          _infoLine(
                            'Available quantity',
                            _active == null
                                ? '—'
                                : _active!.stock.quantity == 0
                                    ? 'Auto-calculate'
                                    : '${_active!.stock.quantity}',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'This prototype stores projects locally on this device. There is no cloud account or shared team workspace.',
                            style: TextStyle(
                                color: muted, fontSize: 12, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PrototypeNotice(),
        ],
      );
  Widget _materialsPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Materials & stock',
            'Material variant, stock format, quantity, kerf, trim and cost.'),
        const SizedBox(height: 14),
        if (_active == null)
          const EmptyState('No active project',
              'Create a project to configure material and stock.')
        else
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.inventory_2_outlined, color: orange),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(_active!.material,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18))),
                          StatusPill(_active!.mode == CutMode.linear
                              ? 'LINEAR'
                              : 'SHEET')
                        ]),
                        const SizedBox(height: 16),
                        _infoLine('Variant', _active!.variant),
                        _infoLine('Stock format', _active!.stock.name),
                        _infoLine(
                            _active!.mode == CutMode.linear
                                ? 'Stock length'
                                : 'Stock width',
                            '${_active!.stock.width} ${_active!.unit}'),
                        if (_active!.mode == CutMode.sheet)
                          _infoLine('Stock height',
                              '${_active!.stock.height} ${_active!.unit}'),
                        _infoLine(
                            'Available quantity',
                            _active!.stock.quantity == 0
                                ? 'Auto-calculate'
                                : '${_active!.stock.quantity}'),
                        _infoLine(
                            'Cost per stock unit',
                            _active!.stock.price == 0
                                ? 'Not specified'
                                : _active!.stock.price.toStringAsFixed(2)),
                        _infoLine('Kerf / edge trim',
                            '${_active!.kerf} / ${_active!.trim} ${_active!.unit}'),
                        const Divider(height: 28),
                        FilledButton.icon(
                            onPressed: _editProject,
                            icon: const Icon(Icons.tune),
                            label: const Text('Configure material & stock')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                            onPressed: _manageStocks,
                            icon: const Icon(Icons.category_outlined),
                            label: Text('Manage stock types (${_active!.stocks.length})')),
                        const SizedBox(height: 10),
                        for (final stock in _active!.stocks)
                          ListTile(dense: true, contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(stock.name),
                            subtitle: Text(_active!.mode == CutMode.linear
                              ? 'Length ${stock.width} ${_active!.unit}'
                              : '${stock.width} × ${stock.height} ${_active!.unit}'),
                            trailing: Text(stock.price == 0 ? '' : stock.price.toStringAsFixed(2)))
                      ]))),
        const SizedBox(height: 16),
        const PrototypeNotice()
      ]);
  Widget _partsPage() {
    final p = _active;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: SectionTitle(
                'Parts list', 'Enter each part size and demand quantity.')),
        FilledButton.icon(
            onPressed: p == null ? null : _addPart,
            icon: const Icon(Icons.add),
            label: const Text('Add part'))
      ]),
      const SizedBox(height: 14),
      if (p == null)
        const EmptyState('No active project', 'Create a project first.')
      else
        Card(
            child: Column(children: [
          Container(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                    child: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                StatusPill(p.mode == CutMode.linear ? 'LENGTHS' : 'RECTANGLES'),
                const SizedBox(width: 8),
                Text('${p.totalPieces} pcs',
                    style: const TextStyle(
                        color: muted, fontWeight: FontWeight.w700))
              ])),
          const Divider(height: 1),
          if (p.parts.isEmpty)
            const Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                    'No parts added yet. Use “Add part” to enter your cutting demand.'))
          else ...[for (var i = 0; i < p.parts.length; i++) _partRow(p, i)],
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${p.parts.length} demand lines • ${p.totalPieces} total pieces',
                        style: const TextStyle(color: muted, fontSize: 12))),
                OutlinedButton.icon(
                    onPressed: _addPart,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add part'))
              ]))
        ])),
      const SizedBox(height: 16),
      const PrototypeNotice()
    ]);
  }

  Widget _partRow(Project p, int i) {
    final part = p.parts[i];
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: canvas, borderRadius: BorderRadius.circular(8)),
              child: Center(
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: muted)))),
          const SizedBox(width: 12),
          Expanded(
              flex: 3,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(part.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        p.mode == CutMode.linear
                            ? 'Length ${part.a} ${p.unit}'
                            : '${part.a} × ${part.b} ${p.unit}${part.rotate ? ' • rotation allowed' : ''}',
                        style: const TextStyle(fontSize: 12, color: muted)),
                    Text('Stock: ${p.stocks.firstWhere((s) => s.id == part.stockId, orElse: () => p.stock).name}',
                        style: const TextStyle(fontSize: 12, color: muted))
                  ])),
          Text('× ${part.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
              tooltip: 'Edit quantity',
              onPressed: () => _editPartQuantity(p, part),
              icon: const Icon(Icons.edit_outlined, size: 18)),
          IconButton(
              tooltip: 'Remove part',
              onPressed: () async {
                setState(() {
                  p.parts.removeAt(i);
                  _result = null;
                });
                await _save();
              },
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFB65B4D)))
        ]));
  }

  Future<void> _editPartQuantity(Project p, Part part) async {
    final ctl = TextEditingController(text: '${part.quantity}');
    var stockId = part.stockId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('Edit ${part.name}'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: stockId,
            decoration: const InputDecoration(labelText: 'Stock type'),
            items: [for (final stock in p.stocks) DropdownMenuItem(value: stock.id, child: Text(stock.name))],
            onChanged: (value) => refresh(() => stockId = value ?? p.stocks.first.id),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      )),
    );
    if (ok == true) {
      final n = int.tryParse(ctl.text) ?? 0;
      if (n > 0) {
        setState(() {
          part.quantity = n;
          part.stockId = stockId;
          p.updated = _date();
          _result = null;
        });
        await _save();
      }
    }
  }

  Widget _resultsPage() {
    final r = _result;
    final p = _active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(
                'Optimisation results',
                'Heuristic cutting plan, material utilisation and proof status.',
              ),
            ),
            FilledButton.icon(
              onPressed: _optimise,
              icon: const Icon(Icons.bolt),
              label: const Text('Run optimiser'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (p == null)
          const EmptyState('No project selected', 'Select or create a project.')
        else if (r == null)
          EmptyState(
            'Plan not generated',
            'Add part demand, configure stock, then run the optimiser.',
            action: FilledButton.icon(
              onPressed: _optimise,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Optimise now'),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD5B4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFFB85C19)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feasible heuristic candidate — optimality not proven',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8E4513)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'The prototype uses deterministic placement heuristics. It does not run an exact solver or certify global optimality.',
                        style: TextStyle(
                            color: Color(0xFF8E4513),
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final n = c.maxWidth > 850
                  ? 4
                  : c.maxWidth > 560
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: n,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: n == 1 ? 4.5 : 1.8,
                children: [
                  MetricCard('Stock units', '${r.stockCount}',
                      Icons.inventory_2_outlined, orange),
                  MetricCard(
                    'Demand size',
                    '${r.demandArea.toStringAsFixed(0)} ${p.unit}${p.mode == CutMode.sheet ? '²' : ''}',
                    Icons.straighten,
                    const Color(0xFF467DC4),
                  ),
                  MetricCard(
                      'Estimated waste',
                      '${(r.waste * 100).toStringAsFixed(1)}%',
                      Icons.recycling_outlined,
                      const Color(0xFF2F8D75)),
                  MetricCard('Stock format', p.stock.name,
                      Icons.view_agenda_outlined, const Color(0xFF8A65C5)),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Run diagnostics',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  for (final note in r.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.circle, size: 7, color: orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.45, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _page = 5),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('View cutting diagrams'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Export CSV'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF report'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _diagramsPage() {
    final r = _result;
    final p = _active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Scaled cutting diagrams',
            'Proportional layouts for the generated candidate plan.'),
        const SizedBox(height: 14),
        if (p == null || r == null)
          EmptyState(
            'No cutting plan available',
            'Run the optimiser to generate layouts.',
            action: FilledButton(
              onPressed: _optimise,
              child: const Text('Optimise'),
            ),
          )
        else if (r.stockCount == 0)
          const EmptyState('No placements',
              'Check that part dimensions fit the configured stock.')
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E6EC)),
            ),
            child: Row(
              children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: orange, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                const Text('Part', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: const Color(0xFF6FB7A0),
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                const Text('Placed part', style: TextStyle(fontSize: 12)),
                const Spacer(),
                Text('Dimensions in ${p.unit}',
                    style: const TextStyle(color: muted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (r.mode == CutMode.linear) ...[
            for (final s in r.linear)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${s.stockName} — Bar ${s.index}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text(
                            '${s.used.toStringAsFixed(1)} / ${(s.stockLength - 2 * p.stocks.firstWhere((stock) => stock.name == s.stockName, orElse: () => p.stock).trim).toStringAsFixed(1)} ${p.unit}',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 74,
                        width: double.infinity,
                        child: CustomPaint(
                            painter: LinearDiagramPainter(
                                s: s, unit: p.unit, trim: p.stocks.firstWhere((stock) => stock.name == s.stockName, orElse: () => p.stock).trim)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in s.cuts)
                            Chip(
                              label: Text(
                                  '${c.name}: ${c.w.toStringAsFixed(0)} ${p.unit}',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            for (final s in r.sheets)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${s.stockName} — Sheet ${s.index}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text('${s.placements.length} pieces',
                              style:
                                  const TextStyle(color: muted, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        width: double.infinity,
                        child: CustomPaint(
                            painter: SheetDiagramPainter(
                                s: s, trim: p.stocks.firstWhere((stock) => stock.name == s.stockName, orElse: () => p.stock).trim, unit: p.unit)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in s.placements)
                            Chip(
                              label: Text(
                                  '${c.name} · ${c.w.toStringAsFixed(0)}×${c.h.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          const PrototypeNotice(),
        ],
      ],
    );
  }

  Widget _reportsPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Production reports',
            'Export a cut list for the workshop or a printable summary.'),
        const SizedBox(height: 14),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.description_outlined,
                          size: 36, color: orange),
                      const SizedBox(height: 12),
                      const Text('Production report',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 5),
                      const Text(
                          'PDF report includes project metadata, stock count, waste estimate, cut list and solver caveats. CSV provides row-level cut positions for spreadsheet or shop-floor workflows.',
                          style: TextStyle(color: muted, height: 1.5)),
                      const SizedBox(height: 18),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        FilledButton.icon(
                            onPressed: _exportPdf,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Print / save PDF')),
                        OutlinedButton.icon(
                            onPressed: _exportCsv,
                            icon: const Icon(Icons.table_chart),
                            label: const Text('Save CSV')),
                        OutlinedButton.icon(
                            onPressed: () => setState(() => _page = 4),
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('View results'))
                      ])
                    ]))),
        const SizedBox(height: 14),
        const PrototypeNotice()
      ]);
  Widget _infoLine(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(color: muted, fontSize: 12))),
        const SizedBox(width: 14),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))
      ]));
}

class LinearDiagramPainter extends CustomPainter {
  LinearDiagramPainter(
      {required this.s, required this.unit, required this.trim});
  final LinearStick s;
  final String unit;
  final double trim;
  @override
  void paint(Canvas canvas, Size size) {
    final left = 8.0, top = 22.0, width = size.width - 16, height = 28.0;
    final scale = width / s.stockLength;
    final base = Paint()..color = const Color(0xFFE6EBF0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, width, height), const Radius.circular(5)),
        base);
    final colors = [
      const Color(0xFF69B49B),
      const Color(0xFF8BB7E9),
      const Color(0xFFFFB16E),
      const Color(0xFFB2A1E2),
      const Color(0xFF7FC9D1)
    ];
    for (var i = 0; i < s.cuts.length; i++) {
      final c = s.cuts[i];
      final rect = Rect.fromLTWH(left + c.x * scale, top, c.w * scale, height);
      canvas.drawRect(rect, Paint()..color = colors[i % colors.length]);
      if (rect.width > 30) {
        final tp = TextPainter(
            text: TextSpan(
                text: c.name,
                style: const TextStyle(
                    fontSize: 10, color: ink, fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…')
          ..layout(maxWidth: rect.width - 4);
        tp.paint(canvas, Offset(rect.left + 3, top + 8));
      }
    }
    final tp = TextPainter(
        text: const TextSpan(
            text: '0', style: TextStyle(fontSize: 10, color: muted)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(left, top + 36));
    final end = TextPainter(
        text: TextSpan(
            text: '${s.stockLength.toStringAsFixed(0)} $unit',
            style: const TextStyle(fontSize: 10, color: muted)),
        textDirection: TextDirection.ltr)
      ..layout();
    end.paint(canvas, Offset(left + width - end.width, top + 36));
  }

  @override
  bool shouldRepaint(covariant LinearDiagramPainter oldDelegate) =>
      oldDelegate.s != s;
}

class SheetDiagramPainter extends CustomPainter {
  SheetDiagramPainter(
      {required this.s, required this.trim, required this.unit});
  final SheetLayout s;
  final double trim;
  final String unit;
  @override
  void paint(Canvas canvas, Size size) {
    const margin = 18.0;
    final scale = math.min((size.width - 2 * margin) / s.stockW,
        (size.height - 2 * margin) / s.stockH);
    final w = s.stockW * scale, h = s.stockH * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    canvas.drawRect(
        Rect.fromLTWH(ox, oy, w, h), Paint()..color = const Color(0xFFF8FAFC));
    final borderPaint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(ox, oy, w, h), borderPaint);
    if (trim > 0) {
      final inset = trim * scale;
      canvas.drawRect(
          Rect.fromLTWH(ox + inset, oy + inset, w - 2 * inset, h - 2 * inset),
          Paint()
            ..color = const Color(0xFFCBD5E1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round);
    }
    final colors = [
      const Color(0xFFFFC08A),
      const Color(0xFF91D1B7),
      const Color(0xFF9CC4F0),
      const Color(0xFFC2B3EA),
      const Color(0xFFF2D47E),
      const Color(0xFF9AD8DC)
    ];
    for (var i = 0; i < s.placements.length; i++) {
      final p = s.placements[i];
      final rect = Rect.fromLTWH(ox + (trim + p.x) * scale,
          oy + (trim + p.y) * scale, p.w * scale, p.h * scale);
      canvas.drawRect(rect, Paint()..color = colors[i % colors.length]);
      canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xFF405268)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (rect.width > 32 && rect.height > 22) {
        final text = TextPainter(
            text: TextSpan(
                text:
                    '${p.name}\n${p.w.toStringAsFixed(0)}×${p.h.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: math.min(11, math.max(7, scale * 13)),
                    color: ink,
                    fontWeight: FontWeight.w700)),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            ellipsis: '…')
          ..layout(maxWidth: rect.width - 4);
        text.paint(
            canvas,
            Offset(rect.center.dx - text.width / 2,
                rect.center.dy - text.height / 2));
      }
    }
    final tp = TextPainter(
        text: TextSpan(
            text:
                '${s.stockW.toStringAsFixed(0)} × ${s.stockH.toStringAsFixed(0)} $unit',
            style: const TextStyle(fontSize: 10, color: muted)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(ox, math.max(0, oy - 14)));
  }

  @override
  bool shouldRepaint(covariant SheetDiagramPainter oldDelegate) =>
      oldDelegate.s != s;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18, color: ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(fontSize: 12, color: muted, height: 1.4))
      ]);
}

class MetricCard extends StatelessWidget {
  const MetricCard(this.label, this.value, this.icon, this.color, {super.key});
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 5),
                  Text(value,
                      style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)
                ]))
          ])));
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFFFE8D8),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF9A4B17),
              fontSize: 9,
              letterSpacing: .6,
              fontWeight: FontWeight.w800)));
}

class PrototypeNotice extends StatelessWidget {
  const PrototypeNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFEAF0F6),
          borderRadius: BorderRadius.circular(10)),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.science_outlined, color: Color(0xFF50647B)),
        SizedBox(width: 10),
        Expanded(
            child: Text(
                'Prototype scope: local projects, basic heuristic optimisation, scaled diagrams and PDF/CSV exports are implemented. Exact optimality proof, advanced inventory/offcut reuse, guillotine cut sequencing, cloud sync, machine constraints and production-grade validation are placeholders / not implemented.',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF50647B), height: 1.5)))
      ]));
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.subtitle, {this.action, super.key});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(26),
          child: Center(
              child: Column(children: [
            const Icon(Icons.layers_clear_outlined, size: 34, color: muted),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12)),
            if (action != null) ...[const SizedBox(height: 14), action!]
          ]))));
}
