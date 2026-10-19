import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/format.dart';

const _visitorKey = 'mvec_visitor_id';

/// Opaque id minted by the server on the first referral click. Checkout sends
/// it so the server can credit the affiliate whose link was clicked.
Future<String> getVisitorId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_visitorKey) ?? '';
  } catch (_) {
    return '';
  }
}

Future<void> saveVisitorId(String id) async {
  if (id.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_visitorKey, id);
  } catch (_) {}
}

/// Server cart (`/api/cart`).
class CartApi {
  CartApi._();
  static final _api = Api.instance;

  static Future<Map<String, dynamic>> get() async =>
      asMap(asMap(await _api.get('/cart'))['cart']);

  static Future<Map<String, dynamic>> add(String productId, int quantity) async =>
      asMap(asMap(await _api.post('/cart', body: {'productId': productId, 'quantity': quantity}))['cart']);

  static Future<Map<String, dynamic>> updateQuantity(String productId, int quantity) async =>
      asMap(asMap(await _api.put('/cart/items/$productId', body: {'quantity': quantity}))['cart']);

  static Future<Map<String, dynamic>> remove(String productId) async =>
      asMap(asMap(await _api.delete('/cart/items/$productId'))['cart']);

  static Future<void> clear() async => _api.delete('/cart');
}

/// A buyer's delivery details for checkout.
class CheckoutRequest {
  CheckoutRequest({
    required this.fulfilment,
    required this.method,
    required this.recipientName,
    required this.recipientPhone,
    this.recipientEmail = '',
    this.province = '',
    this.district = '',
    this.sector = '',
    this.street = '',
    this.couponCode,
  });

  /// `pickup` or `delivery`.
  final String fulfilment;

  /// `pickup`, `standard` or `express`.
  final String method;
  final String recipientName;
  final String recipientPhone;
  final String recipientEmail;
  final String province;
  final String district;
  final String sector;
  final String street;
  final String? couponCode;

  bool get isDelivery => fulfilment == 'delivery';

  Future<Map<String, dynamic>> toBody() async {
    final visitor = await getVisitorId();
    return {
      'shippingAddress': isDelivery
          ? {
              'street': street.trim(),
              'district': district,
              'sector': sector.trim(),
              'province': province,
              'country': 'Rwanda',
            }
          : <String, dynamic>{},
      'recipient': {
        'name': recipientName.trim(),
        'phone': recipientPhone.trim(),
        'email': recipientEmail.trim(),
      },
      'deliveryMethod': method,
      'shippingMethod': method.toUpperCase(),
      'paymentMethod': 'MOMO',
      if (visitor.isNotEmpty) 'visitorId': visitor,
      if (couponCode != null && couponCode!.isNotEmpty) 'couponCode': couponCode,
    };
  }
}

/// Orders (`/api/orders`).
class OrdersApi {
  OrdersApi._();
  static final _api = Api.instance;

  static Map<String, dynamic> _withId(Map<String, dynamic> order) =>
      order.isEmpty ? order : {...order, 'id': order['id'] ?? order['_id']};

  /// Order from the signed-in account's cart.
  static Future<Map<String, dynamic>> checkout(CheckoutRequest r) async {
    final res = asMap(await _api.post('/orders/checkout', body: await r.toBody()));
    return {...res, 'order': _withId(asMap(res['order']))};
  }

  /// Order for specific items (buy now, and guests whose basket is on the phone).
  static Future<Map<String, dynamic>> directCheckout(
    CheckoutRequest r,
    List<({String productId, int quantity})> items,
  ) async {
    final body = await r.toBody();
    body['items'] = [
      for (final i in items) {'productId': i.productId, 'quantity': i.quantity},
    ];
    final res = asMap(await _api.post('/orders/direct-checkout', body: body));
    return {...res, 'order': _withId(asMap(res['order']))};
  }

  static Future<List<Map<String, dynamic>>> mine() async =>
      asMaps(asMap(await _api.get('/orders/my-orders'))['orders']).map(_withId).toList();

  static Future<Map<String, dynamic>> byId(String id) async {
    if (id.isEmpty || id == 'undefined') throw ApiException('A valid order ID is required.');
    return _withId(asMap(asMap(await _api.get('/orders/$id'))['order']));
  }

  /// `{ order, message }`
  static Future<Map<String, dynamic>> cancel(String id) async {
    final res = asMap(await _api.post('/orders/$id/cancel'));
    return {...res, 'order': _withId(asMap(res['order']))};
  }

  static Future<List<Map<String, dynamic>>> adminAll() async =>
      asMaps(asMap(await _api.get('/orders'))['orders']).map(_withId).toList();

