enum CutMode { linear, sheet }

class Part {
  Part({
    required this.name,
    required this.a,
    this.b = 0,
    this.quantity = 1,
    this.rotate = true,
    this.stockId = '',
  });

  final String name;
  final double a;
  final double b;
  final int quantity;
  final bool rotate;
  final String stockId;

  Map<String, dynamic> toJson() => {
        'name': name,
        'a': a,
        'b': b,
        'quantity': quantity,
        'rotate': rotate,
        'stockId': stockId,
      };
}

class StockConfig {
  StockConfig({
    this.id = '',
    this.name = 'Mild steel 25×25×1.6',
    this.width = 6000,
    this.height = 0,
    this.quantity = 0,
    this.price = 0,
    this.kerf = 3,
    this.trim = 0,
  });

  final String id;
  final String name;
  final double width;
  final double height;
  final int quantity;
  final double price;
  final double kerf;
  final double trim;

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
}

class Project {
  Project({
    required this.name,
    required this.mode,
    required this.material,
    required this.variant,
    required this.unit,
    required this.kerf,
    required this.trim,
    required this.parts,
    required this.stocks,
    this.updated = '',
  });

  final String name;
  final CutMode mode;
  final String material;
  final String variant;
  final String unit;
  final double kerf;
  final double trim;
  final List<Part> parts;
  final List<StockConfig> stocks;
  final String updated;

  int get totalPieces => parts.fold(0, (sum, part) => sum + part.quantity);
}
