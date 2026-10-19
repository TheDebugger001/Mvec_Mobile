import '../core/format.dart';

/// A storefront product, shaped like `mapBackendProduct()` in the web app.
class Product {
  const Product({
    required this.id,
    required this.publicId,
    required this.name,
    required this.category,
    required this.brand,
    required this.vendor,
    required this.vendorId,
    required this.price,
    required this.oldPrice,
    required this.rating,
    required this.reviews,
    required this.stock,
    required this.sku,
    required this.image,
    required this.gallery,
    required this.description,
    required this.status,
    required this.slug,
    required this.attributes,
  });

  final String id;
  final String publicId;
  final String name;
  final String category;
  final String brand;
  final String vendor;
  final String vendorId;

  /// Price the buyer pays (the discount price when one applies).
  final num price;

  /// Price before the discount, 0 when the product is not on sale.
  final num oldPrice;
  final num rating;
  final int reviews;
  final int stock;
  final String sku;
  final String image;
  final List<String> gallery;
  final String description;
  final String status;
  final String slug;
  final Map<String, String> attributes;

  bool get soldOut => stock <= 0;
  bool get onSale => oldPrice > price;
  int get percentOff => onSale ? ((1 - price / oldPrice) * 100).round() : 0;

  factory Product.fromJson(Map<String, dynamic> p) {
    final vendor = p['vendor'] is Map ? asMap(p['vendor']) : <String, dynamic>{};
    final category = p['category'] is Map ? asMap(p['category']) : <String, dynamic>{};
    final rawPrice = numOf(p['price']);
    final discount = numOf(p['discountPrice']);
    final active = discount > 0 && discount < rawPrice ? discount : rawPrice;
    final media = asMap(p['media']);
    final attrs = asMap(p['attributes']);
    final galleryRaw = media['gallery'] is List
        ? media['gallery'] as List
        : (p['gallery'] is List ? p['gallery'] as List : const []);
    final gallery = galleryRaw.map(resolveImageUrl).where((e) => e.isNotEmpty).toList();
    final main = resolveImageUrl(
      media['mainImage'] ?? p['mainImage'] ?? (galleryRaw.isNotEmpty ? galleryRaw.first : ''),
    );
    String attr(String k) => strOf(attrs[k] ?? p[k]);
    return Product(
      id: strOf(p['_id'] ?? p['id'] ?? p['publicId']),
      publicId: strOf(p['publicId']),
      name: strOf(p['name']),
      category: strOf(category['name'] ?? (p['category'] is String ? p['category'] : null), 'Uncategorized'),
      brand: strOf(p['brand']),
      vendor: strOf(
        vendor['companyName'] ?? vendor['Fullname'] ?? vendor['fullName'],
        'MVEC Seller',
      ),
      vendorId: strOf(
        vendor['_id'] ?? vendor['id'] ?? (p['vendor'] is String ? p['vendor'] : null) ?? p['vendorId'],
      ),
      price: active,
      oldPrice: discount > 0 && discount < rawPrice ? rawPrice : 0,
      rating: numOf(p['averageRating']),
      reviews: numOf(p['reviewCount']).toInt(),
      stock: numOf(p['stockQuantity']).toInt(),
      sku: strOf(p['sku']),
      image: main,
      gallery: gallery,
      description: strOf(p['description'] ?? p['shortDescription']),
      status: strOf(p['status'], 'ACTIVE'),
      slug: strOf(p['slug']),
      attributes: {
        'Color': attr('color'),
        'Size': attr('size'),
        'Material': attr('material'),
        'Weight': attr('weight'),
        'Capacity': attr('capacity'),
        'Model': attr('model'),
      },
    );
  }

  /// Fields the cart/wishlist need from a product.
  Map<String, dynamic> toSnapshot() => {
        'id': id,
        'name': name,
        'image': image,
        'price': price,
        'stock': stock,
        'sku': sku,
        'vendor': vendor,
        'vendorId': vendorId,
      };
}

/// A store as listed in `/vendors`.
class StoreSummary {
  const StoreSummary({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.rating,
    required this.slug,
    required this.logoUrl,
    required this.bannerUrl,
    required this.verified,
    required this.location,
    required this.description,
    this.products = 0,
  });

  /// Store id used in `/vendors/:id`.
  final String id;

  /// The vendor's account id, which products reference.
  final String userId;
  final String name;
  final String category;
  final num rating;
  final String slug;
  final String logoUrl;
  final String bannerUrl;
  final bool verified;
  final String location;
  final String description;
  final int products;

  factory StoreSummary.fromJson(Map<String, dynamic> v) {
    final loc = v['location'];
    return StoreSummary(
      id: strOf(v['id'] ?? v['_id']),
      userId: strOf(v['userId'] ?? v['user']),
      name: strOf(v['businessName'], 'Vendor'),
      category: strOf(v['category']),
      rating: numOf(v['ratingAvg']),
      slug: strOf(v['slug']),
      logoUrl: resolveImageUrl(v['logoUrl']),
      bannerUrl: resolveImageUrl(v['bannerUrl']),
      verified: v['verificationStatus'] == 'VERIFIED',
      location: loc is String ? loc : strOf(asMap(loc)['city'], 'Rwanda'),
      description: strOf(v['description']),
    );
  }

  StoreSummary withProducts(int count, String fallbackCategory) => StoreSummary(
        id: id,
        userId: userId,
        name: name,
        category: category.isNotEmpty ? category : fallbackCategory,
        rating: rating,
        slug: slug,
        logoUrl: logoUrl,
        bannerUrl: bannerUrl,
        verified: verified,
        location: location,
        description: description,
        products: count,
      );
}

class CategoryInfo {
  const CategoryInfo({required this.id, required this.name, required this.slug, required this.imageUrl});
  final String id;
  final String name;
  final String slug;
  final String imageUrl;

  factory CategoryInfo.fromJson(Map<String, dynamic> c) => CategoryInfo(
        id: strOf(c['id'] ?? c['_id']),
        name: strOf(c['name']),
        slug: strOf(c['slug']),
        imageUrl: resolveImageUrl(c['imageUrl']),
      );
}
