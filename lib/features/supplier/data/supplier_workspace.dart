import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/api_config.dart';

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
    this.minimumOrderQuantity = 1,
    this.bulkDiscount = 0,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String imageUrl;
  final double price;
  final int stock;
  final String status;
  final int minimumOrderQuantity;
  final double bulkDiscount;

  factory SupplierProduct.fromJson(
    Map<String, dynamic> json,
  ) => SupplierProduct(
    id: '${json['_id'] ?? json['id'] ?? ''}',
    name: '${json['name'] ?? json['title'] ?? 'Untitled product'}',
    category: '${json['category'] ?? json['categoryName'] ?? 'General'}',
    description: '${json['description'] ?? ''}',
    imageUrl:
        '${json['imageUrl'] ?? json['image'] ?? json['media']?['mainImage'] ?? ''}',
    price:
        (json['wholesalePrice'] as num?)?.toDouble() ??
        (json['price'] as num?)?.toDouble() ??
        0,
    stock:
        (json['stockQuantity'] as num?)?.toInt() ??
        (json['stock'] as num?)?.toInt() ??
        0,
    status: '${json['status'] ?? 'ACTIVE'}',
    minimumOrderQuantity:
        (json['moq'] as num?)?.toInt() ??
        (json['minimumOrderQuantity'] as num?)?.toInt() ??
        1,
    bulkDiscount: (json['bulkDiscount'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'description': description,
    'imageUrl': imageUrl,
    'wholesalePrice': price,
    'stockQuantity': stock,
    'moq': minimumOrderQuantity,
    'bulkDiscount': bulkDiscount,
    'status': status,
  };

  SupplierProduct copyWith({
    int? stock,
    double? price,
    String? status,
    int? minimumOrderQuantity,
    double? bulkDiscount,
  }) => SupplierProduct(
    id: id,
    name: name,
    category: category,
    description: description,
    imageUrl: imageUrl,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    status: status ?? this.status,
    minimumOrderQuantity: minimumOrderQuantity ?? this.minimumOrderQuantity,
    bulkDiscount: bulkDiscount ?? this.bulkDiscount,
  );
}

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

  factory SupplierOrder.fromJson(Map<String, dynamic> json) => SupplierOrder(
    id: '${json['_id'] ?? json['id'] ?? ''}',
    buyer: '${json['buyerName'] ?? json['buyer'] ?? 'Marketplace buyer'}',
    product: '${json['productName'] ?? json['product'] ?? 'Supplier item'}',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    total: (json['total'] as num?)?.toDouble() ?? 0,
    status: '${json['fulfillmentStatus'] ?? json['status'] ?? 'Pending'}',
    requestedAt:
        DateTime.tryParse(
          '${json['requestedAt'] ?? json['createdAt'] ?? ''}',
        ) ??
        DateTime.now(),
  );
}

class SupplierNotice {
  const SupplierNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool read;

  factory SupplierNotice.fromJson(Map<String, dynamic> json) => SupplierNotice(
    id: '${json['_id'] ?? json['id'] ?? ''}',
    title: '${json['title'] ?? 'Supplier update'}',
    message: '${json['message'] ?? ''}',
    createdAt:
        DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
    read: json['read'] == true,
  );
}

class SupplierProfile {
  const SupplierProfile({
    required this.businessName,
    required this.email,
    required this.phone,
    required this.address,
    required this.orderNotifications,
    required this.stockNotifications,
  });

  final String businessName;
  final String email;
  final String phone;
  final String address;
  final bool orderNotifications;
  final bool stockNotifications;

  factory SupplierProfile.fromJson(Map<String, dynamic> json) =>
      SupplierProfile(
        businessName: '${json['businessName'] ?? json['companyName'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        address: '${json['address'] ?? ''}',
        orderNotifications: json['orderNotifications'] != false,
        stockNotifications: json['stockNotifications'] != false,
      );

  Map<String, dynamic> toJson() => {
    'businessName': businessName,
    'email': email,
    'phone': phone,
    'address': address,
    'orderNotifications': orderNotifications,
    'stockNotifications': stockNotifications,
  };
}

class SupplierWorkspaceData {
  const SupplierWorkspaceData({
    required this.products,
    required this.orders,
    required this.notifications,
    required this.profile,
  });

  final List<SupplierProduct> products;
  final List<SupplierOrder> orders;
  final List<SupplierNotice> notifications;
  final SupplierProfile profile;
}

abstract interface class SupplierWorkspaceService {
  Future<List<SupplierProduct>> products();
  Future<List<SupplierOrder>> orders();
  Future<List<SupplierNotice>> notifications();
  Future<SupplierProfile> profile();
  Future<void> saveProduct(SupplierProduct product);
  Future<void> updateStock(String id, int stock);
  Future<void> updateOrderStatus(String id, String status);
  Future<void> markNotificationRead(String id);
  Future<void> saveProfile(SupplierProfile profile);
}

