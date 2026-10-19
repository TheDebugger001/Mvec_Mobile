import '../core/api_client.dart';
import '../core/format.dart';

/// Notifications (`/api/notifications`).
class NotificationsApi {
  NotificationsApi._();
  static final _api = Api.instance;

  /// `{notifications, unreadCount}`
  static Future<({List<Map<String, dynamic>> items, int unread})> mine({int? limit}) async {
    final res = asMap(await _api.get('/notifications/mine', query: {'limit': limit}));
    final items = asMaps(res['data'])
        .map((n) => {...n, 'body': strOf(n['body'] ?? n['message'])})
        .toList();
    return (items: items, unread: numOf(asMap(res['meta'])['unreadCount']).toInt());
  }

  static Future<void> markRead(String id) async => _api.patch('/notifications/$id/read');
  static Future<void> markAllRead() async => _api.post('/notifications/read-all');
}

/// Direct messages (`/api/conversations`).
class ConversationsApi {
  ConversationsApi._();
  static final _api = Api.instance;

  static Future<List<Map<String, dynamic>>> all() async =>
      asMaps(asMap(await _api.get('/conversations'))['conversations']);

  static Future<List<Map<String, dynamic>>> messages(String id) async =>
      asMaps(asMap(await _api.get('/conversations/$id/messages'))['messages']);

  static Future<Map<String, dynamic>> send(String id, String text) async =>
      asMap(asMap(await _api.post('/conversations/$id/messages', body: {'content': text}))['message']);

  static Future<void> markRead(String id) async => _api.patch('/conversations/$id/read');

  static Future<List<Map<String, dynamic>>> contacts(String q) async =>
      asMaps(asMap(await _api.get('/conversations/contacts', query: {'q': q}))['contacts']);

  static Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async =>
      asMap(asMap(await _api.post('/conversations', body: payload))['conversation']);
}

/// Support tickets (`/api/support`).
class SupportApi {
  SupportApi._();
  static final _api = Api.instance;

  static Future<Map<String, dynamic>> createCase(Map<String, dynamic> payload) async =>
      asMap(await _api.post('/support/cases', body: payload));

  static Future<List<Map<String, dynamic>>> cases({int pageSize = 50}) async =>
      asMaps(asMap(await _api.get('/support/cases', query: {'pageSize': pageSize}))['cases']);

  static Future<Map<String, dynamic>> byId(String id) async =>
      asMap(asMap(await _api.get('/support/cases/$id'))['case']);

  static Future<void> comment(String id, String message) async =>
      _api.post('/support/cases/$id/comments', body: {'message': message});

  static Future<void> updateStatus(String id, String status) async =>
      _api.patch('/support/cases/$id/status', body: {'status': status});
}
