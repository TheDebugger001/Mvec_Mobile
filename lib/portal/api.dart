import '../core/api_client.dart';
import '../core/format.dart';

// Short JSON helpers for the dashboards. Every call goes through the same
// client as the storefront (token, error messages, session handling).

final _api = Api.instance;

Future<Map<String, dynamic>> jget(String path, [Map<String, dynamic>? query]) async => asMap(await _api.get(path, query: query));
Future<Map<String, dynamic>> jpost(String path, [Object? body]) async => asMap(await _api.post(path, body: body ?? const {}));
Future<Map<String, dynamic>> jput(String path, [Object? body]) async => asMap(await _api.put(path, body: body ?? const {}));
Future<Map<String, dynamic>> jpatch(String path, [Object? body]) async => asMap(await _api.patch(path, body: body ?? const {}));
Future<Map<String, dynamic>> jdelete(String path, [Object? body]) async => asMap(await _api.delete(path, body: body));

/// `GET` and read one list out of the response (`{orders:[...]}`).
Future<List<Map<String, dynamic>>> jlist(String path, String key, [Map<String, dynamic>? query]) async => asMaps((await jget(path, query))[key]);

/// Seller products with `id` always set (`productsApi.getVendorProducts`).
Future<List<Map<String, dynamic>>> vendorProducts() async => [
  for (final p in await jlist('/products/vendor/me', 'products')) {...p, 'id': idOf(p)},
];

/// Builds the product body the backend expects (`toProductPayload` on the web).
Map<String, dynamic> productPayload(Map<String, dynamic> f) {
  final out = <String, dynamic>{};
  for (final k in const [
    'name',
    'sku',
    'brand',
    'shortDescription',
    'description',
    'price',
    'discountPrice',
    'discountType',
    'discountValue',
    'costPrice',
    'stockQuantity',
    'lowStockThreshold',
    'status',
    'storeId',
  ]) {
    if (f.containsKey(k)) out[k] = f[k];
  }
  if (f['categoryId'] != null) out['category'] = f['categoryId'];
  final media = <String, dynamic>{};
  if (f.containsKey('mainImage')) media['mainImage'] = f['mainImage'];
  if (f.containsKey('gallery')) media['gallery'] = f['gallery'];
  if (media.isNotEmpty) out['media'] = media;
  final attrs = <String, dynamic>{};
  for (final k in const ['color', 'size', 'material', 'weight', 'capacity', 'model']) {
    if (f.containsKey(k)) attrs[k] = f[k];
  }
  if (attrs.isNotEmpty) out['attributes'] = attrs;
  return out;
}
