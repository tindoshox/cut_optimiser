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
import 'package:pdf/pdf.dart' as pdf;
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
  static const _projectsStorageKey = 'cut_optimiser_projects_v1';
  static const _stocksStorageKey = 'cut_optimiser_stocks_v1';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _page = 0;
  bool _loading = true;
  bool _showArchivedProjects = false;
  final List<Project> _projects = [];
  final List<StockConfig> _stockCatalog = [];
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
    final savedStocks = prefs.getString(_stocksStorageKey);
    if (savedStocks != null) {
      try {
        _stockCatalog.addAll((jsonDecode(savedStocks) as List).map(
            (entry) => StockConfig.fromJson(Map<String, dynamic>.from(entry))));
      } catch (error) {
        _toast('Saved stock catalog could not be read: $error');
      }
    }
    final raw = prefs.getString(_projectsStorageKey);
    if (raw != null) {
      try {
        _projects.addAll((jsonDecode(raw) as List)
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e))));
      } catch (error) {
        _toast('Saved projects could not be read: $error');
      }
    }
    for (final project in _projects) {
      for (final stock in project.stocks) {
        final index = _stockCatalog.indexWhere((item) => item.id == stock.id);
        if (index < 0) {
          _stockCatalog.add(stock);
        }
      }
      project.bindStocks(_stockCatalog);
    }
    if (_projects.isEmpty && raw == null) {
      final linearStocks = _stockCatalog
          .where((item) => item.mode == CutMode.linear && item.unit == 'mm')
          .toList();
      final stock = linearStocks.isEmpty ? null : linearStocks.first;
      final defaultStock = stock ??
          StockConfig(
            name: '6 m bar',
            width: 6000,
            quantity: 0,
            mode: CutMode.linear,
          );
      if (stock == null) _stockCatalog.add(defaultStock);
      final sample = Project(
          name: 'Workshop — frame set',
          mode: CutMode.linear,
          material: defaultStock.material,
          variant: defaultStock.variant,
          stock: defaultStock,
          assemblies: [
            Assembly(
              name: 'Frame set',
              parts: [
                Part(name: 'Upright', a: 1800, quantity: 4),
                Part(name: 'Cross rail', a: 920, quantity: 6),
                Part(name: 'Brace', a: 640, quantity: 4),
                Part(name: 'Short tab', a: 280, quantity: 8)
              ],
            ),
          ]);
      sample.updated = _date();
      _projects.add(sample);
      _active = sample;
      _result = CuttingEngine.solve(sample);
      await _save();
    } else {
      final activeProjects =
          _projects.where((project) => !project.archived).toList();
      _active = activeProjects.isEmpty ? null : activeProjects.first;
      _result = _active == null ? null : CuttingEngine.solve(_active!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _projectsStorageKey,
      jsonEncode(_projects
          .map((project) => project.toJson(includeStockDefinitions: false))
          .toList()),
    );
    await prefs.setString(
      _stocksStorageKey,
      jsonEncode(_stockCatalog.map((stock) => stock.toJson()).toList()),
    );
  }

  List<StockConfig> _stocksForProject(Project project) => _stockCatalog
      .where(
          (stock) => stock.mode == project.mode && stock.unit == project.unit)
      .toList();

  String _projectMaterialSummary(Project project) => project.stocks
      .map((stock) => [
            stock.material,
            if (stock.variant.isNotEmpty) stock.variant,
          ].join(' '))
      .toSet()
      .join(', ');

  String _stockLabel(StockConfig stock) => [
        stock.material,
        if (stock.variant.isNotEmpty) stock.variant,
        '— ${stock.name}',
      ].join(' ');

  void _replaceCatalogStock(StockConfig stock) {
    final index = _stockCatalog.indexWhere((item) => item.id == stock.id);
    if (index >= 0) _stockCatalog[index] = stock;
    for (final project in _projects) {
      final projectStockIndex =
          project.stocks.indexWhere((item) => item.id == stock.id);
      if (projectStockIndex >= 0) project.stocks[projectStockIndex] = stock;
    }
  }

  void _registerProjectStocks(Project project) {
    for (var index = 0; index < project.stocks.length; index++) {
      final stock = project.stocks[index];
      final catalogIndex =
          _stockCatalog.indexWhere((item) => item.id == stock.id);
      if (catalogIndex < 0) {
        _stockCatalog.add(stock);
      } else {
        project.stocks[index] = _stockCatalog[catalogIndex];
      }
    }
    project.bindStocks(_stockCatalog);
  }

  String _date() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _newProject() async {
    final name = TextEditingController(text: 'New cutting job');
    var mode = CutMode.linear;
    var unit = 'mm';

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
                  onChanged: (value) => refresh(() => unit = value ?? unit),
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
                      unit: unit,
                      material:
                          mode == CutMode.linear ? 'Mild steel' : 'Plywood',
                      variant: mode == CutMode.linear
                          ? '25×25×1.6 mm'
                          : '18 mm birch',
                      stock: mode == CutMode.linear
                          ? StockConfig(
                              name: unit == 'mm' ? '6 m bar' : '20 ft bar',
                              material: mode == CutMode.linear
                                  ? 'Mild steel'
                                  : 'Plywood',
                              variant: mode == CutMode.linear
                                  ? '25×25×1.6 mm'
                                  : '18 mm birch',
                              width: unit == 'mm' ? 6000 : 240,
                              mode: mode,
                              unit: unit)
                          : StockConfig(
                              name: '2440 × 1220 sheet',
                              width: unit == 'mm' ? 2440 : 96,
                              height: unit == 'mm' ? 1220 : 48,
                              material: 'Plywood',
                              variant: '18 mm birch',
                              mode: mode,
                              unit: unit),
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
      final compatibleStocks = _stocksForProject(result);
      if (compatibleStocks.isNotEmpty) {
        result.stocks = [compatibleStocks.first];
        result.material = compatibleStocks.first.material;
        result.variant = compatibleStocks.first.variant;
      }
      _registerProjectStocks(result);
      setState(() {
        _projects.insert(0, result);
        _active = result;
        _result = null;
        _page = 1;
      });
      await _save();
    }
  }

  Future<void> _archiveProject(Project project) async {
    setState(() {
      project.archived = true;
      project.updated = _date();
      if (_active?.id == project.id) {
        final remaining =
            _projects.where((candidate) => !candidate.archived).toList();
        _active = remaining.isEmpty ? null : remaining.first;
        _result = _active == null ? null : CuttingEngine.solve(_active!);
      }
    });
    await _save();
  }

  Future<void> _restoreProject(Project project) async {
    setState(() {
      project.archived = false;
      project.updated = _date();
      if (_active == null) {
        _active = project;
        _result = CuttingEngine.solve(project);
      }
    });
    await _save();
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
            '“${project.name}” and its assemblies and parts will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB65B4D)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _projects.removeWhere((candidate) => candidate.id == project.id);
      if (_active?.id == project.id) {
        final remaining =
            _projects.where((candidate) => !candidate.archived).toList();
        _active = remaining.isEmpty ? null : remaining.first;
        _result = _active == null ? null : CuttingEngine.solve(_active!);
      }
    });
    await _save();
  }

  Future<void> _editProject() async {
    final p = _active;
    if (p == null) return;

    final name = TextEditingController(text: p.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit project'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Project name'),
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
      p.updated = _date();
      setState(() => _result = null);
      await _save();
    }
  }

  double _num(String s, double fallback) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? fallback;

  Future<StockConfig?> _stockEditor(StockConfig? existing) async {
    final name = TextEditingController(text: existing?.name ?? 'New stock');
    final material =
        TextEditingController(text: existing?.material ?? 'Mild steel');
    final variant = TextEditingController(text: existing?.variant ?? '');
    final width =
        TextEditingController(text: (existing?.width ?? 6000).toString());
    final height = TextEditingController(
        text: (existing?.height ?? (_active?.mode == CutMode.sheet ? 1220 : 0))
            .toString());
    final quantity =
        TextEditingController(text: (existing?.quantity ?? 0).toString());
    final price =
        TextEditingController(text: (existing?.price ?? 0).toString());
    final kerf = TextEditingController(text: (existing?.kerf ?? 3).toString());
    final trim = TextEditingController(text: (existing?.trim ?? 0).toString());
    var mode = existing?.mode ?? _active?.mode ?? CutMode.linear;
    var unit = existing?.unit ?? _active?.unit ?? 'mm';

    return showDialog<StockConfig>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title:
              Text(existing == null ? 'Add shared stock' : 'Edit shared stock'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: material,
                    decoration: const InputDecoration(labelText: 'Material'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: variant,
                    decoration:
                        const InputDecoration(labelText: 'Variant / profile'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Stock format'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<CutMode>(
                        initialValue: mode,
                        decoration:
                            const InputDecoration(labelText: 'Cutting mode'),
                        items: const [
                          DropdownMenuItem(
                              value: CutMode.linear, child: Text('Linear')),
                          DropdownMenuItem(
                              value: CutMode.sheet, child: Text('Sheet')),
                        ],
                        onChanged: existing == null
                            ? (value) => refresh(() => mode = value ?? mode)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: const [
                          DropdownMenuItem(value: 'mm', child: Text('mm')),
                          DropdownMenuItem(value: 'in', child: Text('in')),
                        ],
                        onChanged: existing == null
                            ? (value) => refresh(() => unit = value ?? unit)
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: width,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: mode == CutMode.linear
                                ? 'Stock length ($unit)'
                                : 'Sheet width ($unit)'),
                      ),
                    ),
                    if (mode == CutMode.sheet) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: height,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: 'Sheet height ($unit)'),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Available qty (0 = unlimited)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Cost per unit'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: kerf,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Kerf ($unit)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: trim,
                        keyboardType: TextInputType.number,
                        decoration:
                            InputDecoration(labelText: 'Edge trim ($unit)'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final stockWidth = _num(width.text, 0);
                final stockHeight =
                    mode == CutMode.sheet ? _num(height.text, 0) : 0.0;
                final available = int.tryParse(quantity.text) ?? -1;
                if (name.text.trim().isEmpty ||
                    material.text.trim().isEmpty ||
                    stockWidth <= 0 ||
                    (mode == CutMode.sheet && stockHeight <= 0) ||
                    available < 0) {
                  _toast(
                      'Enter a material, stock name, valid dimensions and quantity.');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  StockConfig(
                    id: existing?.id,
                    name: name.text.trim(),
                    material: material.text.trim(),
                    variant: variant.text.trim(),
                    width: stockWidth,
                    height: stockHeight,
                    quantity: available,
                    price: _num(price.text, 0),
                    kerf: _num(kerf.text, 0),
                    trim: _num(trim.text, 0),
                    mode: mode,
                    unit: unit,
                  ),
                );
              },
              child: const Text('Save stock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageStocks() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Global materials & stock'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final stock in _stockCatalog)
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title:
                            Text('${stock.material} ${stock.variant}'.trim()),
                        subtitle: Text(
                          '${stock.name} • ${stock.mode == CutMode.linear ? '${stock.width} ${stock.unit}' : '${stock.width} × ${stock.height} ${stock.unit}'} • Qty ${stock.quantity == 0 ? 'unlimited' : stock.quantity}',
                        ),
                        trailing: Wrap(children: [
                          IconButton(
                            tooltip: 'Edit stock type',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final updated = await _stockEditor(stock);
                              if (updated != null) {
                                _replaceCatalogStock(updated);
                                refresh(() {});
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Remove stock type',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _projects.any((project) => project.parts
                                    .any((part) => part.stockId == stock.id))
                                ? null
                                : () {
                                    for (final project in _projects) {
                                      project.stocks.removeWhere(
                                          (item) => item.id == stock.id);
                                      if (project.stocks.isEmpty) {
                                        final replacements = _stockCatalog
                                            .where((item) =>
                                                item.id != stock.id &&
                                                item.mode == project.mode &&
                                                item.unit == project.unit)
                                            .toList();
                                        if (replacements.isNotEmpty) {
                                          project.stocks
                                              .add(replacements.first);
                                        }
                                      }
                                    }
                                    _stockCatalog.removeWhere(
                                        (item) => item.id == stock.id);
                                    refresh(() {});
                                  },
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final stock = await _stockEditor(null);
                    if (stock != null) {
                      _stockCatalog.add(stock);
                      refresh(() {});
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add material / stock'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock quantities are shared across projects. Each project plan checks the shared quantity independently; plans do not reserve or deduct stock.',
                style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    fontSize: 12),
              ),
            ]),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'))
          ],
        ),
      ),
    );
    setState(() {
      _result = _active == null ? null : CuttingEngine.solve(_active!);
    });
    await _save();
  }

  Future<void> _addAssembly() async {
    final name = TextEditingController(text: 'New assembly');
    final quantity = TextEditingController(text: '1');
    final assembly = await showDialog<Assembly>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add assembly'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Assembly name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Assemblies to produce'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(quantity.text) ?? 0;
              if (name.text.trim().isEmpty || count <= 0) {
                _toast('Enter an assembly name and a positive quantity.');
                return;
              }
              Navigator.pop(
                dialogContext,
                Assembly(name: name.text.trim(), quantity: count),
              );
            },
            child: const Text('Add assembly'),
          ),
        ],
      ),
    );
    if (assembly == null || _active == null) return;
    setState(() {
      _active!.assemblies.add(assembly);
      _active!.updated = _date();
      _result = null;
    });
    await _save();
  }

  Future<void> _editAssembly(Assembly assembly) async {
    final name = TextEditingController(text: assembly.name);
    final quantity = TextEditingController(text: '${assembly.quantity}');
    final updated = await showDialog<Assembly>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit assembly'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Assembly name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Assemblies to produce'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(quantity.text) ?? 0;
              if (name.text.trim().isEmpty || count <= 0) {
                _toast('Enter an assembly name and a positive quantity.');
                return;
              }
              Navigator.pop(
                dialogContext,
                Assembly(
                    name: name.text.trim(), quantity: count, id: assembly.id),
              );
            },
            child: const Text('Save assembly'),
          ),
        ],
      ),
    );
    if (updated == null || _active == null) return;
    setState(() {
      if (updated.quantity != assembly.quantity) {
        for (final part in assembly.parts) {
          _active!.cutPieces
              .removeWhere((key) => key.startsWith('${part.id}:'));
        }
      }
      assembly.name = updated.name;
      assembly.quantity = updated.quantity;
      _active!.updated = _date();
      _result = null;
    });
    await _save();
  }

  Future<void> _addPart(Assembly assembly) async {
    final p = _active;
    if (p == null) return;
    final availableStocks = _stocksForProject(p);
    if (availableStocks.isEmpty) {
      _toast(
          'Add a shared ${p.mode == CutMode.linear ? 'linear' : 'sheet'} stock type first.');
      return;
    }

    final name = TextEditingController(
        text: p.mode == CutMode.linear ? 'Cut length' : 'Panel');
    final a =
        TextEditingController(text: p.mode == CutMode.linear ? '1000' : '600');
    final b =
        TextEditingController(text: p.mode == CutMode.linear ? '0' : '400');
    final q = TextEditingController(text: '1');
    var rotate = true;
    final lastPart = assembly.parts.isNotEmpty
        ? assembly.parts.last
        : p.parts.isNotEmpty
            ? p.parts.last
            : null;
    var selectedStockId =
        availableStocks.any((stock) => stock.id == lastPart?.stockId)
            ? lastPart!.stockId
            : availableStocks.first.id;

    final part = await showDialog<Part>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('Add part to ${assembly.name}'),
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
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Stock type'),
                  items: [
                    for (final stock in availableStocks)
                      DropdownMenuItem(
                          value: stock.id,
                          child: Text(_stockLabel(stock),
                              overflow: TextOverflow.ellipsis))
                  ],
                  onChanged: (value) => refresh(() =>
                      selectedStockId = value ?? availableStocks.first.id),
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
        assembly.parts.add(part);
        final stock =
            _stockCatalog.firstWhere((item) => item.id == part.stockId);
        if (!p.stocks.any((item) => item.id == stock.id)) {
          p.stocks.add(stock);
        }
        p.material = stock.material;
        p.variant = stock.variant;
        p.updated = _date();
        _result = null;
      });
      await _save();
    }
  }

  Future<void> _editPart(Project project, Assembly assembly, Part part) async {
    final name = TextEditingController(text: part.name);
    final a = TextEditingController(text: '${part.a}');
    final b = TextEditingController(text: '${part.b}');
    final quantity = TextEditingController(text: '${part.quantity}');
    final availableStocks = _stocksForProject(project);
    if (availableStocks.isEmpty) {
      _toast('Add a shared stock type before editing this part.');
      return;
    }
    if (project.assemblies.isEmpty) {
      _toast('Add an assembly before editing this part.');
      return;
    }
    var stockId = availableStocks.any((stock) => stock.id == part.stockId)
        ? part.stockId
        : availableStocks.first.id;
    var assemblyId = assembly.id;
    var rotate = part.rotate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('Edit ${part.name}'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Part name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: stockId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Shared stock'),
                items: [
                  for (final stock in availableStocks)
                    DropdownMenuItem(
                        value: stock.id,
                        child: Text(_stockLabel(stock),
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: (value) => refresh(() => stockId = value ?? stockId),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: assemblyId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assembly'),
                items: [
                  for (final target in project.assemblies)
                    DropdownMenuItem(
                      value: target.id,
                      child: Text(target.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) =>
                    refresh(() => assemblyId = value ?? assemblyId),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: a,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: project.mode == CutMode.linear
                          ? 'Length (${project.unit})'
                          : 'Width (${project.unit})',
                    ),
                  ),
                ),
                if (project.mode == CutMode.sheet) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: b,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: 'Height (${project.unit})'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Quantity per assembly'),
              ),
              if (project.mode == CutMode.sheet)
                CheckboxListTile(
                  value: rotate,
                  onChanged: (value) => refresh(() => rotate = value ?? rotate),
                  title: const Text('Allow 90° rotation'),
                  contentPadding: EdgeInsets.zero,
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save part')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final updatedA = _num(a.text, 0);
    final updatedB = project.mode == CutMode.sheet ? _num(b.text, 0) : 0.0;
    final updatedQuantity = int.tryParse(quantity.text) ?? 0;
    if (name.text.trim().isEmpty ||
        updatedA <= 0 ||
        (project.mode == CutMode.sheet && updatedB <= 0) ||
        updatedQuantity <= 0) {
      _toast('Enter a name, positive dimensions and a positive quantity.');
      return;
    }
    setState(() {
      final destination = project.assemblies
          .firstWhere((candidate) => candidate.id == assemblyId);
      if (updatedQuantity != part.quantity || destination != assembly) {
        project.cutPieces.removeWhere((key) => key.startsWith('${part.id}:'));
      }
      part
        ..name = name.text.trim()
        ..a = updatedA
        ..b = updatedB
        ..quantity = updatedQuantity
        ..stockId = stockId
        ..rotate = rotate;
      if (destination != assembly) {
        assembly.parts.remove(part);
        destination.parts.add(part);
      }
      final stock = _stockCatalog.firstWhere((item) => item.id == stockId);
      if (!project.stocks.any((item) => item.id == stock.id)) {
        project.stocks.add(stock);
      }
      project.updated = _date();
      _result = null;
    });
    await _save();
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
      ['Materials', _projectMaterialSummary(p)],
      ['Stock types', p.stocks.map((stock) => stock.name).join(', ')],
      ['Status', 'Heuristic plan — optimality not proven'],
      [],
      [
        'Stock unit',
        'Assembly',
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
            c.assemblyName,
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
            c.assemblyName,
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
        build: (ctx) {
          final content = <pw.Widget>[
            pw.Text('Cut Optimiser — Production Report',
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Project: ${p.name}'),
            pw.Text('Materials: ${_projectMaterialSummary(p)}'),
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
                  p.stocks
                      .map((s) => '${s.name}: ${s.kerf} ${p.unit}')
                      .join('; ')
                ],
                [
                  'Stock-specific trim',
                  p.stocks
                      .map((s) => '${s.name}: ${s.trim} ${p.unit}')
                      .join('; ')
                ],
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text('Parts by assembly',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ];

          for (final assembly in p.assemblies) {
            content.addAll([
              pw.SizedBox(height: 8),
              pw.Text('${assembly.name} — ${assembly.quantity} to produce',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Table.fromTextArray(
                headers: [
                  'Part',
                  'Per assembly',
                  'Total to cut',
                  'Dimensions (${p.unit})',
                  'Stock'
                ],
                data: [
                  for (final part in assembly.parts)
                    [
                      part.name,
                      '${part.quantity}',
                      '${part.quantity * assembly.quantity}',
                      p.mode == CutMode.linear
                          ? '${part.a}'
                          : '${part.a} × ${part.b}',
                      p.stocks
                              .where((stock) => stock.id == part.stockId)
                              .map((stock) => stock.name)
                              .firstOrNull ??
                          'Unknown stock',
                    ]
                ],
              ),
            ]);
          }

          content.addAll([
            pw.SizedBox(height: 12),
            pw.Text('Cut list by assembly',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ]);
          for (final assembly in p.assemblies) {
            final placements = r.mode == CutMode.linear
                ? [
                    for (final stick in r.linear)
                      for (final part in stick.cuts)
                        if (part.assemblyName == assembly.name)
                          (stick.stockName, stick.index, part)
                  ]
                : [
                    for (final sheet in r.sheets)
                      for (final part in sheet.placements)
                        if (part.assemblyName == assembly.name)
                          (sheet.stockName, sheet.index, part)
                  ];
            if (placements.isEmpty) continue;
            content.addAll([
              pw.SizedBox(height: 8),
              pw.Text(assembly.name,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              if (r.mode == CutMode.linear)
                pw.Table.fromTextArray(
                  headers: ['Bar', 'Part', 'Start', 'Length'],
                  data: [
                    for (final (stockName, index, part) in placements)
                      [
                        '$stockName $index',
                        part.name,
                        part.x.toStringAsFixed(1),
                        part.w.toStringAsFixed(1)
                      ]
                  ],
                )
              else
                pw.Table.fromTextArray(
                  headers: ['Sheet', 'Part', 'X', 'Y', 'W', 'H', 'Rotated'],
                  data: [
                    for (final (stockName, index, part) in placements)
                      [
                        '$stockName $index',
                        part.name,
                        part.x.toStringAsFixed(1),
                        part.y.toStringAsFixed(1),
                        part.w.toStringAsFixed(1),
                        part.h.toStringAsFixed(1),
                        part.rotated ? 'Yes' : 'No'
                      ]
                  ],
                ),
            ]);
          }

          content.addAll([
            pw.SizedBox(height: 14),
            pw.Text('Notes: ${r.notes.join(' ')}'),
          ]);
          return content;
        },
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: pdf.PdfPageFormat.a4.landscape,
        build: (ctx) => [
          pw.Text('Cutting diagrams — ${p.name}',
              style:
                  pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          if (r.mode == CutMode.linear)
            for (final stick in r.linear) _pdfLinearDiagram(stick, p.unit)
          else
            for (final sheet in r.sheets)
              _pdfSheetDiagram(
                  sheet, p.unit, _trimForStock(p, sheet.stockName)),
        ],
      ),
    );
    await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: '${p.name}_production_report.pdf');
  }

  pw.Widget _pdfLinearDiagram(LinearStick stick, String unit) {
    const width = 740.0;
    const left = 4.0;
    const barTop = 22.0;
    const barHeight = 24.0;
    final scale = (width - left * 2) / stick.stockLength;
    final colors = [
      pdf.PdfColor.fromHex('#69B49B'),
      pdf.PdfColor.fromHex('#8BB7E9'),
      pdf.PdfColor.fromHex('#FFB16E'),
      pdf.PdfColor.fromHex('#B2A1E2'),
      pdf.PdfColor.fromHex('#7FC9D1'),
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('${stick.stockName} — Bar ${stick.index}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(
            height: 58,
            child: pw.Stack(
              children: [
                pw.Positioned(
                  left: left,
                  top: barTop,
                  child: pw.SizedBox(
                    width: width - left * 2,
                    height: barHeight,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: pdf.PdfColor.fromHex('#E6EBF0'),
                        border: pw.Border.all(
                            color: pdf.PdfColor.fromHex('#405268')),
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < stick.cuts.length; index++)
                  pw.Positioned(
                    left: left + stick.cuts[index].x * scale,
                    top: barTop,
                    child: pw.SizedBox(
                      width: math.max(1.0, stick.cuts[index].w * scale),
                      height: barHeight,
                      child: pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                        decoration: pw.BoxDecoration(
                          color: stick.cuts[index].isCut
                              ? pdf.PdfColor.fromHex('#2F8D75')
                              : colors[index % colors.length],
                          border: pw.Border.all(
                              color: pdf.PdfColor.fromHex('#FFFFFF')),
                        ),
                        child: pw.Text(
                          '${stick.cuts[index].assemblyName}: ${stick.cuts[index].name}',
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: const pw.TextStyle(fontSize: 6),
                        ),
                      ),
                    ),
                  ),
                pw.Positioned(
                  left: left,
                  top: 48,
                  child: pw.Text('0 $unit',
                      style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Positioned(
                  right: left,
                  top: 48,
                  child: pw.Text(
                      '${stick.stockLength.toStringAsFixed(0)} $unit',
                      style: const pw.TextStyle(fontSize: 8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSheetDiagram(SheetLayout sheet, String unit, double trim) {
    const maxWidth = 740.0;
    const maxHeight = 410.0;
    const inset = 8.0;
    final scale = math.min(
      (maxWidth - inset * 2) / sheet.stockW,
      (maxHeight - inset * 2) / sheet.stockH,
    );
    final width = sheet.stockW * scale + inset * 2;
    final height = sheet.stockH * scale + inset * 2;
    final colors = [
      pdf.PdfColor.fromHex('#FFC08A'),
      pdf.PdfColor.fromHex('#91D1B7'),
      pdf.PdfColor.fromHex('#9CC4F0'),
      pdf.PdfColor.fromHex('#C2B3EA'),
      pdf.PdfColor.fromHex('#F2D47E'),
      pdf.PdfColor.fromHex('#9AD8DC'),
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('${sheet.stockName} — Sheet ${sheet.index}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(
            width: width,
            height: height,
            child: pw.Stack(
              children: [
                pw.Positioned(
                  left: inset,
                  top: inset,
                  child: pw.SizedBox(
                    width: sheet.stockW * scale,
                    height: sheet.stockH * scale,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: pdf.PdfColor.fromHex('#F8FAFC'),
                        border: pw.Border.all(
                            color: pdf.PdfColor.fromHex('#101B2A')),
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < sheet.placements.length; index++)
                  pw.Positioned(
                    left: inset + (trim + sheet.placements[index].x) * scale,
                    top: inset + (trim + sheet.placements[index].y) * scale,
                    child: pw.SizedBox(
                      width: sheet.placements[index].w * scale,
                      height: sheet.placements[index].h * scale,
                      child: pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(2),
                        decoration: pw.BoxDecoration(
                          color: sheet.placements[index].isCut
                              ? pdf.PdfColor.fromHex('#2F8D75')
                              : colors[index % colors.length],
                          border: pw.Border.all(
                              color: pdf.PdfColor.fromHex('#405268')),
                        ),
                        child: pw.Text(
                          '${sheet.placements[index].assemblyName}: ${sheet.placements[index].name}\n${sheet.placements[index].w.toStringAsFixed(0)} × ${sheet.placements[index].h.toStringAsFixed(0)}',
                          maxLines: 3,
                          textAlign: pw.TextAlign.center,
                          overflow: pw.TextOverflow.clip,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          pw.Text(
              '${sheet.stockW.toStringAsFixed(0)} × ${sheet.stockH.toStringAsFixed(0)} $unit',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
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
              : '${_active!.name}  •  ${_projectMaterialSummary(_active!)}',
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
    final activeProjects =
        _projects.where((project) => !project.archived).toList();
    final pieces = activeProjects.fold<int>(0, (s, p) => s + p.totalPieces);
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
          MetricCard('Projects', '${activeProjects.length}',
              Icons.folder_copy_outlined, orange),
          MetricCard('Part demand', '$pieces pcs', Icons.view_list_outlined,
              const Color(0xFF2F8D75)),
          MetricCard(
              'Material types',
              '${_stockCatalog.map((stock) => stock.material).toSet().length}',
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
        for (final p in activeProjects.take(6))
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
                  '${p.mode == CutMode.linear ? 'Linear' : 'Sheet'} • ${_projectMaterialSummary(p)} • ${p.totalPieces} pieces'),
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
                                labelText: 'Select active project'),
                            items: [
                              for (final p in _projects
                                  .where((project) => !project.archived))
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
                          _infoLine(
                              'Materials',
                              _active == null
                                  ? '—'
                                  : _projectMaterialSummary(_active!)),
                          _infoLine(
                              'Stock types',
                              _active?.stocks
                                      .map((stock) => stock.name)
                                      .join(', ') ??
                                  '—'),
                          _infoLine(
                            'Stock formats',
                            _active == null
                                ? '—'
                                : _active!.stocks
                                    .map((stock) =>
                                        '${stock.name} (${stock.mode == CutMode.linear ? '${stock.width}' : '${stock.width} × ${stock.height}'} ${stock.unit})')
                                    .join(', '),
                          ),
                          _infoLine(
                            'Shared availability',
                            _active == null
                                ? '—'
                                : _active!.stocks
                                    .map((stock) =>
                                        '${stock.name}: ${stock.quantity == 0 ? 'unlimited' : stock.quantity}')
                                    .join(', '),
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
          _projectManagementCard(),
          const SizedBox(height: 18),
          const PrototypeNotice(),
        ],
      );

  Widget _projectManagementCard() {
    final visibleProjects = _projects
        .where((project) => project.archived == _showArchivedProjects)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _showArchivedProjects ? 'Archived projects' : 'Projects',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(
                      () => _showArchivedProjects = !_showArchivedProjects),
                  icon: Icon(_showArchivedProjects
                      ? Icons.folder_open_outlined
                      : Icons.archive_outlined),
                  label: Text(
                      _showArchivedProjects ? 'Show active' : 'Show archived'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (visibleProjects.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_showArchivedProjects
                    ? 'No archived projects.'
                    : 'No active projects. Create a project or restore one from the archive.'),
              )
            else
              for (final project in visibleProjects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    project.archived
                        ? Icons.archive_outlined
                        : project.mode == CutMode.linear
                            ? Icons.linear_scale
                            : Icons.grid_view,
                  ),
                  title: Text(project.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${project.mode == CutMode.linear ? 'Linear' : 'Sheet'} • ${project.totalPieces} pieces${_active?.id == project.id ? ' • Active' : ''}'),
                  onTap: project.archived
                      ? null
                      : () => setState(() {
                            _active = project;
                            _result = CuttingEngine.solve(project);
                          }),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (project.archived)
                        IconButton(
                          tooltip: 'Restore project',
                          onPressed: () => _restoreProject(project),
                          icon: const Icon(Icons.unarchive_outlined),
                        )
                      else
                        IconButton(
                          tooltip: 'Archive project',
                          onPressed: () => _archiveProject(project),
                          icon: const Icon(Icons.archive_outlined),
                        ),
                      IconButton(
                        tooltip: 'Delete project',
                        onPressed: () => _deleteProject(project),
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFB65B4D)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _materialsPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Materials & stock',
            'Maintain reusable material definitions and shared stock quantities for every project.'),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.inventory_2_outlined, color: orange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Global stock catalog',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  StatusPill('${_stockCatalog.length} TYPES'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Material and available quantities are shared across projects. Optimising a project checks the available quantity but does not reserve or deduct stock.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _manageStocks,
                  icon: const Icon(Icons.tune),
                  label: const Text('Manage shared materials & stock'),
                ),
                if (_stockCatalog.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                      'No shared stock types yet. Add one to assign it to assembly parts.'),
                ],
                for (final stock in _stockCatalog)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(stock.mode == CutMode.linear
                        ? Icons.linear_scale
                        : Icons.grid_view),
                    title: Text('${stock.material} ${stock.variant}'.trim()),
                    subtitle: Text(
                      '${stock.name} • ${stock.mode == CutMode.linear ? '${stock.width} ${stock.unit}' : '${stock.width} × ${stock.height} ${stock.unit}'} • ${stock.quantity == 0 ? 'Unlimited' : 'Available: ${stock.quantity}'}',
                    ),
                    trailing: Text(
                        stock.price == 0 ? '' : stock.price.toStringAsFixed(2)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const PrototypeNotice()
      ]);
  Widget _partsPage() {
    final p = _active;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: SectionTitle('Assemblies & parts',
                'Define assemblies to produce, then list each assembly’s component parts.')),
        FilledButton.icon(
            onPressed: p == null ? null : _addAssembly,
            icon: const Icon(Icons.add),
            label: const Text('Add assembly'))
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
                StatusPill(p.mode == CutMode.linear ? 'LINEAR' : 'SHEET'),
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
          if (p.assemblies.isEmpty)
            const Padding(
                padding: EdgeInsets.all(30),
                child: Text('No assemblies defined. Add an assembly to begin.'))
          else
            for (final assembly in p.assemblies) _assemblyCard(p, assembly),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${p.assemblies.length} assemblies • ${p.parts.length} part definitions • ${p.totalPieces} pieces to cut',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12))),
                OutlinedButton.icon(
                    onPressed: _addAssembly,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Assembly'))
              ]))
        ])),
      const SizedBox(height: 16),
      const PrototypeNotice()
    ]);
  }

  Widget _assemblyCard(Project project, Assembly assembly) => Card(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          children: [
            ListTile(
              title: Text(assembly.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${assembly.quantity} to produce • ${assembly.parts.fold<int>(0, (sum, part) => sum + part.quantity)} parts per assembly • ${assembly.quantity * assembly.parts.fold<int>(0, (sum, part) => sum + part.quantity)} total cuts'),
              trailing: Wrap(children: [
                IconButton(
                  tooltip: 'Edit assembly quantity and name',
                  onPressed: () => _editAssembly(assembly),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove assembly',
                  onPressed: () async {
                    setState(() {
                      for (final part in assembly.parts) {
                        project.cutPieces.removeWhere(
                            (key) => key.startsWith('${part.id}:'));
                      }
                      project.assemblies.remove(assembly);
                      project.updated = _date();
                      _result = null;
                    });
                    await _save();
                  },
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFB65B4D)),
                ),
              ]),
            ),
            if (assembly.parts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('No parts in this assembly yet.'),
              )
            else
              for (var index = 0; index < assembly.parts.length; index++)
                _partRow(project, assembly, assembly.parts[index], index),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _addPart(assembly),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add part to assembly'),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _partRow(Project project, Assembly assembly, Part part, int index) {
    final assignedStock =
        _stockCatalog.where((item) => item.id == part.stockId);
    final stockName =
        assignedStock.isEmpty ? 'Unknown stock' : assignedStock.first.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 24,
          child: Text('${index + 1}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(part.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${project.mode == CutMode.linear ? 'Length ${part.a}' : '${part.a} × ${part.b}'} ${project.unit} • ${part.quantity} per assembly • $stockName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit part name, dimensions and quantity',
          onPressed: () => _editPart(project, assembly, part),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
        IconButton(
          tooltip: 'Remove part',
          onPressed: () async {
            setState(() {
              assembly.parts.remove(part);
              project.cutPieces
                  .removeWhere((key) => key.startsWith('${part.id}:'));
              project.updated = _date();
              _result = null;
            });
            await _save();
          },
          icon: const Icon(Icons.delete_outline,
              size: 18, color: Color(0xFFB65B4D)),
        ),
      ]),
    );
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
                  MetricCard('Stock types', '${p.stocks.length}',
                      Icons.view_agenda_outlined, const Color(0xFF8A65C5)),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Required stock by type',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Stock units required for this project, compared with shared availability.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final stock in p.stocks)
                    _stockRequirementRow(
                      stock,
                      p.mode == CutMode.linear
                          ? r.linear
                              .where((stick) => stick.stockId == stock.id)
                              .length
                          : r.sheets
                              .where((sheet) => sheet.stockId == stock.id)
                              .length,
                      p.mode,
                    ),
                ],
              ),
            ),
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

  Widget _stockRequirementRow(StockConfig stock, int required, CutMode mode) {
    final overAvailable = stock.quantity > 0 && required > stock.quantity;
    final quantityLabel = stock.quantity == 0
        ? 'Unlimited available'
        : '${stock.quantity} available';
    final unitLabel = mode == CutMode.linear ? 'bars' : 'sheets';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        mode == CutMode.linear ? Icons.linear_scale : Icons.grid_view,
        color: overAvailable ? const Color(0xFFB65B4D) : orange,
      ),
      title: Text(
        '${stock.material}${stock.variant.isNotEmpty ? ' • ${stock.variant}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${stock.name} • $quantityLabel'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$required $unitLabel required',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: overAvailable ? const Color(0xFFB65B4D) : null,
            ),
          ),
          if (overAvailable)
            const Text(
              'Insufficient stock',
              style: TextStyle(color: Color(0xFFB65B4D), fontSize: 11),
            ),
        ],
      ),
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
                          '${group.length > 1 ? 'Bar ${item.index}: ' : ''}${part.assemblyName}: ${part.name}: ${part.w.toStringAsFixed(0)} ${project.unit}${part.isCut ? ' · Cut' : ''}',
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
                          '${group.length > 1 ? 'Sheet ${item.index}: ' : ''}${part.assemblyName}: ${part.name} · ${part.w.toStringAsFixed(0)}×${part.h.toStringAsFixed(0)}${part.isCut ? ' · Cut' : ''}',
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
                text: '${c.assemblyName}: ${c.name}${c.isCut ? ' ✓' : ''}',
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
                    '${p.assemblyName}: ${p.name}${p.isCut ? ' ✓' : ''}\n${p.w.toStringAsFixed(0)}×${p.h.toStringAsFixed(0)}',
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
