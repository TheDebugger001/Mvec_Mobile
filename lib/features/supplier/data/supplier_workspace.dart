import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';

/// A supplier's own wholesale catalogue item.
///
/// Mirrors `Mvec_backend/src/models/WholesaleProduct.js`: the entity is
/// wholesale-oriented, so it carries a `wholesalePrice` *and* a `retailPrice`,
/// a minimum order quantity, a bulk discount and a `media` object — none of
/// which belong on a retail marketplace product.
class SupplierProduct {
  const SupplierProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.stock,
    required this.status,
    this.shortDescription = '',
    this.unit = 'piece',
    this.retailPrice,
    this.minimumOrderQuantity = 1,
    this.bulkDiscount = 0,
    this.gallery = const <String>[],
    this.localImagePath = '',
  });

  final String id;
  final String name;
  final String category;
  final String description;

  /// `media.mainImage` in the backend payload.
  final String imageUrl;

  /// `wholesalePrice` — what the supplier charges per unit at MOQ volume.
  final double price;

  final int stock;

  /// One of `ACTIVE`, `OUT_OF_STOCK` (forced by the backend), `ARCHIVED`.
  final String status;

  final String shortDescription;

  /// Selling unit: `piece`, `kg`, `crate`…
  final String unit;

  final double? retailPrice;
  final int minimumOrderQuantity;

  /// Percentage 0–100.
  final double bulkDiscount;

  final List<String> gallery;

  /// A picture the supplier picked off *this* device, as an absolute file path.
  ///
  /// Deliberately not part of the API contract: there is no upload endpoint to
  /// send the bytes to, so this is a local-only reference the app keeps in
  /// memory for the session. The backend only ever knows [imageUrl].
  final String localImagePath;

  factory SupplierProduct.fromJson(Map<String, dynamic> json) {
    final media = json['media'] is Map
        ? Map<String, dynamic>.from(json['media'] as Map)
        : const <String, dynamic>{};
    final rawGallery = media['gallery'] ?? json['gallery'];
    return SupplierProduct(
      id: _str(json['_id'] ?? json['id']),
      name: _str(json['name'] ?? json['title'], fallback: 'Untitled product'),
      category: _str(
        json['category'] ?? json['categoryName'],
        fallback: 'General',
      ),
      description: _str(json['shortDescription'] ?? json['description']),
      shortDescription: _str(json['shortDescription'] ?? json['description']),
      imageUrl: _str(
        media['mainImage'] ?? json['mainImage'] ?? json['imageUrl'] ?? json['image'],
      ),
      price:
          (json['wholesalePrice'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0,
      retailPrice:
          (json['retailPrice'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble(),
      stock:
          (json['stockQuantity'] as num?)?.toInt() ??
          (json['stock'] as num?)?.toInt() ??
          0,
      status: _str(json['status'], fallback: 'ACTIVE'),
      unit: _str(json['unit'], fallback: 'piece'),
      minimumOrderQuantity:
          (json['moq'] as num?)?.toInt() ??
          (json['minimumOrderQuantity'] as num?)?.toInt() ??
          1,
      bulkDiscount: (json['bulkDiscount'] as num?)?.toDouble() ?? 0,
      gallery:
          rawGallery is List
              ? rawGallery.map((e) => e.toString()).toList()
              : const <String>[],
    );
  }

  /// The payload the backend's `sanitizeWholesalePayload` understands.
  ///
  /// Deliberately limited to the seven fields the web supplier form collects:
  /// name, category, wholesale price, MOQ, stock, bulk discount, description.
  ///
  /// `unit`, `retailPrice`, `media` and `status` are omitted on purpose. The
  /// supplier form no longer collects them, and every one has a safe backend
  /// default on create (`unit: "piece"`, `retailPrice: 0`, empty `media`,
  /// `status: "ACTIVE"` demoted to `OUT_OF_STOCK` when stock is 0). On update
  /// `sanitizeWholesalePayload` falls back to the stored product, so omitting
  /// them preserves existing data instead of blanking it.
  ///
  /// A device-local photo never reaches here. [localImagePath] points at a file
  /// on this phone, which would be meaningless to the backend and to any other
  /// vendor's client, so the media object stays out of the payload until there
  /// is an upload endpoint to turn those bytes into a URL.
  Map<String, dynamic> toJson() => {
    'name': name,
    // The backend's WholesaleProduct has no `description` field; the long text
    // is stored as `shortDescription`.
    'shortDescription': description,
    'category': category,
    'wholesalePrice': price,
    'moq': minimumOrderQuantity,
    'stockQuantity': stock,
    'bulkDiscount': bulkDiscount,
  };

  SupplierProduct copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    String? imageUrl,
    double? price,
    double? retailPrice,
    int? stock,
    String? status,
    String? unit,
    int? minimumOrderQuantity,
    double? bulkDiscount,
    List<String>? gallery,
    String? localImagePath,
  }) => SupplierProduct(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    description: description ?? this.description,
    shortDescription: description ?? shortDescription,
    imageUrl: imageUrl ?? this.imageUrl,
    price: price ?? this.price,
    retailPrice: retailPrice ?? this.retailPrice,
    stock: stock ?? this.stock,
    status: status ?? this.status,
    unit: unit ?? this.unit,
    minimumOrderQuantity: minimumOrderQuantity ?? this.minimumOrderQuantity,
    bulkDiscount: bulkDiscount ?? this.bulkDiscount,
    gallery: gallery ?? this.gallery,
    localImagePath: localImagePath ?? this.localImagePath,
  );

  /// The backend flips status to `OUT_OF_STOCK` whenever `stockQuantity <= 0`,
  /// so it is not a choice the supplier can make.
  bool get isOutOfStock => stock <= 0 || status.toUpperCase() == 'OUT_OF_STOCK';
  bool get isArchived => status.toUpperCase() == 'ARCHIVED';
  bool get isActive => status.toUpperCase() == 'ACTIVE' && !isOutOfStock;

  /// There is no `minStock` on the wholesale model, so low stock is derived
  /// from the MOQ: fewer units left than one order needs.
  bool get isLowStock => !isOutOfStock && stock < minimumOrderQuantity;

  String get stockStatus {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  /// Unit price after the bulk discount, i.e. what a vendor actually pays.
  double get effectivePrice =>
      price * (1 - bulkDiscount.clamp(0, 100) / 100);
}

/// A wholesale order placed against the supplier's catalogue.
///
/// The backend has no `/supplier/orders` route, so these are read from the
/// role-scoped `GET /orders` collection — see [ApiSupplierWorkspaceService].
class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.buyer,
    required this.product,
    required this.quantity,
    required this.total,
    required this.status,
    required this.requestedAt,
  });

  final String id;
  final String buyer;
  final String product;
  final int quantity;
  final double total;
  final String status;
  final DateTime requestedAt;

  factory SupplierOrder.fromJson(Map<String, dynamic> json) {
    final buyer = json['buyer'] ?? json['buyerName'] ?? json['vendor'];
    final items = json['items'];
    final first = items is List && items.isNotEmpty ? items.first : null;
    final firstItem = first is Map ? Map<String, dynamic>.from(first) : null;
    final product =
        firstItem?['name'] ?? json['productName'] ?? json['product'] ?? 'Supplier item';
    return SupplierOrder(
      id: _str(json['_id'] ?? json['id'] ?? json['orderNumber']),
      buyer:
          buyer is Map
              ? _str(
                buyer['businessName'] ?? buyer['Fullname'] ?? buyer['name'],
                fallback: 'Marketplace buyer',
              )
              : _str(buyer, fallback: 'Marketplace buyer'),
      product: _str(product, fallback: 'Supplier item'),
      quantity:
          (firstItem?['quantity'] as num?)?.toInt() ??
          (json['quantity'] as num?)?.toInt() ??
          1,
      total:
          (json['total'] as num?)?.toDouble() ??
          (json['totalAmount'] as num?)?.toDouble() ??
          0,
      status: _str(json['status'] ?? json['fulfillmentStatus'], fallback: 'Pending'),
      requestedAt:
          DateTime.tryParse(_str(json['createdAt'] ?? json['requestedAt'])) ??
          DateTime.now(),
    );
  }
}

