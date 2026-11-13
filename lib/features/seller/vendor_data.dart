import '../../portal/api.dart';
import 'seller_common.dart';

/// Orders, products and commission rate behind the analytics and reports pages.
Future<({List<Map<String, dynamic>> orders, List<Map<String, dynamic>> products, double commission})> vendorData() async {
  final r = await Future.wait<dynamic>([
    jlist('/orders/vendor/orders', 'orders'),
    vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    jget('/payouts/balance').catchError((_) => <String, dynamic>{}),
  ]);
  return (orders: r[0] as List<Map<String, dynamic>>, products: r[1] as List<Map<String, dynamic>>, commission: parsePercent((r[2] as Map)['commissionRate']));
}
