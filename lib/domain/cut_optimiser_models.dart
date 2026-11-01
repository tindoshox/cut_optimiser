import 'dart:math' as math;

enum CutMode { linear, sheet }

class Part {
  Part(
      {required this.name,
      required this.a,
      this.b = 0,
      this.quantity = 1,
      this.rotate = true,
      this.stockId = '',
      this.assemblyName = '',
      String? id,
      this.pieceIndex})
      : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final int? pieceIndex;
  String name;
  double a;
  double b;
  int quantity;
  bool rotate;
  String stockId;
  String assemblyName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'a': a,
        'b': b,
        'quantity': quantity,
        'rotate': rotate,
        'stockId': stockId,
      };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
        id: json['id']?.toString(),
        name: json['name'] ?? 'Part',
        a: (json['a'] as num).toDouble(),
        b: (json['b'] as num? ?? 0).toDouble(),
        quantity: json['quantity'] ?? 1,
        rotate: json['rotate'] ?? true,
        stockId: json['stockId']?.toString() ?? '',
      );
}

class Assembly {
  Assembly({
    required this.name,
    this.quantity = 1,
    List<Part>? parts,
    String? id,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        parts = parts ?? [];

  final String id;
  String name;
  int quantity;
  List<Part> parts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'parts': parts.map((part) => part.toJson()).toList(),
      };

  factory Assembly.fromJson(Map<String, dynamic> json) => Assembly(
        id: json['id']?.toString(),
        name: json['name']?.toString() ?? 'Assembly',
        quantity: json['quantity'] as int? ?? 1,
        parts: ((json['parts'] as List?) ?? [])
            .map((entry) => Part.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
      );
}

class StockConfig {
  StockConfig(
      {String? id,
      this.name = 'Mild steel 25×25×1.6',
      this.material = 'Mild steel',
      this.variant = '25×25×1.6 mm',
      this.width = 6000,
      this.height = 0,
      this.quantity = 0,
      this.price = 0,
      this.kerf = 3,
      this.trim = 0,
      CutMode? mode,
      this.unit = 'mm'})
      : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        mode = mode ?? (height > 0 ? CutMode.sheet : CutMode.linear);

  final String id;
  String name;
  String material;
  String variant;
  double width;
  double height;
  int quantity;
  double price;
  double kerf;
  double trim;
  CutMode mode;
  String unit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'material': material,
        'variant': variant,
        'width': width,
        'height': height,
        'quantity': quantity,
        'price': price,
        'kerf': kerf,
        'trim': trim,
        'mode': mode.name,
        'unit': unit,
      };

  factory StockConfig.fromJson(Map<String, dynamic> json) => StockConfig(
        id: json['id']?.toString(),
        name: json['name'] ?? 'Stock',
        material: json['material']?.toString() ?? 'Mild steel',
        variant: json['variant']?.toString() ?? '',
        width: (json['width'] as num? ?? 6000).toDouble(),
        height: (json['height'] as num? ?? 0).toDouble(),
        quantity: json['quantity'] ?? 0,
        price: (json['price'] as num? ?? 0).toDouble(),
        kerf: (json['kerf'] as num? ?? 3).toDouble(),
        trim: (json['trim'] as num? ?? 0).toDouble(),
        mode: CutMode.values.firstWhere(
          (mode) => mode.name == json['mode'],
          orElse: () => (json['height'] as num? ?? 0) > 0
              ? CutMode.sheet
              : CutMode.linear,
        ),
        unit: json['unit']?.toString() ?? 'mm',
      );
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
    List<Assembly>? assemblies,
    Set<String>? cutPieces,
    this.updated = '',
    this.archived = false,
  })  : stocks = stocks ?? [stock ?? StockConfig()],
        assemblies = assemblies ??
            [
              Assembly(
                name: 'Assembly 1',
                parts: parts ?? [],
              )
            ],
        cutPieces = cutPieces ?? <String>{},
        id = DateTime.now().microsecondsSinceEpoch.toString() {
    _assignDefaultStock();
  }

  Project._({
    required this.id,
    required this.name,
    required this.mode,
    required this.material,
    required this.variant,
    required this.unit,
    required this.kerf,
    required this.trim,
    required this.stocks,
    required this.assemblies,
    required this.cutPieces,
    required this.updated,
    required this.archived,
  }) {
    _assignDefaultStock();
  }

  final String id;
  String name;
  CutMode mode;
  String material;
  String variant;
  String unit;
  double kerf;
  double trim;
  List<StockConfig> stocks;
  List<Assembly> assemblies;
  Set<String> cutPieces;
  String updated;
  bool archived;

  StockConfig get stock =>
      stocks.isEmpty ? StockConfig(mode: mode, unit: unit) : stocks.first;
  set stock(StockConfig value) {
    if (stocks.isEmpty) {
      stocks = [value];
    } else {
      stocks[0] = value;
    }
    _assignDefaultStock();
  }

  void _assignDefaultStock() {
    if (stocks.isEmpty) return;
    for (final part in assemblies.expand((assembly) => assembly.parts)) {
      if (!stocks.any((stock) => stock.id == part.stockId)) {
        part.stockId = stocks.first.id;
      }
    }
  }

  void bindStocks(List<StockConfig> catalog) {
    final ids = stocks.map((stock) => stock.id).toSet();
    final matched = catalog.where((stock) => ids.contains(stock.id)).toList();
    if (matched.isNotEmpty) stocks = matched;
    _assignDefaultStock();
  }

  Map<String, dynamic> toJson({bool includeStockDefinitions = true}) => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'material': material,
        'variant': variant,
        'unit': unit,
        'kerf': kerf,
        'trim': trim,
        'assemblies': assemblies.map((assembly) => assembly.toJson()).toList(),
        'stockIds': stocks.map((stock) => stock.id).toList(),
        if (includeStockDefinitions)
          'stocks': stocks.map((s) => s.toJson()).toList(),
        'cutPieces': cutPieces.toList(),
        if (includeStockDefinitions && stocks.isNotEmpty)
          'stock': stock.toJson(),
        'updated': updated,
        'archived': archived,
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    final stockList = (json['stocks'] as List?)
        ?.map((entry) => StockConfig.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    final legacyStock = StockConfig.fromJson(
        Map<String, dynamic>.from(json['stock'] ?? {'width': 6000}));
    final stockIds =
        (json['stockIds'] as List?)?.map((entry) => entry.toString()).toList();
    final stocks = stockList != null && stockList.isNotEmpty
        ? stockList
        : stockIds != null
            ? stockIds.map((id) => StockConfig(id: id)).toList()
            : <StockConfig>[legacyStock];
    if (stockIds == null && (stockList == null || stockList.isEmpty)) {
      legacyStock.kerf = (json['kerf'] as num? ?? 3).toDouble();
      legacyStock.trim = (json['trim'] as num? ?? 0).toDouble();
    }

    final parts = ((json['parts'] as List?) ?? [])
        .map((entry) => Part.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    final assemblies = ((json['assemblies'] as List?) ?? [])
        .map((entry) => Assembly.fromJson(Map<String, dynamic>.from(entry)))
        .toList();

    for (final part in assemblies.expand((assembly) => assembly.parts)) {
      if (stocks.isNotEmpty &&
          (part.stockId.isEmpty ||
              !stocks.any((stock) => stock.id == part.stockId))) {
        part.stockId = stocks.first.id;
      }
    }

    return Project._(
      id: json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Untitled',
      mode: CutMode.values.firstWhere((mode) => mode.name == json['mode'],
          orElse: () => CutMode.linear),
      material: json['material'] ?? 'Mild steel',
      variant: json['variant'] ?? '',
      unit: json['unit'] ?? 'mm',
      kerf: (json['kerf'] as num? ?? 3).toDouble(),
      trim: (json['trim'] as num? ?? 0).toDouble(),
      stocks: stocks,
      assemblies: assemblies.isNotEmpty
          ? assemblies
          : [Assembly(name: 'Assembly 1', parts: parts)],
      cutPieces: ((json['cutPieces'] as List?) ?? [])
          .map((entry) => entry.toString())
          .toSet(),
      updated: json['updated'] ?? '',
      archived: json['archived'] as bool? ?? false,
    );
  }

  List<Part> get parts =>
      assemblies.expand((assembly) => assembly.parts).toList();

  int get totalPieces => assemblies.fold(
        0,
        (sum, assembly) =>
            sum +
            assembly.quantity *
                assembly.parts
                    .fold(0, (partSum, part) => partSum + part.quantity),
      );

  List<Part> get demandParts => [
        for (final assembly in assemblies)
          for (final part in assembly.parts)
            Part(
              id: part.id,
              name: part.name,
              a: part.a,
              b: part.b,
              quantity: part.quantity * assembly.quantity,
              rotate: part.rotate,
              stockId: part.stockId,
              assemblyName: assembly.name,
            ),
      ];
}

double clamp(double value, double min, double max) =>
    math.max(min, math.min(value, max));