/// A supplier-facing notification, read from the role-scoped
/// `GET /notifications` collection.
class SupplierNotice {
  const SupplierNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.read,
    this.type,
    this.actionPath,
    this.actionLabel,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool read;

  /// The notice's kind, e.g. `ORDER`, `PAYOUT`, `DELIVERY`. Used to work out
  /// where the row should lead when the API does not name a destination.
  final String? type;

  /// In-app route the row leads to, e.g. `/supplier/orders`.
  ///
  /// Taken from the payload when the API sends one, otherwise derived by
  /// [supplierNoticeDestination] from [type]. Only ever a `/supplier` path —
  /// see that function for why an arbitrary path is not followed.
  final String? actionPath;

  /// Verb on the row's button, e.g. `Review order`. Derived when absent.
  final String? actionLabel;

  /// Where tapping this notice should take the supplier.
  ///
  /// Prefers what the API asked for, then falls back to the kind of notice so a
  /// feed without destinations is still useful. Anything outside the supplier
  /// portal is refused: the path arrives from the server, and following it
  /// blindly would let a bad payload bounce someone into the admin area.
  String? get destination => supplierNoticeDestination(
    apiPath: actionPath,
    type: type,
    title: title,
  );

  factory SupplierNotice.fromJson(Map<String, dynamic> json) {
    final status = _str(json['status']).toUpperCase();
    return SupplierNotice(
      id: _str(json['_id'] ?? json['id']),
      title: _str(
        json['title'] ?? json['type'],
        fallback: 'Supplier update',
      ),
      message: _str(json['message'] ?? json['body']),
      createdAt:
          DateTime.tryParse(_str(json['createdAt'])) ?? DateTime.now(),
      read: json['read'] == true || status == 'READ',
      type: json['type'] == null ? null : '${json['type']}',
      actionPath: json['actionPath'] == null ? null : '${json['actionPath']}',
      actionLabel: json['actionLabel'] == null ? null : '${json['actionLabel']}',
    );
  }
}

