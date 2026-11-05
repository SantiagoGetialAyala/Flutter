class Product {
  const Product({
    required this.id,
    required this.name,
    required this.productType,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.isActive,
  });

  final int id;
  final String name;
  final String productType;
  final String description;
  final double quantity;
  final String unit;
  final bool isActive;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      productType: json['product_type'] as String? ?? 'cafe',
      description: json['description'] as String? ?? '',
      quantity: double.tryParse(json['quantity'].toString()) ?? 0,
      unit: json['unit'] as String? ?? 'kg',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
