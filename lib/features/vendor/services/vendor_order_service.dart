import '../../../core/api_client.dart';
import '../models/vendor_order.dart';

/// Contract for the vendor's order data source.
///
/// The UI talks to this interface only, so the live [ApiVendorOrderService] can
/// be swapped for another transport (a cache, an offline store) without
/// touching the screens; see `vendor_dependencies.dart` for the wiring.
///
/// Every method throws on failure so the Riverpod layer can surface a message;
/// the screens render the error state with a retry.
abstract class VendorOrderService {
  /// True when this service is answering from a bundled/local dataset rather
  /// than the API. The shipped implementation is always API-backed, so this is
  /// always false; it is retained so the screens can branch without changing.
  bool get isDemo;

  /// Orders assigned to the signed-in vendor, newest first, with per-status
  /// counts for the filter tabs.
  Future<VendorOrderPage> orders({VendorOrderStatus? status, String search = ''});

  /// Single order by id or human order number.
  Future<VendorOrder> order(String id);

  /// Moves an order to [status]. [trackingCode] is required to move into
  /// [VendorOrderStatus.shipped]; [deliveryOtp] is required to move into
  /// [VendorOrderStatus.delivered], which is what releases escrow.
  Future<VendorOrder> updateStatus(
    String id,
    VendorOrderStatus status, {
    String? trackingCode,
    String? courierName,
    String? deliveryOtp,
  });

  /// Cancels an order, refunding the buyer and returning the goods to stock.
  Future<VendorOrder> cancel(String id, {String? reason});
}

/// Orders plus the counts that drive the filter tabs.
class VendorOrderPage {
  const VendorOrderPage({required this.orders, this.counts = const {}});

  final List<VendorOrder> orders;

  /// How many orders sit in each status, so tabs can render `"Pending 3"`.
  /// Always includes a `null` key for the unfiltered total.
  final Map<VendorOrderStatus?, int> counts;

  int get total => counts[null] ?? orders.length;
}

/// Talks to the platform's order API.
class ApiVendorOrderService implements VendorOrderService {
  ApiVendorOrderService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<VendorOrderPage> orders({VendorOrderStatus? status, String search = ''}) async {
    final res = await _api.get('/orders/vendor/orders');
    final list = listJson(res, ['orders', 'data']).map(VendorOrder.fromJson).toList();
    final filtered = list.where((order) {
      if (status != null && order.status != status) return false;
      if (search.trim().isEmpty) return true;
      final term = search.trim().toLowerCase();
      return order.number.toLowerCase().contains(term) ||
          order.buyerName.toLowerCase().contains(term) ||
          order.items.any((item) => item.name.toLowerCase().contains(term));
    }).toList();
    return VendorOrderPage(
      orders: filtered,
      counts: {
        for (final s in VendorOrderStatus.values)
          s: list.where((o) => o.status == s).length,
        null: list.length,
      },
    );
  }

  @override
  Future<VendorOrder> order(String id) async {
    final res = await _api.get('/orders/$id');
    return VendorOrder.fromJson(singleJson(res, ['order']));
  }

  @override
  Future<VendorOrder> updateStatus(
    String id,
    VendorOrderStatus status, {
    String? trackingCode,
    String? courierName,
    String? deliveryOtp,
  }) async {
    final res = await _api.patch('/orders/$id/status', body: {
      'status': status == VendorOrderStatus.pending
          ? 'PENDING'
          : status == VendorOrderStatus.processing
              ? 'PROCESSING'
              : status == VendorOrderStatus.shipped
                  ? 'SHIPPED'
                  : status == VendorOrderStatus.delivered
                      ? 'DELIVERED'
                      : 'CANCELLED',
      if (trackingCode != null && trackingCode.trim().isNotEmpty) 'trackingCode': trackingCode.trim(),
      if (courierName != null && courierName.trim().isNotEmpty) 'courierName': courierName.trim(),
      if (deliveryOtp != null && deliveryOtp.trim().isNotEmpty) 'deliveryOtp': deliveryOtp.trim(),
    });
    return VendorOrder.fromJson(singleJson(res, ['order']));
  }

  @override
  Future<VendorOrder> cancel(String id, {String? reason}) async {
    throw ApiException(
      'The backend only allows buyers or administrators to cancel orders.',
    );
  }
}