class DemoSupplierWorkspaceService implements SupplierWorkspaceService {
  final List<SupplierProduct> _products = [
    const SupplierProduct(
      id: 'sp-101',
      name: 'Arabica Coffee Beans',
      category: 'Beverages',
      description: 'Washed specialty beans from Nyamasheke, medium roast.',
      imageUrl: 'https://picsum.photos/seed/mvec-coffee/320/240',
      price: 12500,
      stock: 84,
      status: 'ACTIVE',
      minimumOrderQuantity: 10,
      bulkDiscount: 8,
    ),
    const SupplierProduct(
      id: 'sp-102',
      name: 'Fresh Avocados',
      category: 'Produce',
      description: 'Ripe Hass avocados, packed in reusable crates.',
      imageUrl: 'https://picsum.photos/seed/mvec-avocado/320/240',
      price: 900,
      stock: 12,
      status: 'ACTIVE',
      minimumOrderQuantity: 5,
      bulkDiscount: 5,
    ),
    const SupplierProduct(
      id: 'sp-103',
      name: 'Dried Red Kidney Beans',
      category: 'Grains & pulses',
      description: 'Sorted, clean and ready for wholesale delivery.',
      imageUrl: 'https://picsum.photos/seed/mvec-beans/320/240',
      price: 2400,
      stock: 0,
      status: 'OUT_OF_STOCK',
      minimumOrderQuantity: 10,
      bulkDiscount: 8,
    ),
    const SupplierProduct(
      id: 'sp-104',
      name: 'Raw Forest Honey',
      category: 'Pantry',
      description: 'Unfiltered honey sourced from local beekeepers.',
      imageUrl: 'https://picsum.photos/seed/mvec-honey/320/240',
      price: 7800,
      stock: 31,
      status: 'ACTIVE',
      minimumOrderQuantity: 5,
      bulkDiscount: 5,
    ),
  ];

  final List<SupplierOrder> _orders = [
    SupplierOrder(
      id: 'MV-4821',
      buyer: 'Kigali Market Kitchen',
      product: 'Arabica Coffee Beans',
      quantity: 8,
      total: 100000,
      status: 'Pending',
      requestedAt: DateTime(2026, 9, 28),
    ),
    SupplierOrder(
      id: 'MV-4814',
      buyer: 'Green Basket Ltd',
      product: 'Fresh Avocados',
      quantity: 24,
      total: 21600,
      status: 'Confirmed',
      requestedAt: DateTime(2026, 9, 27),
    ),
    SupplierOrder(
      id: 'MV-4792',
      buyer: 'Umurimo Grocers',
      product: 'Raw Forest Honey',
      quantity: 6,
      total: 46800,
      status: 'Ready to ship',
      requestedAt: DateTime(2026, 9, 25),
    ),
    SupplierOrder(
      id: 'MV-4760',
      buyer: 'Kivu Cafe',
      product: 'Arabica Coffee Beans',
      quantity: 4,
      total: 50000,
      status: 'Completed',
      requestedAt: DateTime(2026, 9, 22),
    ),
  ];

  final List<SupplierNotice> _notifications = [
    SupplierNotice(
      id: 'sn-1',
      title: 'New order request',
      message:
          'Kigali Market Kitchen requested 8 bags of Arabica Coffee Beans.',
      createdAt: DateTime(2026, 9, 28, 9),
      read: false,
    ),
    SupplierNotice(
      id: 'sn-2',
      title: 'Low stock reminder',
      message: 'Fresh Avocados are down to 12 units.',
      createdAt: DateTime(2026, 9, 27, 14),
      read: false,
    ),
    SupplierNotice(
      id: 'sn-3',
      title: 'Payout processed',
      message: 'Your RWF 50,000 payout for MV-4760 is complete.',
      createdAt: DateTime(2026, 9, 23, 11),
      read: true,
    ),
  ];

  SupplierProfile _profile = const SupplierProfile(
    businessName: 'Rwanda Fresh Produce Co.',
    email: 'supplier@mvec.rw',
    phone: '+250 788 245 610',
    address: 'KN 5 Road, Kigali, Rwanda',
    orderNotifications: true,
    stockNotifications: true,
  );

  @override
  Future<List<SupplierProduct>> products() async =>
      List.unmodifiable(_products);
  @override
  Future<List<SupplierOrder>> orders() async => List.unmodifiable(_orders);
  @override
  Future<List<SupplierNotice>> notifications() async =>
      List.unmodifiable(_notifications);
  @override
  Future<SupplierProfile> profile() async => _profile;