/// Maps a notice to the page that can act on it.
///
/// Order matters: an explicit `apiPath` wins, but only inside the supplier
/// portal. Otherwise the notice's own type decides, and the title is the last
/// resort for feeds that send no type at all. Returns null when nothing matches,
/// which the row renders as "mark read only" rather than a dead button.
String? supplierNoticeDestination({
  String? apiPath,
  String? type,
  String? title,
}) {
  final requested = apiPath?.trim();
  if (requested != null && requested.isNotEmpty) {
    // The portal root is allowed as well as its pages.
    final inPortal =
        requested == '/supplier' || requested.startsWith('/supplier/');
    return inPortal ? requested : null;
  }

  final kind = (type ?? '').trim().toUpperCase();
  switch (kind) {
    case 'ORDER' || 'ORDER_REQUEST' || 'NEW_ORDER' || 'VENDOR_ORDER':
      return '/supplier/orders';
    case 'STOCK' || 'LOW_STOCK' || 'INVENTORY':
      return '/supplier/inventory';
    case 'PRODUCT' || 'CATALOGUE' || 'CATALOG' || 'LISTING':
      return '/supplier/products';
    case 'PAYOUT' || 'PAYMENT' || 'WITHDRAWAL' || 'TRANSACTION' || 'ESCROW':
      return '/supplier/payments';
    case 'DELIVERY' || 'DISPATCH' || 'SHIPMENT' || 'DISPUTE':
      return '/supplier/delivery';
    case 'SUPPLY_REQUEST' || 'SUPPLY' || 'REQUEST':
      return '/supplier/supply-requests';
    case 'TEAM' || 'STAFF' || 'INVITE':
      return '/supplier/team';
    case 'REVIEW' || 'RATING':
      return '/supplier/reviews';
    case 'ACCOUNT' || 'SETTINGS' || 'PROFILE' || 'SECURITY':
      return '/supplier/settings';
  }

  // Feeds that send only a headline: match on what it is talking about.
  final subject = '${type ?? ''} $title'.toLowerCase();
  if (subject.contains('payout') ||
      subject.contains('payment') ||
      subject.contains('escrow')) {
    return '/supplier/payments';
  }
  if (subject.contains('stock') || subject.contains('inventory')) {
    return '/supplier/inventory';
  }
  if (subject.contains('deliver') || subject.contains('ship')) {
    return '/supplier/delivery';
  }
  if (subject.contains('order')) return '/supplier/orders';
  if (subject.contains('supply')) return '/supplier/supply-requests';
  if (subject.contains('team') || subject.contains('staff')) {
    return '/supplier/team';
  }
  return null;
}