  /// Vendor's orders.
  static Future<Map<String, dynamic>> vendorOrders() async =>
      asMap(await _api.get('/orders/vendor/orders'));

  /// Orders a courier can pick up or deliver.
  static Future<List<Map<String, dynamic>>> deliverable() async =>
      asMaps(asMap(await _api.get('/orders/deliverable'))['orders']).map(_withId).toList();

  static Future<void> confirmDelivery(String id, String otp) async =>
      _api.patch('/orders/$id/deliver', body: {'deliveryOtp': otp});
}

/// Payments (`/api/payments`).
class PaymentsApi {
  PaymentsApi._();
  static final _api = Api.instance;

  /// MTN MoMo or Airtel Money; the provider is detected from the number.
  static Future<Map<String, dynamic>> payMobileMoney(String orderId, String phone) async =>
      asMap(await _api.post('/payments/pay', body: {'orderId': orderId, 'phoneNumber': phone}));

  /// Card on Flutterwave's page -> `{checkoutUrl, paymentId, status}`.
  static Future<Map<String, dynamic>> payCard(String orderId) async =>
      asMap(await _api.post('/payments/pay/card', body: {'orderId': orderId}));

  /// K-Pay: `method` is `momo`, `card` or `spenn`.
  static Future<Map<String, dynamic>> payKpay(String orderId, String method, String phone) async =>
      asMap(await _api.post('/payments/pay/kpay', body: {
        'orderId': orderId,
        'method': method,
        if (phone.isNotEmpty) 'phoneNumber': phone,
      }));

  /// Asks the backend to reconcile with the gateway and returns the latest state.
  static Future<Map<String, dynamic>> status(String paymentId) async =>
      asMap(await _api.get('/payments/status/$paymentId'));
}

/// Delivery fee quotes and coupons used at checkout.
class CheckoutApi {
  CheckoutApi._();
  static final _api = Api.instance;

  static Future<Map<String, dynamic>> quote({
    required String method,
    required List<({String productId, int qty})> items,
    String? province,
    String? district,
  }) async =>
      asMap(await _api.post('/shipping/quote', body: {
        if (province != null && district != null) 'address': {'province': province, 'district': district},
        'method': method,
        'items': [
          for (final i in items) {'productId': i.productId, 'qty': i.qty},
        ],
      }));

  static Future<Map<String, dynamic>> validateCoupon({
    required String code,
    required List<({String productId, int qty})> items,
    required String shippingMethod,
    String? province,
    String? district,
  }) async =>
      asMap(await _api.post('/promotions/validate', body: {
        'code': code,
        'items': [
          for (final i in items) {'productId': i.productId, 'qty': i.qty},
        ],
        'shippingMethod': shippingMethod,
        if (province != null && district != null)
          'shippingAddress': {'province': province, 'district': district},
      }));
}

/// Disputes / refunds the buyer reported (`/api/disputes`).
class DisputesApi {
  DisputesApi._();
  static final _api = Api.instance;

  static Future<List<Map<String, dynamic>>> mine() async =>
      asMaps(asMap(await _api.get('/disputes/mine'))['data']);

  static Future<List<Map<String, dynamic>>> all({int pageSize = 100}) async =>
      asMaps(asMap(await _api.get('/disputes', query: {'pageSize': pageSize}))['data']);

  static Future<void> open({
    required String orderId,
    required String reason,
    required String description,
    required num amount,
  }) async =>
      _api.post('/disputes', body: {
        'orderId': orderId,
        'reason': reason,
        'description': description,
        'disputedAmount': amount,
      });

  static Future<void> respond(String id, String message) async =>
      _api.post('/disputes/$id/evidence', body: {'message': message});

  static Future<void> arbitrate(String id, Map<String, dynamic> payload) async =>
      _api.post('/disputes/$id/arbitrate', body: payload);
}

/// Buyer ad-removal subscription (`/api/buyer/subscription`).
class BuyerSubscriptionApi {
  BuyerSubscriptionApi._();
  static final _api = Api.instance;

  static Future<Map<String, dynamic>> get() async => asMap(await _api.get('/buyer/subscription'));

  static Future<Map<String, dynamic>> checkout({required String method, String? phone}) async =>
      asMap(await _api.post('/buyer/subscription/checkout',
          body: {'method': method, if (method == 'momo' && phone != null) 'phoneNumber': phone}));

  static Future<Map<String, dynamic>> switchToFree() async =>
      asMap(await _api.post('/buyer/subscription', body: {'plan': 'FREE'}));
}
