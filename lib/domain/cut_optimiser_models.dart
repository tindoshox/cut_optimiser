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

class StockConfig {
  StockConfig(
      {String? id,
      this.name = 'Mild steel 25×25×1.6',
      this.width = 6000,
      this.height = 0,
      this.quantity = 0,
      this.price = 0,
      this.kerf = 3,
      this.trim = 0})
      : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  String name;
  double width;
  double height;
  int quantity;
  double price;
  double kerf;
  double trim;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'quantity': quantity,
        'price': price,
        'kerf': kerf,
        'trim': trim,
      };

  factory StockConfig.fromJson(Map<String, dynamic> json) => StockConfig(
        id: json['id']?.toString(),
        name: json['name'] ?? 'Stock',
        width: (json['width'] as num? ?? 6000).toDouble(),
        height: (json['height'] as num? ?? 0).toDouble(),
        quantity: json['quantity'] ?? 0,
        price: (json['price'] as num? ?? 0).toDouble(),
        kerf: (json['kerf'] as num? ?? 3).toDouble(),
        trim: (json['trim'] as num? ?? 0).toDouble(),
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
    Set<String>? cutPieces,
    this.updated = '',
  })  : parts = parts ?? [],
        stocks = stocks ?? [stock ?? StockConfig()],
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
    required this.parts,
    required this.stocks,
    required this.cutPieces,
    required this.updated,
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
  List<Part> parts;
  List<StockConfig> stocks;
  Set<String> cutPieces;
  String updated;

  StockConfig get stock => stocks.first;
  set stock(StockConfig value) {
    if (stocks.isEmpty) {
      stocks = [value];
    } else {
      stocks[0] = value;
    }
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
        'id': id,
        'name': name,
        'mode': mode.name,
        'material': material,
        'variant': variant,
        'unit': unit,
        'kerf': kerf,
        'trim': trim,
        'parts': parts.map((p) => p.toJson()).toList(),
        'stocks': stocks.map((s) => s.toJson()).toList(),
        'cutPieces': cutPieces.toList(),
        'stock': stock.toJson(),
        'updated': updated,
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    final stockList = (json['stocks'] as List?)
        ?.map((entry) => StockConfig.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    final legacyStock = StockConfig.fromJson(
        Map<String, dynamic>.from(json['stock'] ?? {'width': 6000}));
    final stocks = (stockList == null || stockList.isEmpty)
        ? <StockConfig>[legacyStock]
        : stockList;
    if (stockList == null || stockList.isEmpty) {
      legacyStock.kerf = (json['kerf'] as num? ?? 3).toDouble();
      legacyStock.trim = (json['trim'] as num? ?? 0).toDouble();
    }

    final parts = ((json['parts'] as List?) ?? [])
        .map((entry) => Part.fromJson(Map<String, dynamic>.from(entry)))
        .toList();

    for (final part in parts) {
      if (part.stockId.isEmpty ||
          !stocks.any((stock) => stock.id == part.stockId)) {
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
      parts: parts,
      stocks: stocks,
      cutPieces: ((json['cutPieces'] as List?) ?? [])
          .map((entry) => entry.toString())
          .toSet(),
      updated: json['updated'] ?? '',
    );
  }

  int get totalPieces => parts.fold(0, (sum, part) => sum + part.quantity);
}

double clamp(double value, double min, double max) =>
    math.max(min, math.min(value, max));