/// Button verb for a destination, so the row says what will happen.
String supplierNoticeActionLabel(String? destination, String? apiLabel) {
  final custom = apiLabel?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  return switch (destination) {
    '/supplier/orders' => 'Review orders',
    '/supplier/inventory' => 'Check stock',
    '/supplier/products' => 'Open catalogue',
    '/supplier/payments' => 'View payouts',
    '/supplier/delivery' => 'Track delivery',
    '/supplier/supply-requests' => 'View requests',
    '/supplier/team' => 'Manage team',
    '/supplier/reviews' => 'Read reviews',
    '/supplier/settings' => 'Open settings',
    _ => 'Open',
  };
}

/// The supplier's own business record.
///
/// Mirrors `Mvec_backend/src/models/Supplier.js`: business identity, contact
/// details, a verification state and a `ratingAvg`. `verificationStatus` is
/// owned by the admin — a supplier can read it but never change it.
class SupplierProfile {
  const SupplierProfile({
    required this.businessName,
    required this.email,
    required this.phone,
    required this.address,
    required this.orderNotifications,
    required this.stockNotifications,
    this.id = '',
    this.publicId,
    this.slug,
    this.description = '',
    this.logoUrl = '',
    this.verificationStatus = 'UNVERIFIED',
    this.accountStatus = 'ACTIVE',
    this.ratingAvg,
  });

  final String id;

  /// Human-facing id, e.g. `MVEC-SUP-1A2B3C4D`.
  final String? publicId;
  final String businessName;
  final String? slug;
  final String description;
  final String logoUrl;
  final String email;
  final String phone;
  final String address;

  /// One of `UNVERIFIED`, `PENDING`, `VERIFIED`, `REJECTED`.
  final String verificationStatus;

  /// One of `ACTIVE`, `SUSPENDED`, `BLOCKED`, `UNDER_REVIEW`.
  final String accountStatus;
  final double? ratingAvg;

  final bool orderNotifications;
  final bool stockNotifications;

