/// Product model mirroring the backend product schema
/// (`id`, `name`, `slug`, `price`, `stockQuantity`, `media.mainImage`,
/// `brand`, ...). Parsing is tolerant of both nested (`media.mainImage`,
/// `category.name`) and flat legacy keys (`image_url`, `category_name`)
/// so real API and demo payloads both work unchanged.
class Product {
  const Product({
    required this.id,
    this.apiId,
    required this.name,
    required this.slug,
    required this.description,
    required this.price,
    required this.imageUrl,
    this.originalPrice,
    this.brand,
    this.stockQuantity = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.badges = const <String>[],
    this.categoryId,
    this.categoryName,
    this.vendorId,
    this.vendorName,
    this.isFeatured = false,
    this.isOnSale = false,
  });

  final int id;
  final String? apiId;
  final String name;
  final String slug;
  final String description;
  final double price;

  /// Price before any discount; null means the product is not on sale.
  final double? originalPrice;
  final String imageUrl;
  final String? brand;
  final int stockQuantity;
  final double rating;
  final int ratingCount;
  final List<String> badges;
  final int? categoryId;
  final String? categoryName;
  final int? vendorId;
  final String? vendorName;
  final bool isFeatured;
  final bool isOnSale;

  bool get inStock => stockQuantity > 0;

  bool get isBestSeller => badges.contains('best-seller');

  bool get isNewArrival => badges.contains('new');

  /// A product counts as on sale when flagged or when an original price is set.
  bool get onSale =>
      isOnSale || (originalPrice != null && originalPrice! > price);

  /// Integer percentage discount (0 when not on sale).
  int get discountPercent {
    final base = originalPrice ?? price;
    if (base <= 0 || base <= price) return 0;
    return ((base - price) / base * 100).round();
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    final category = json['category'];
    final vendor = json['vendor'];
    final fallbackImage = json['image_url'] ?? json['image'];
    final original = json['originalPrice'] ??
        (json['discount'] is Map
            ? (json['discount'] as Map<String, dynamic>)['originalPrice']
            : null);

    return Product(
      id: _toInt(json['id'] ?? json['_id']),
      apiId: (json['_id'] ?? json['id'])?.toString(),
      name: _toString(json['name']),
      slug: _toString(json['slug']),
      description: _toString(json['description']),
      price: _toDouble(json['price']),
      originalPrice: original != null ? _toDouble(original) : null,
      imageUrl: media is Map
          ? _toString(media['mainImage'])
          : _toString(fallbackImage),
      brand: json['brand']?.toString(),
      stockQuantity: _toInt(json['stockQuantity']),
      rating: _toDouble(json['rating'] ?? json['averageRating']),
      ratingCount: _toInt(json['ratingCount'] ?? json['reviewCount']),
      badges: json['badges'] is List
          ? (json['badges'] as List<dynamic>).map((e) => e.toString()).toList()
          : const <String>[],
      categoryId: category is Map
          ? _toIntOrNull(category['id'] ?? category['_id'])
          : _toIntOrNull(json['category_id']),
      categoryName: category is Map
          ? category['name']?.toString()
          : json['category_name']?.toString(),
      vendorId: vendor is Map
          ? _toIntOrNull(vendor['id'] ?? vendor['_id'])
          : _toIntOrNull(json['vendor_id']),
      vendorName: vendor is Map
          ? (vendor['name'] ?? vendor['companyName'] ?? vendor['Fullname'])?.toString()
          : json['vendor_name']?.toString(),
      isFeatured: json['isFeatured'] == true || json['featured'] == true,
      isOnSale:
          json['isOnSale'] == true || json['onSale'] == true || original != null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'price': price,
        'originalPrice': originalPrice,
        'stockQuantity': stockQuantity,
        'rating': rating,
        'ratingCount': ratingCount,
        'badges': badges,
        'isFeatured': isFeatured,
        'isOnSale': onSale,
        'brand': brand,
        'category': <String, dynamic>{
          'id': categoryId,
          'name': categoryName,
        },
        'vendor': <String, dynamic>{
          'id': vendorId,
          'name': vendorName,
        },
        'media': <String, dynamic>{
          'mainImage': imageUrl,
        },
      };

  static String _toString(dynamic value) => value?.toString() ?? '';

  static double _toDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static int _toInt(dynamic value) => value is num
      ? value.toInt()
      : _parseId(value) ?? 0;

  static int? _toIntOrNull(dynamic value) => value is num
      ? value.toInt()
      : _parseId(value);

  static int? _parseId(dynamic value) {
    final text = value?.toString() ?? '';
    final decimal = int.tryParse(text);
    if (decimal != null) return decimal;
    if (RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(text)) {
      return int.tryParse(text.substring(0, 12), radix: 16);
    }
    return null;
  }
}