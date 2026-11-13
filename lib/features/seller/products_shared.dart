import '../../core/format.dart';

String productImage(Map<String, dynamic> p) => strOf(asMap(p['media'])['mainImage'] ?? p['mainImage']);