  factory SupplierProfile.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return SupplierProfile(
      id: _str(json['_id'] ?? json['id']),
      publicId: json['publicId']?.toString(),
      businessName: _str(json['businessName'] ?? json['companyName']),
      slug: json['slug']?.toString(),
      description: _str(json['description']),
      logoUrl: _str(json['logoUrl']),
      email: _str(json['email']),
      phone: _str(json['phone']),
      address: _str(
        location is Map ? location['name'] : location,
      ),
      verificationStatus: _str(
        json['verificationStatus'],
        fallback: 'UNVERIFIED',
      ),
      accountStatus: _str(json['status'], fallback: 'ACTIVE'),
      ratingAvg: (json['ratingAvg'] as num?)?.toDouble(),
      orderNotifications: json['orderNotifications'] != false,
      stockNotifications: json['stockNotifications'] != false,
    );
  }

  /// The payload `POST /suppliers/onboard` and `PATCH /suppliers/me/profile`
  /// accept — `businessName`, `description`, `phone`, `email` and `logoUrl`.
  /// Keys outside that set are dropped server-side, so they are not sent.
  Map<String, dynamic> toJson() => {
    'businessName': businessName,
    'description': description,
    'email': email,
    'phone': phone,
    'logoUrl': logoUrl,
    if (publicId != null) 'publicId': publicId,
  };

  String get display => businessName.isEmpty ? 'Unnamed supplier' : businessName;

  String get verificationStatusOrDefault =>
      verificationStatus.isEmpty ? 'UNVERIFIED' : verificationStatus;

  bool get isVerified => verificationStatusOrDefault == 'VERIFIED';
  bool get isPending =>
      verificationStatusOrDefault == 'PENDING' ||
      verificationStatusOrDefault == 'UNDER_REVIEW';
  bool get isRejected => verificationStatusOrDefault == 'REJECTED';
  bool get isSuspended =>
      accountStatus.toUpperCase() == 'SUSPENDED' ||
      accountStatus.toUpperCase() == 'BLOCKED';

  /// Shows the verification state when one applies, otherwise the account
  /// state, so the portal always has something meaningful to render.
  String get effectiveStatus {
    if (isVerified) return 'VERIFIED';
    if (isPending) return 'PENDING';
    if (isRejected) return 'REJECTED';
    return accountStatus.toUpperCase();
  }

  /// True until the profile exists — `GET /suppliers/me/profile` 404s in this
  /// state, which is a normal first-run state rather than a failure.
  bool get isOnboarded => businessName.isNotEmpty;
}

/// Dashboard counters derived from the catalogue.
///
/// The backend exposes no metrics endpoint, so [SupplierMetrics.fromCatalog]
/// computes the inventory figures from the supplier's own product list. The
/// commerce figures (revenue, order count) come from the order list instead of
/// being invented.
class SupplierMetrics {
  const SupplierMetrics({
    this.totalProducts = 0,
    this.activeProducts = 0,
    this.lowStockProducts = 0,
    this.outOfStockProducts = 0,
    this.totalUnitsInStock = 0,
    this.totalCatalogValue = 0,
    this.openOrders = 0,
    this.salesTotal = 0,
    this.protectedFunds = 0,
  });

  final int totalProducts;
  final int activeProducts;
  final int lowStockProducts;
  final int outOfStockProducts;
  final int totalUnitsInStock;

  /// Sum of `wholesalePrice * stockQuantity` across the catalogue.
  final double totalCatalogValue;

  final int openOrders;

  /// Value of the completed orders.
  final double salesTotal;

  /// Value of the orders that are paid but not yet fulfilled — held by MVEC
  /// until delivery is confirmed.
  final double protectedFunds;

  factory SupplierMetrics.fromCatalog(
    List<SupplierProduct> products, {
    List<SupplierOrder> orders = const <SupplierOrder>[],
  }) {
    var active = 0;
    var low = 0;
    var out = 0;
    var units = 0;
    var value = 0.0;
    for (final p in products) {
      if (p.isArchived) continue;
      if (p.isOutOfStock) {
        out++;
      } else if (p.isLowStock) {
        low++;
      }
      if (p.isActive) active++;
      units += p.stock;
      value += p.price * p.stock;
    }

    var open = 0;
    var sales = 0.0;
    var held = 0.0;
    for (final o in orders) {
      final status = o.status.toLowerCase();
      if (status == 'completed' || status == 'delivered') {
        sales += o.total;
      } else if (status != 'pending' && status != 'cancelled') {
        open++;
        held += o.total;
      }
    }

    return SupplierMetrics(
      totalProducts: products.length,
      activeProducts: active,
      lowStockProducts: low,
      outOfStockProducts: out,
      totalUnitsInStock: units,
      totalCatalogValue: value,
      openOrders: open,
      salesTotal: sales,
      protectedFunds: held,
    );
  }

