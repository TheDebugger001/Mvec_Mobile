import '../../../../core/api_client.dart';
import 'home_service.dart';

/// Live marketplace home feed service.
class ApiHomeService implements HomeService {
  ApiHomeService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    final res = await _api.get('/home');
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw const FormatException('Home feed response was not an object');
  }
}