  @override
  Future<void> saveProduct(SupplierProduct product) async {
    final index = _products.indexWhere((item) => item.id == product.id);
    if (index < 0) {
      _products.insert(
        0,
        SupplierProduct(
          id: 'sp-${DateTime.now().microsecondsSinceEpoch}',
          name: product.name,
          category: product.category,
          description: product.description,
          imageUrl: product.imageUrl,
          price: product.price,
          stock: product.stock,
          status: product.stock == 0 ? 'OUT_OF_STOCK' : 'ACTIVE',
          minimumOrderQuantity: product.minimumOrderQuantity,
          bulkDiscount: product.bulkDiscount,
        ),
      );
    } else {
      _products[index] = product.copyWith(
        status: product.stock == 0 ? 'OUT_OF_STOCK' : 'ACTIVE',
      );
    }
  }

  @override
  Future<void> updateStock(String id, int stock) async {
    final index = _products.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Product not found');
    _products[index] = _products[index].copyWith(
      stock: stock,
      status: stock == 0 ? 'OUT_OF_STOCK' : 'ACTIVE',
    );
  }

  @override
  Future<void> updateOrderStatus(String id, String status) async {
    final index = _orders.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Order not found');
    final order = _orders[index];
    _orders[index] = SupplierOrder(
      id: order.id,
      buyer: order.buyer,
      product: order.product,
      quantity: order.quantity,
      total: order.total,
      status: status,
      requestedAt: order.requestedAt,
    );
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final notice = _notifications[index];
    _notifications[index] = SupplierNotice(
      id: notice.id,
      title: notice.title,
      message: notice.message,
      createdAt: notice.createdAt,
      read: true,
    );
  }

  @override
  Future<void> saveProfile(SupplierProfile profile) async => _profile = profile;
}

class ApiSupplierWorkspaceService implements SupplierWorkspaceService {
  ApiSupplierWorkspaceService(this._api);
  final ApiClient _api;

  @override
  Future<List<SupplierProduct>> products() async =>
      listJson(await _api.get('/supplier/products'), [
        'products',
      ]).map(SupplierProduct.fromJson).toList();

  @override
  Future<List<SupplierOrder>> orders() async =>
      listJson(await _api.get('/supplier/orders'), [
        'orders',
      ]).map(SupplierOrder.fromJson).toList();

  @override
  Future<List<SupplierNotice>> notifications() async =>
      listJson(await _api.get('/supplier/notifications'), [
        'notifications',
      ]).map(SupplierNotice.fromJson).toList();

  @override
  Future<SupplierProfile> profile() async => SupplierProfile.fromJson(
    singleJson(await _api.get('/supplier/profile'), ['profile', 'supplier']),
  );

  @override
  Future<void> saveProduct(SupplierProduct product) async {
    if (product.id.isEmpty) {
      await _api.post('/supplier/products', body: product.toJson());
    } else {
      await _api.patch(
        '/supplier/products/${product.id}',
        body: product.toJson(),
      );
    }
  }

  @override
  Future<void> updateStock(String id, int stock) async {
    await _api.patch(
      '/supplier/products/$id/stock',
      body: {'stockQuantity': stock},
    );
  }

  @override
  Future<void> updateOrderStatus(String id, String status) async {
    await _api.patch(
      '/supplier/orders/$id/fulfillment',
      body: {'status': status},
    );
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _api.patch('/supplier/notifications/$id', body: {'read': true});
  }

  @override
  Future<void> saveProfile(SupplierProfile profile) async {
    await _api.patch('/supplier/profile', body: profile.toJson());
  }
}

final supplierWorkspaceServiceProvider = Provider<SupplierWorkspaceService>(
  (ref) =>
      kDemoMode
          ? DemoSupplierWorkspaceService()
          : ApiSupplierWorkspaceService(ref.watch(apiProvider)),
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
    final values = await Future.wait<dynamic>([
      _service.products(),
      _service.orders(),
      _service.notifications(),
      _service.profile(),
    ]);
    return SupplierWorkspaceData(
      products: values[0] as List<SupplierProduct>,
      orders: values[1] as List<SupplierOrder>,
      notifications: values[2] as List<SupplierNotice>,
      profile: values[3] as SupplierProfile,
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
  Future<void> updateStock(String id, int stock) =>
      _change(() => _service.updateStock(id, stock));
  Future<void> updateOrderStatus(String id, String status) =>
      _change(() => _service.updateOrderStatus(id, status));
  Future<void> markNotificationRead(String id) =>
      _change(() => _service.markNotificationRead(id));
  Future<void> saveProfile(SupplierProfile profile) =>
      _change(() => _service.saveProfile(profile));
}