  bool get hasInventory => totalProducts > 0;
}

class SupplierWorkspaceData {
  const SupplierWorkspaceData({
    required this.products,
    required this.orders,
    required this.notifications,
    required this.profile,
    this.ordersUnavailable = false,
    this.notificationsUnavailable = false,
  });

  final List<SupplierProduct> products;
  final List<SupplierOrder> orders;
  final List<SupplierNotice> notifications;
  final SupplierProfile profile;

  /// `GET /orders` is admin-only on the backend, so a supplier gets 403 rather
  /// than an empty list. The Orders page needs to tell those apart to avoid
  /// claiming "no orders yet" when the truth is "not readable by your role".
  final bool ordersUnavailable;

  /// `GET /notifications/mine` should always work; flag it only so the page can
  /// report a genuine fault instead of a false "you're all caught up".
  final bool notificationsUnavailable;

  SupplierMetrics get metrics => SupplierMetrics.fromCatalog(
    products,
    orders: orders,
  );
}

abstract interface class SupplierWorkspaceService {
  Future<List<SupplierProduct>> products();
  Future<List<SupplierOrder>> orders();
  Future<List<SupplierNotice>> notifications();
  Future<SupplierProfile> profile();
  /// Creates the product when [SupplierProduct.id] is empty, otherwise updates
  /// the existing one.
  Future<void> saveProduct(SupplierProduct product);
  Future<void> deleteProduct(String id);
  Future<void> updateStock(String id, int stock);
  Future<void> updateOrderStatus(String id, String status);
  Future<void> markNotificationRead(String id);
  Future<void> saveProfile(SupplierProfile profile, {required bool isNewProfile});
}

/// Empty-state implementation of [SupplierWorkspaceService].
///
/// The bundled supplier portal this used to serve is gone, so every read now
/// resolves to the same shape [ApiSupplierWorkspaceService] returns for a
/// supplier who has not set anything up yet: no catalogue items, no orders, no
/// notices, and a blank profile — which is what routes the app to its
/// onboarding / not-available states instead of inventing a business.
///
/// Writes throw an [ApiException]: nothing may be kept in memory, so the forms
/// report a real failure instead of silently dropping the supplier's edits.
class EmptySupplierWorkspaceService implements SupplierWorkspaceService {
  /// Blank profile for a supplier that has not completed onboarding. Mirrors the
  /// 404 branch of `ApiSupplierWorkspaceService.profile`.
  static const SupplierProfile _blankProfile = SupplierProfile(
    businessName: '',
    email: '',
    phone: '',
    address: '',
    orderNotifications: true,
    stockNotifications: true,
  );

  @override
  Future<List<SupplierProduct>> products() async => const <SupplierProduct>[];

  @override
  Future<List<SupplierOrder>> orders() async => const <SupplierOrder>[];

  @override
  Future<List<SupplierNotice>> notifications() async =>
      const <SupplierNotice>[];

  @override
  Future<SupplierProfile> profile() async => _blankProfile;

  Never _writeUnsupported(String what) => throw ApiException(
    '$what is not available yet — this endpoint has not shipped.',
    statusCode: 501,
  );

  @override
  Future<void> saveProduct(SupplierProduct product) =>
      _writeUnsupported('Saving products');

  @override
  Future<void> deleteProduct(String id) => _writeUnsupported('Product changes');

  @override
  Future<void> updateStock(String id, int stock) =>
      _writeUnsupported('Stock changes');

  @override
  Future<void> updateOrderStatus(String id, String status) =>
      _writeUnsupported('Order updates');

  @override
  Future<void> markNotificationRead(String id) =>
      _writeUnsupported('Notification updates');

  @override
  Future<void> saveProfile(
    SupplierProfile profile, {
    required bool isNewProfile,
  }) => _writeUnsupported('Saving the profile');
}

