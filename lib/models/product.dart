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
    this.deal,
    this.variants = const [],
    this.variantOptions = const [],
    this.sellerBadges = const [],
    this.bulkSeller = false,
    this.productId = '',
    this.variantLabel = '',
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

  /// The flash deal as buyers see it now (null: none on or coming).
  final Deal? deal;

  /// Sizes/colours, each with its own stock and price; buyers choose one.
  final List<ProductVariant> variants;
  final List<({String name, List<String> values})> variantOptions;

  /// Earned seller badges: [(code, label, hint)].
  final List<({String code, String label, String hint})> sellerBadges;

  /// Sold by a supplier (wholesaler): flagged "Supplier · bulk".
  final bool bulkSeller;

  /// For one size/colour as a cart line: the product's own id and "Red / M".
  final String productId;
  final String variantLabel;

  bool get hasVariants => variants.isNotEmpty;
  bool get soldOut => hasVariants ? variants.every((v) => v.stock <= 0) : stock <= 0;
  bool get onSale => oldPrice > price;
  int get percentOff => onSale ? ((1 - price / oldPrice) * 100).round() : 0;

  factory Product.fromJson(Map<String, dynamic> p) {
    final vendor = p['vendor'] is Map ? asMap(p['vendor']) : <String, dynamic>{};
    final category = p['category'] is Map ? asMap(p['category']) : <String, dynamic>{};
    final rawPrice = numOf(p['price']);
    // A live flash deal wins over a regular discount.
    final deal = p['deal'] is Map ? Deal.fromJson(asMap(p['deal'])) : null;
    final discount = deal != null && deal.live ? deal.price : numOf(p['discountPrice']);
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
        'Ikiguzi Seller',
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
      deal: deal,
      variants: [for (final v in asMaps(p['variants'])) ProductVariant.fromJson(v)],
      variantOptions: [
        for (final o in asMaps(p['variantOptions']))
          (name: strOf(o['name']), values: [for (final v in (o['values'] as List? ?? const [])) '$v']),
      ],
      sellerBadges: [
        for (final b in asMaps(p['sellerBadges'])) (code: strOf(b['code']), label: strOf(b['label']), hint: strOf(b['hint'])),
      ],
      bulkSeller: p['bulkSeller'] == true,
    );
  }

  /// One size/colour of this product as something to put in the cart.
  Product forVariant(ProductVariant v) => Product(
        id: v.key,
        publicId: publicId,
        name: name,
        category: category,
        brand: brand,
        vendor: vendor,
        vendorId: vendorId,
        price: v.price,
        oldPrice: v.ownPrice == null ? oldPrice : 0,
        rating: rating,
        reviews: reviews,
        stock: v.stock,
        sku: v.sku.isEmpty ? sku : v.sku,
        image: v.image.isEmpty ? image : v.image,
        gallery: gallery,
        description: description,
        status: status,
        slug: slug,
        attributes: attributes,
        deal: deal,
        sellerBadges: sellerBadges,
        bulkSeller: bulkSeller,
        productId: id,
        variantLabel: v.label,
      );

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
        if (variantLabel.isNotEmpty) 'variantLabel': variantLabel,
        if (productId.isNotEmpty) 'productId': productId,
      };
}

/// A flash deal: a lower price for a while, maybe for a limited number of units.
class Deal {
  const Deal({required this.price, required this.startsAt, required this.endsAt, required this.live, required this.left, required this.percentOff});
  final num price;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool live;

  /// Units left at the deal price; null when there's no limit.
  final int? left;
  final int percentOff;

  factory Deal.fromJson(Map<String, dynamic> d) => Deal(
        price: numOf(d['price']),
        startsAt: parseDate(d['startsAt']),
        endsAt: parseDate(d['endsAt']),
        live: d['live'] == true,
        left: d['left'] == null ? null : numOf(d['left']).toInt(),
        percentOff: numOf(d['percentOff']).toInt(),
      );
}

/// One size/colour of a product.
class ProductVariant {
  const ProductVariant({required this.id, required this.key, required this.label, required this.options, required this.price, required this.ownPrice, required this.stock, required this.image, required this.sku});
  final String id;

  /// "productId~variantId": what the cart and checkout take.
  final String key;
  final String label;
  final Map<String, String> options;
  final num price;
  final num? ownPrice;
  final int stock;
  final String image;
  final String sku;

  factory ProductVariant.fromJson(Map<String, dynamic> v) => ProductVariant(
        id: strOf(v['id']),
        key: strOf(v['key']),
        label: strOf(v['label']),
        options: {for (final e in asMap(v['options']).entries) e.key: '${e.value}'},
        price: numOf(v['price']),
        ownPrice: v['ownPrice'] == null ? null : numOf(v['ownPrice']),
        stock: numOf(v['stockQuantity']).toInt(),
        image: resolveImageUrl(v['image']),
        sku: strOf(v['sku']),
      );
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
