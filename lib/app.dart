// Copyright (C) 2026 Tendai Shoko
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:cut_optimiser/domain/cut_optimiser_models.dart';
import 'package:cut_optimiser/domain/cutting_engine.dart';
import 'package:cut_optimiser/ui/cut_optimiser_widgets.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CutOptimiserApp());

class CutOptimiserApp extends StatefulWidget {
  const CutOptimiserApp({super.key});

  @override
  State<CutOptimiserApp> createState() => _CutOptimiserAppState();
}

class _CutOptimiserAppState extends State<CutOptimiserApp> {
  static const _themeModeKey = 'cut_optimiser_theme_mode_v1';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    final themeMode = ThemeMode.values.where((mode) => mode.name == savedMode);
    if (themeMode.isNotEmpty && mounted) {
      setState(() => _themeMode = themeMode.first);
    }
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    setState(() => _themeMode = themeMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, themeMode.name);
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: orange,
      primary: orange,
      brightness: brightness,
      surface: dark ? const Color(0xFF182638) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: dark ? const Color(0xFF101B2A) : canvas,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: dark ? const Color(0xFF34465A) : const Color(0xFFE3E8EE),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF101B2A) : const Color(0xFFF7F9FB),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF405268) : const Color(0xFFDCE3EA),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF405268) : const Color(0xFFDCE3EA),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Cut Optimiser',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: _themeMode,
        home: AppShell(
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
        ),
      );
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    'Reports',
    'About',
  ];
  final List<IconData> _icons = [
    Icons.dashboard_outlined,
    Icons.folder_open_outlined,
    Icons.inventory_2_outlined,
    Icons.view_list_outlined,
    Icons.auto_awesome_outlined,
    Icons.grid_view_outlined,
    Icons.description_outlined,
    Icons.info_outline,
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
                Text(
                  'Stock quantity = 0 lets the solver calculate the requirement. Dimensions use the selected unit consistently.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
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
    final name =
        TextEditingController(text: original?.name ?? 'New stock type');
    final width =
        TextEditingController(text: (original?.width ?? 6000).toString());
    final height = TextEditingController(
        text: (original?.height ?? (_active?.mode == CutMode.sheet ? 1220 : 0))
            .toString());
    final quantity =
        TextEditingController(text: (original?.quantity ?? 0).toString());
    final price =
        TextEditingController(text: (original?.price ?? 0).toString());
    final kerf = TextEditingController(
        text: (original?.kerf ?? _active?.kerf ?? 3).toString());
    final trim = TextEditingController(
        text: (original?.trim ?? _active?.trim ?? 0).toString());
    final p = _active!;
    return showDialog<StockConfig>(
        context: context,
        builder: (context) => AlertDialog(
              title:
                  Text(original == null ? 'Add stock type' : 'Edit stock type'),
              content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'Stock type / profile name')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: width,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: p.mode == CutMode.linear
                                ? 'Stock length (${p.unit})'
                                : 'Sheet width (${p.unit})')),
                    if (p.mode == CutMode.sheet) ...[
                      const SizedBox(height: 10),
                      TextField(
                          controller: height,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: 'Sheet height (${p.unit})'))
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: quantity,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Available qty (0 = auto)'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: price,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Cost per unit')))
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: kerf,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: 'Cut kerf (${p.unit})'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: trim,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: 'Edge trim (${p.unit})')))
                    ]),
                  ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      final w = _num(width.text, 0);
                      final h =
                          p.mode == CutMode.sheet ? _num(height.text, 0) : 0.0;
                      final q = int.tryParse(quantity.text) ?? 0;
                      if (name.text.trim().isEmpty ||
                          w <= 0 ||
                          (p.mode == CutMode.sheet && h <= 0) ||
                          q < 0) {
                        return;
                      }
                      Navigator.pop(
                          context,
                          StockConfig(
                              id: original?.id,
                              name: name.text.trim(),
                              width: w,
                              height: h,
                              quantity: q,
                              price: _num(price.text, 0),
                              kerf: _num(kerf.text, 0),
                              trim: _num(trim.text, 0)));
                    },
                    child: const Text('Save stock'))
              ],
            ));
  }

  Future<void> _manageStocks() async {
    final p = _active;
    if (p == null) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, refresh) => AlertDialog(
                  title: const Text('Stock types'),
                  content: SizedBox(
                      width: 520,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: ListView(shrinkWrap: true, children: [
                          for (final stock in p.stocks)
                            ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(stock.name),
                              subtitle: Text(p.mode == CutMode.linear
                                  ? '${stock.width} ${p.unit} • Qty ${stock.quantity == 0 ? 'auto' : stock.quantity} • Kerf/trim ${stock.kerf}/${stock.trim}'
                                  : '${stock.width} × ${stock.height} ${p.unit} • Qty ${stock.quantity == 0 ? 'auto' : stock.quantity} • Kerf/trim ${stock.kerf}/${stock.trim}'),
                              trailing: Wrap(children: [
                                IconButton(
                                    tooltip: 'Edit stock type',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final updated = await _stockEditor(stock);
                                      if (updated != null) {
                                        final i = p.stocks.indexWhere(
                                            (s) => s.id == stock.id);
                                        if (i >= 0) p.stocks[i] = updated;
                                        refresh(() {});
                                      }
                                    }),
                                IconButton(
                                    tooltip: 'Remove stock type',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: p.stocks.length <= 1
                                        ? null
                                        : () {
                                            final replacement = p.stocks
                                                .firstWhere(
                                                    (s) => s.id != stock.id);
                                            for (final part in p.parts.where(
                                                (part) =>
                                                    part.stockId == stock.id)) {
                                              part.stockId = replacement.id;
                                            }
                                            p.stocks.removeWhere(
                                                (s) => s.id == stock.id);
                                            refresh(() {});
                                          })
                              ]),
                            )
                        ])),
                        const SizedBox(height: 8),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                                onPressed: () async {
                                  final stock = await _stockEditor(null);
                                  if (stock != null) {
                                    p.stocks.add(stock);
                                    refresh(() {});
                                  }
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add stock type'))),
                        const SizedBox(height: 4),
                        Text(
                            'Each part is optimised only against its assigned stock type.',
                            style: TextStyle(
                                color: Theme.of(dialogContext)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12)),
                      ])),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Done'))
                  ],
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
                  items: [
                    for (final stock in p.stocks)
                      DropdownMenuItem(value: stock.id, child: Text(stock.name))
                  ],
                  onChanged: (value) => refresh(
                      () => selectedStockId = value ?? p.stocks.first.id),
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

  Future<void> _togglePartCut(PlacedPart part) async {
    await _togglePartsCut([part]);
  }

  Future<void> _togglePartsCut(Iterable<PlacedPart> parts) async {
    final project = _active;
    final pieces = parts.toList();
    if (project == null || pieces.isEmpty) return;
    setState(() {
      final markCut = !pieces.first.isCut;
      for (final part in pieces) {
        if (markCut) {
          project.cutPieces.add(part.cutKey);
        } else {
          project.cutPieces.remove(part.cutKey);
        }
      }
      project.updated = _date();
      _result = CuttingEngine.solve(project);
    });
    await _save();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  double _trimForStock(Project project, String stockName) => project.stocks
      .firstWhere((stock) => stock.name == stockName,
          orElse: () => project.stock)
      .trim;

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
          rows.add([
            '${s.stockName} - Bar ${s.index}',
            c.name,
            c.x,
            0,
            c.w,
            '',
            false
          ]);
        }
      }
    } else {
      for (final s in r.sheets) {
        for (final c in s.placements) {
          rows.add([
            '${s.stockName} - Sheet ${s.index}',
            c.name,
            c.x,
            c.y,
            c.w,
            c.h,
            c.rotated
          ]);
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
          pw.Text(
              'Mode: ${p.mode.name} • Stock types: ${p.stocks.map((s) => s.name).join(', ')}'),
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
              [
                'Stock-specific kerf',
                p.stocks.map((s) => '${s.name}: ${s.kerf} ${p.unit}').join('; ')
              ],
              [
                'Stock-specific trim',
                p.stocks.map((s) => '${s.name}: ${s.trim} ${p.unit}').join('; ')
              ],
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 920;
    final compact = screenWidth < 600;
    final useNavigationDrawer =
        !wide && defaultTargetPlatform == TargetPlatform.android;
    final content = _buildPage();
    final heading = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _pages[_page],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          _active == null
              ? 'Create a project to get started'
              : '${_active!.name}  •  ${_active!.material} / ${_active!.variant}',
          maxLines: 1,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final actions = <Widget>[
      if (_active != null)
        if (compact)
          IconButton(
            tooltip: 'Configure',
            onPressed: _editProject,
            icon: const Icon(Icons.tune),
          )
        else
          OutlinedButton.icon(
            onPressed: _editProject,
            icon: const Icon(Icons.tune, size: 17),
            label: const Text('Configure'),
          ),
      if (compact)
        IconButton.filled(
          tooltip: 'New project',
          onPressed: _newProject,
          icon: const Icon(Icons.add),
        )
      else
        FilledButton.icon(
          onPressed: _newProject,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New project'),
        ),
    ];
    return Scaffold(
        key: _scaffoldKey,
        drawer: useNavigationDrawer ? _navigationDrawer() : null,
        body: SafeArea(
            top: true,
            bottom: false,
            child: Row(children: [
              if (wide) _sidebar(),
              Expanded(
                  child: Column(children: [
                if (!wide)
                  _mobileHeader(useNavigationDrawer: useNavigationDrawer),
                Container(
                  height: compact ? 90 : 68,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 24,
                    vertical: compact ? 6 : 0,
                  ),
                  color: Theme.of(context).colorScheme.surface,
                  child: compact
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(child: heading),
                                ...actions,
                              ],
                            ),
                          ],
                        )
                      : Row(children: [
                          Expanded(child: heading),
                          if (_active != null)
                            OutlinedButton.icon(
                              onPressed: _editProject,
                              icon: const Icon(Icons.tune, size: 17),
                              label: const Text('Configure'),
                            ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _newProject,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New project'),
                          ),
                        ]),
                ),
                Expanded(
                    child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: SingleChildScrollView(
                            key: ValueKey(_page),
                            padding: EdgeInsets.all(compact ? 12 : 22),
                            child: content)))
              ]))
            ])));
  }

  Widget _mobileHeader({required bool useNavigationDrawer}) => Container(
      height: 56,
      color: ink,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        if (useNavigationDrawer)
          IconButton(
            tooltip: 'Open navigation menu',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
        const SawBladeIcon(size: 22, bladeColor: orange, hubColor: ink),
        const SizedBox(width: 10),
        const Text('CUT OPTIMISER',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const Spacer(),
        if (!useNavigationDrawer)
          PopupMenuButton<int>(
              iconColor: Colors.white,
              onSelected: _selectPage,
              itemBuilder: (_) => [
                    for (var i = 0; i < _pages.length; i++)
                      PopupMenuItem(value: i, child: Text(_pages[i]))
                  ])
      ]));

  Widget _navigationDrawer() => Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                color: ink,
                child: const Row(
                  children: [
                    SawBladeIcon(size: 28, bladeColor: orange, hubColor: ink),
                    SizedBox(width: 12),
                    Text(
                      'CUT OPTIMISER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'WORKSPACE',
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      ListTile(
                        selected: _page == i,
                        selectedColor: orange,
                        selectedTileColor: const Color(0xFFFFF1E7),
                        leading: Icon(_icons[i]),
                        title: Text(_pages[i]),
                        onTap: () {
                          Navigator.pop(context);
                          _selectPage(i);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

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
                  child: const SawBladeIcon(
                      size: 22, bladeColor: ink, hubColor: orange)),
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
        Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
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
        ])),
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
      case 6:
        return _reportsPage();
      case 7:
        return _aboutPage();
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
        final cards = [
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
        ];
        if (n == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                card,
                const SizedBox(height: 12),
              ],
            ],
          );
        }
        return GridView.count(
            crossAxisCount: n,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: cards);
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
                            isExpanded: true,
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
                          Text(
                            'This prototype stores projects locally on this device. There is no cloud account or shared team workspace.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                              height: 1.45,
                            ),
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
                            label: Text(
                                'Manage stock types (${_active!.stocks.length})')),
                        const SizedBox(height: 10),
                        for (final stock in _active!.stocks)
                          ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(stock.name),
                              subtitle: Text(_active!.mode == CutMode.linear
                                  ? 'Length ${stock.width} ${_active!.unit}'
                                  : '${stock.width} × ${stock.height} ${_active!.unit}'),
                              trailing: Text(stock.price == 0
                                  ? ''
                                  : stock.price.toStringAsFixed(2)))
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
                Text(
                  '${p.totalPieces} pcs',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                )
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
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12))),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)))),
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
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    Text(
                        'Stock: ${p.stocks.firstWhere((s) => s.id == part.stockId, orElse: () => p.stock).name}',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant))
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
      builder: (c) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: Text('Edit ${part.name}'),
                content: SizedBox(
                    width: 360,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: ctl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Quantity')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: stockId,
                        decoration:
                            const InputDecoration(labelText: 'Stock type'),
                        items: [
                          for (final stock in p.stocks)
                            DropdownMenuItem(
                                value: stock.id, child: Text(stock.name))
                        ],
                        onChanged: (value) =>
                            refresh(() => stockId = value ?? p.stocks.first.id),
                      ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Save')),
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
                childAspectRatio: n == 1 ? 3.3 : 1.8,
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
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
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
                  label: const Text('Diagram'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('CSV'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
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
          Builder(builder: (context) {
            final pieces = r.mode == CutMode.linear
                ? r.linear.expand((stick) => stick.cuts).toList()
                : r.sheets.expand((sheet) => sheet.placements).toList();
            final cutCount = pieces.where((part) => part.isCut).length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap a part in the diagram or list to mark it cut. '
                      '$cutCount of ${pieces.length} placed parts marked cut.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF34465A)
                    : const Color(0xFFE0E6EC),
              ),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: orange,
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  const Text('Uncut part', style: TextStyle(fontSize: 12)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: const Color(0xFF2F8D75),
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  const Text('Cut', style: TextStyle(fontSize: 12)),
                ]),
                Text(
                  'Dimensions in ${p.unit}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (r.mode == CutMode.linear) ...[
            for (final group in groupLinearDiagrams(
                r.linear, (stick) => _trimForStock(p, stick.stockName)))
              _linearDiagramCard(group, p),
          ] else ...[
            for (final group in groupSheetDiagrams(
                r.sheets, (sheet) => _trimForStock(p, sheet.stockName)))
              _sheetDiagramCard(group, p),
          ],
          const SizedBox(height: 12),
          const PrototypeNotice(),
        ],
      ],
    );
  }

  Widget _linearDiagramCard(List<LinearStick> group, Project project) {
    final stick = group.first;
    final trim = _trimForStock(project, stick.stockName);
    final barNumbers = group.map((item) => item.index).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.length == 1
                        ? '${stick.stockName} — Bar ${stick.index}'
                        : '${stick.stockName} — ${group.length} identical bars',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${stick.used.toStringAsFixed(1)} / ${(stick.stockLength - 2 * trim).toStringAsFixed(1)} ${project.unit}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (group.length > 1)
              Text(
                'Bars: $barNumbers',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final painter = LinearDiagramPainter(
                s: stick,
                unit: project.unit,
                trim: trim,
                isDark: Theme.of(context).brightness == Brightness.dark,
              );
              final size = Size(constraints.maxWidth, 74);
              return SizedBox(
                height: size.height,
                width: size.width,
                child: GestureDetector(
                  onTapUp: (details) {
                    final part = painter.partAt(size, details.localPosition);
                    if (part != null) {
                      final partIndex = stick.cuts.indexOf(part);
                      _togglePartsCut(
                          group.map((item) => item.cuts[partIndex]));
                    }
                  },
                  child: CustomPaint(size: size, painter: painter),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Offcut: ${stick.offcutLength(trim).toStringAsFixed(1)} ${project.unit}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in group)
                  for (final part in item.cuts)
                    FilterChip(
                      selected: part.isCut,
                      selectedColor: const Color(0xFFD9EEE7),
                      avatar: part.isCut
                          ? const Icon(Icons.check_circle,
                              size: 16, color: Color(0xFF2F8D75))
                          : null,
                      label: Text(
                          '${group.length > 1 ? 'Bar ${item.index}: ' : ''}${part.name}: ${part.w.toStringAsFixed(0)} ${project.unit}${part.isCut ? ' · Cut' : ''}',
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _togglePartCut(part),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetDiagramCard(List<SheetLayout> group, Project project) {
    final sheet = group.first;
    final trim = _trimForStock(project, sheet.stockName);
    final sheetNumbers = group.map((item) => item.index).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.length == 1
                        ? '${sheet.stockName} — Sheet ${sheet.index}'
                        : '${sheet.stockName} — ${group.length} identical sheets',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sheet.placements.length} pieces',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (group.length > 1)
              Text(
                'Sheets: $sheetNumbers',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final painter = SheetDiagramPainter(
                s: sheet,
                trim: trim,
                unit: project.unit,
                isDark: Theme.of(context).brightness == Brightness.dark,
              );
              final size = Size(constraints.maxWidth, 280);
              return SizedBox(
                height: size.height,
                width: size.width,
                child: GestureDetector(
                  onTapUp: (details) {
                    final part = painter.partAt(size, details.localPosition);
                    if (part != null) {
                      final partIndex = sheet.placements.indexOf(part);
                      _togglePartsCut(
                          group.map((item) => item.placements[partIndex]));
                    }
                  },
                  child: CustomPaint(size: size, painter: painter),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Unused stock area: ${sheet.unusedArea(trim).toStringAsFixed(1)} ${project.unit}²',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in group)
                  for (final part in item.placements)
                    FilterChip(
                      selected: part.isCut,
                      selectedColor: const Color(0xFFD9EEE7),
                      avatar: part.isCut
                          ? const Icon(Icons.check_circle,
                              size: 16, color: Color(0xFF2F8D75))
                          : null,
                      label: Text(
                          '${group.length > 1 ? 'Sheet ${item.index}: ' : ''}${part.name} · ${part.w.toStringAsFixed(0)}×${part.h.toStringAsFixed(0)}${part.isCut ? ' · Cut' : ''}',
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _togglePartCut(part),
                    ),
              ],
            ),
          ],
        ),
      ),
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
                      Text(
                          'PDF report includes project metadata, stock count, waste estimate, cut list and solver caveats. CSV provides row-level cut positions for spreadsheet or shop-floor workflows.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.5)),
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

  Widget _aboutPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('About Cut Optimiser',
            'Application details, limitations and license.'),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appearance',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('Choose whether the app follows your device theme.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<ThemeMode>(
                  key: ValueKey(widget.themeMode),
                  initialValue: widget.themeMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Theme'),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System default'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) widget.onThemeModeChanged(mode);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14)),
                          child: const Center(
                              child: SawBladeIcon(
                                  size: 32,
                                  bladeColor: orange,
                                  hubColor: ink))),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Cut Optimiser',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                                'A cross-platform planner for sheet and linear cutting.',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.45)),
                          ]))
                    ]))),
        const SizedBox(height: 14),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Application information',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      _infoLine('Version', '0.1.0+1'),
                      _infoLine(
                          'Cutting modes', 'Linear stock and sheet nesting'),
                      _infoLine('Storage',
                          'Projects are saved locally on this device'),
                      const SizedBox(height: 8),
                      const Text(
                          'Create and manage cutting projects, generate candidate layouts, track completed cuts, and export CSV or PDF production reports.',
                          style: TextStyle(height: 1.5)),
                    ]))),
        const SizedBox(height: 14),
        const PrototypeNotice(),
        const SizedBox(height: 14),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('License and copyright',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('Copyright (C) 2026 Tendai Shoko'),
                      const SizedBox(height: 8),
                      const Text(
                          'This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.'),
                      const SizedBox(height: 8),
                      const Text(
                          'This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.'),
                      const SizedBox(height: 8),
                      const Text(
                          'See the GNU General Public License for more details:'),
                      const SelectableText(
                          'https://www.gnu.org/licenses/gpl-3.0.html',
                          style: TextStyle(color: Color(0xFF467DC4))),
                    ]))),
      ]);

  Widget _infoLine(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(title,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12))),
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
      {required this.s,
      required this.unit,
      required this.trim,
      required this.isDark});
  final LinearStick s;
  final String unit;
  final double trim;
  final bool isDark;

  PlacedPart? partAt(Size size, Offset position) {
    const left = 8.0;
    final top = 22.0, width = size.width - 16, height = 28.0;
    final scale = width / s.stockLength;
    for (final part in s.cuts.reversed) {
      final rect =
          Rect.fromLTWH(left + part.x * scale, top, part.w * scale, height);
      if (rect.contains(position)) return part;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final left = 8.0, top = 22.0, width = size.width - 16, height = 28.0;
    final scale = width / s.stockLength;
    final base = Paint()
      ..color = isDark ? const Color(0xFF34465A) : const Color(0xFFE6EBF0);
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
      canvas.drawRect(
          rect,
          Paint()
            ..color =
                c.isCut ? const Color(0xFF2F8D75) : colors[i % colors.length]);
      if (c.isCut) {
        canvas.drawRect(
            rect,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
      if (rect.width > 30) {
        final tp = TextPainter(
            text: TextSpan(
                text: c.isCut ? '${c.name} ✓' : c.name,
                style: TextStyle(
                    fontSize: 10,
                    color: c.isCut ? Colors.white : ink,
                    fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…')
          ..layout(maxWidth: rect.width - 4);
        tp.paint(canvas, Offset(rect.left + 3, top + 8));
      }
    }
    final labelColor =
        isDark ? const Color(0xFFB4C0CF) : const Color(0xFF738195);
    final tp = TextPainter(
        text: TextSpan(
            text: '0', style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(left, top + 36));
    final end = TextPainter(
        text: TextSpan(
            text: '${s.stockLength.toStringAsFixed(0)} $unit',
            style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr)
      ..layout();
    end.paint(canvas, Offset(left + width - end.width, top + 36));
  }

  @override
  bool shouldRepaint(covariant LinearDiagramPainter oldDelegate) =>
      oldDelegate.s != s || oldDelegate.isDark != isDark;
}

class SheetDiagramPainter extends CustomPainter {
  SheetDiagramPainter(
      {required this.s,
      required this.trim,
      required this.unit,
      required this.isDark});
  final SheetLayout s;
  final double trim;
  final String unit;
  final bool isDark;

  PlacedPart? partAt(Size size, Offset position) {
    const margin = 18.0;
    final scale = math.min((size.width - 2 * margin) / s.stockW,
        (size.height - 2 * margin) / s.stockH);
    final w = s.stockW * scale, h = s.stockH * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    for (final part in s.placements.reversed) {
      final rect = Rect.fromLTWH(ox + (trim + part.x) * scale,
          oy + (trim + part.y) * scale, part.w * scale, part.h * scale);
      if (rect.contains(position)) return part;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 18.0;
    final scale = math.min((size.width - 2 * margin) / s.stockW,
        (size.height - 2 * margin) / s.stockH);
    final w = s.stockW * scale, h = s.stockH * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    canvas.drawRect(
        Rect.fromLTWH(ox, oy, w, h),
        Paint()
          ..color = isDark ? const Color(0xFF223448) : const Color(0xFFF8FAFC));
    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF9DABBC) : ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(ox, oy, w, h), borderPaint);
    if (trim > 0) {
      final inset = trim * scale;
      canvas.drawRect(
          Rect.fromLTWH(ox + inset, oy + inset, w - 2 * inset, h - 2 * inset),
          Paint()
            ..color = isDark ? const Color(0xFF60758C) : const Color(0xFFCBD5E1)
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
      canvas.drawRect(
          rect,
          Paint()
            ..color =
                p.isCut ? const Color(0xFF2F8D75) : colors[i % colors.length]);
      canvas.drawRect(
          rect,
          Paint()
            ..color = p.isCut ? Colors.white : const Color(0xFF405268)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (rect.width > 32 && rect.height > 22) {
        final text = TextPainter(
            text: TextSpan(
                text:
                    '${p.name}${p.isCut ? ' ✓' : ''}\n${p.w.toStringAsFixed(0)}×${p.h.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: math.min(11, math.max(7, scale * 13)),
                    color: p.isCut ? Colors.white : ink,
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
            style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? const Color(0xFFB4C0CF)
                    : const Color(0xFF738195))),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(ox, math.max(0, oy - 14)));
  }

  @override
  bool shouldRepaint(covariant SheetDiagramPainter oldDelegate) =>
      oldDelegate.s != s || oldDelegate.isDark != isDark;
}