/// Live supplier portal, backed by the marketplace backend.
///
/// Every supplier route is resolved from the bearer token (`/me/*`), so no
/// supplier id is ever sent by the app. The catalogue and profile come from
/// `supplier.routes.js`; orders and notifications have no supplier-scoped
/// route, so they are read from the token-scoped collections the rest of the
/// app already uses. A missing collection degrades to an empty list instead of
/// failing the whole workspace.
class ApiSupplierWorkspaceService implements SupplierWorkspaceService {
  ApiSupplierWorkspaceService(this._api);
  final ApiClient _api;

  /// `GET /suppliers/me/products` → `{ success, supplier, count, products }`.
  /// The backend returns the whole catalogue unpaginated.
  @override
  Future<List<SupplierProduct>> products() async =>
      listJson(await _api.get('/suppliers/me/products'), [
        'products',
        'data',
      ]).map(SupplierProduct.fromJson).toList();

  /// `GET /orders`, scoped to the signed-in supplier by the bearer token.
  @override
  Future<List<SupplierOrder>> orders() async =>
      _tolerant(
        () async =>
            listJson(await _api.get('/orders'), ['orders', 'data'])
                .map(SupplierOrder.fromJson)
                .toList(),
      );

  /// `GET /notifications/mine?limit=200` → `{ data, meta }`.
  ///
  /// Must be `/mine`: the collection root `GET /api/notifications` is the admin
  /// oversight route (`authorize("super_admin")`) and 403s for a supplier.
  @override
  Future<List<SupplierNotice>> notifications() async =>
      _tolerant(
        () async =>
            listJson(
              await _api.get('/notifications/mine', query: {'limit': '200'}),
              ['data', 'notifications'],
            ).map(SupplierNotice.fromJson).toList(),
      );

