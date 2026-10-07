import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class VendorProductImageStore {
  static const _key = 'mvec_vendor_product_local_images';

  Future<Map<String, List<String>>> _readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null || encoded.isEmpty) return {};
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Saved vendor product images are invalid.');
    }
    return decoded.map((key, value) {
      final paths =
          value is List
              ? value.map((path) => path.toString()).where((path) => path.isNotEmpty).toList()
              : value == null || value.toString().isEmpty
                  ? <String>[]
                  : <String>[value.toString()];
      return MapEntry(key.toString(), paths);
    });
  }

  Future<Map<String, List<String>>> readAll() => _readAll();

  Future<void> saveAll(String productId, List<String> paths) async {
    final images = await _readAll();
    final retained = paths.where((path) => path.isNotEmpty).toList();
    if (retained.isEmpty) {
      images.remove(productId);
    } else {
      images[productId] = retained;
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, jsonEncode(images));
    if (!saved) {
      throw StateError('Could not save the vendor product images on this device.');
    }
  }

  Future<void> save(String productId, String path) =>
      saveAll(productId, path.isEmpty ? const [] : [path]);

  Future<List<String>?> remove(String productId) async {
    final images = await _readAll();
    final removed = images.remove(productId);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, jsonEncode(images));
    if (!saved) {
      throw StateError('Could not remove the vendor product images from this device.');
    }
    return removed;
  }
}
