/// Category model mirroring the backend category schema
/// (`id`, `name`, `slug`, `productCount`, `media.mainImage`).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.imageUrl,
    this.productCount = 0,
  });

  final int id;
  final String name;
  final String slug;
  final String imageUrl;
  final int productCount;

  factory Category.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    return Category(
      id: _toInt(json['id'] ?? json['_id']),
      name: _toString(json['name']),
      slug: _toString(json['slug']),
      imageUrl: media is Map
          ? _toString(media['mainImage'])
          : _toString(
              // The backend Category document stores the image as `imageUrl`,
              // so the catalogue spellings alone would leave every tile blank.
              json['imageUrl'] ??
                  json['image_url'] ??
                  json['icon'] ??
                  json['image'],
            ),
      productCount: _toInt(json['productCount'] ?? json['product_count']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'slug': slug,
        'productCount': productCount,
        'media': <String, dynamic>{
          'mainImage': imageUrl,
        },
      };

  static String _toString(dynamic value) => value?.toString() ?? '';

  static int _toInt(dynamic value) => value is num
      ? value.toInt()
      : _parseId(value) ?? 0;

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