  /// `GET /suppliers/me/profile` → `{ supplier }`.
  ///
  /// 404s until onboarding is complete. That is a normal first-run state, so it
  /// becomes an empty profile and the portal offers onboarding instead of an
  /// error state.
  @override
  Future<SupplierProfile> profile() async {
    try {
      return SupplierProfile.fromJson(
        singleJson(await _api.get('/suppliers/me/profile'), [
          'supplier',
          'profile',
          'data',
        ]),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return const SupplierProfile(
          businessName: '',
          email: '',
          phone: '',
          address: '',
          orderNotifications: true,
          stockNotifications: true,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> saveProduct(SupplierProduct product) async {
    if (product.id.isEmpty) {
      await _api.post('/suppliers/me/products', body: product.toJson());
    } else {
      await _api.put(
        '/suppliers/me/products/${product.id}',
        body: product.toJson(),
      );
    }
  }

  @override
  Future<void> deleteProduct(String id) =>
      _api.delete('/suppliers/me/products/$id');

  /// `PUT` replaces the whole wholesale document, so a stock change is sent as
  /// a full payload rather than a partial one that would blank the rest.
  @override
  Future<void> updateStock(String id, int stock) async {
    final current = (await products()).where((p) => p.id == id).firstOrNull;
    if (current == null) throw StateError('Product not found');
    await saveProduct(
      current.copyWith(
        stock: stock,
        status: stock == 0 ? 'OUT_OF_STOCK' : 'ACTIVE',
      ),
    );
  }

  @override
  Future<void> updateOrderStatus(String id, String status) =>
      _api.patch('/orders/$id/status', body: {'status': status});

  /// `PATCH /notifications/:id/read` — the backend exposes this as a PATCH;
  /// there is no POST twin, so the verb has to match or it 404s.
  @override
  Future<void> markNotificationRead(String id) =>
      _api.patch('/notifications/$id/read');

  /// `POST /suppliers/onboard` creates the profile; `PATCH
  /// /suppliers/me/profile` updates it. A 404 from [profile] is what signals
  /// "not onboarded yet".
  @override
  Future<void> saveProfile(
    SupplierProfile profile, {
    required bool isNewProfile,
  }) async {
    if (isNewProfile) {
      await _api.post('/suppliers/onboard', body: profile.toJson());
    } else {
      await _api.patch('/suppliers/me/profile', body: profile.toJson());
    }
  }

  /// Keeps a secondary collection from taking the whole portal down: a route
  /// the backend does not expose yet yields an empty list, not an error.
  Future<List<T>> _tolerant<T>(Future<List<T>> Function() load) async {
    try {
      return await load();
    } on ApiException {
      return const [];
    }
  }
}

String _str(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value is Map || value is List ? fallback : value.toString();
  return text.isEmpty ? fallback : text;
}

/// The supplier portal always reads from the marketplace backend. Until the
/// catalogue/profile routes answer for a given supplier the app simply shows the
/// empty states the pages already implement.
final supplierWorkspaceServiceProvider = Provider<SupplierWorkspaceService>(
  (ref) => ApiSupplierWorkspaceService(ref.watch(apiProvider)),
);

final supplierWorkspaceProvider =
    AsyncNotifierProvider<SupplierWorkspaceController, SupplierWorkspaceData>(
      SupplierWorkspaceController.new,
    );

class SupplierWorkspaceController extends AsyncNotifier<SupplierWorkspaceData> {
  late SupplierWorkspaceService _service;

  @override
  Future<SupplierWorkspaceData> build() async {
    _service = ref.watch(supplierWorkspaceServiceProvider);
    return _load();
  }

  Future<SupplierWorkspaceData> _load() async {
    // Each section loads independently and in its own error scope. A single
    // unreadable endpoint used to fail this Future.wait, which flipped the one
    // shared provider into AsyncError and blanked *every* supplier page — even
    // pages whose own endpoints were fine. Now a failure degrades only its own
    // section, and the page says so honestly.
    var ordersUnavailable = false;
    var notificationsUnavailable = false;

    final results = await Future.wait<dynamic>([
      _service.products(),
      _service.orders().catchError((Object _) {
        ordersUnavailable = true;
        return <SupplierOrder>[];
      }),
      _service.notifications().catchError((Object _) {
        notificationsUnavailable = true;
        return <SupplierNotice>[];
      }),
      _service.profile(),
    ]);

    return SupplierWorkspaceData(
      products: results[0] as List<SupplierProduct>,
      orders: results[1] as List<SupplierOrder>,
      notifications: results[2] as List<SupplierNotice>,
      profile: results[3] as SupplierProfile,
      ordersUnavailable: ordersUnavailable,
      notificationsUnavailable: notificationsUnavailable,
    );
  }

  Future<void> _change(Future<void> Function() action) async {
    state = const AsyncLoading<SupplierWorkspaceData>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      await action();
      return _load();
    });
  }

  Future<void> saveProduct(SupplierProduct product) =>
      _change(() => _service.saveProduct(product));
  Future<void> deleteProduct(String id) =>
      _change(() => _service.deleteProduct(id));
  Future<void> updateStock(String id, int stock) =>
      _change(() => _service.updateStock(id, stock));
  Future<void> updateOrderStatus(String id, String status) =>
      _change(() => _service.updateOrderStatus(id, status));
  Future<void> markNotificationRead(String id) =>
      _change(() => _service.markNotificationRead(id));
  /// `isNewProfile` keys off the record's identity, not off whether the user
  /// typed a business name: `id` is empty exactly when `GET
  /// /suppliers/me/profile` 404s, which is the first-run state. Deriving it
  /// from [SupplierProfile.isOnboarded] would PATCH a supplier that does not
  /// exist yet, since onboarding requires a non-empty `businessName`.
  Future<void> saveProfile(SupplierProfile profile) =>
      _change(
        () => _service.saveProfile(profile, isNewProfile: profile.id.isEmpty),
      );

  /// True once the supplier has a business profile, i.e. `GET
  /// /suppliers/me/profile` no longer 404s.
  bool get isOnboarded => state.valueOrNull?.profile.isOnboarded ?? false;
}