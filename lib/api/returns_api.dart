import '../core/api_client.dart';
import '../core/format.dart';

/// Returns after delivery (`/api/returns`): the buyer asks, the seller
/// answers, Ikiguzi decides when they disagree. Rows are the server's maps.
class ReturnsApi {
  ReturnsApi._();
  static final _api = Api.instance;

  static Future<Map<String, dynamic>> eligibility(String orderId) async => asMap(await _api.get('/returns/orders/$orderId/eligibility'));

  /// items: [{orderItemId, quantity}]
  static Future<List<Map<String, dynamic>>> create({required String orderId, required List<Map<String, dynamic>> items, required String reason, required String description, List<String> photos = const []}) async =>
      asMaps(asMap(await _api.post('/returns', body: {'orderId': orderId, 'items': items, 'reason': reason, 'description': description, 'photos': photos}))['returns']);

  static Future<List<Map<String, dynamic>>> mine() async => asMaps(asMap(await _api.get('/returns/mine'))['returns']);
  static Future<void> cancel(String id) async => _api.post('/returns/$id/cancel');
  static Future<void> escalate(String id, String reason) async => _api.post('/returns/$id/escalate', body: {'reason': reason});

  // Sellers
  static Future<List<Map<String, dynamic>>> forSeller([String status = '']) async =>
      asMaps(asMap(await _api.get('/returns/seller', query: status.isEmpty ? null : {'status': status}))['returns']);
  static Future<void> approve(String id, String instructions) async => _api.post('/returns/$id/approve', body: {'instructions': instructions});
  static Future<void> reject(String id, String reason) async => _api.post('/returns/$id/reject', body: {'reason': reason});
  static Future<void> received(String id, {required bool restock}) async => _api.post('/returns/$id/received', body: {'restock': restock});
  static Future<void> refundNow(String id) async => _api.post('/returns/$id/refund');

  // Ikiguzi
  static Future<List<Map<String, dynamic>>> forAdmin([String status = '']) async =>
      asMaps(asMap(await _api.get('/returns/admin', query: status.isEmpty ? null : {'status': status}))['returns']);
  static Future<void> decide(String id, String decision, String note) async => _api.post('/returns/$id/decide', body: {'decision': decision, 'note': note});
}
