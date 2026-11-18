import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Push notifications (Firebase Cloud Messaging): a rider's offer, "your
/// parcel is on its way", a price drop, even when the app is closed.
///
/// Off unless the build sets the Firebase app's keys (nothing secret):
///   --dart-define=FIREBASE_API_KEY=... FIREBASE_APP_ID=...
///   FIREBASE_SENDER_ID=... FIREBASE_PROJECT_ID=...
/// After sign-in the device's token is sent to `/api/notifications/devices`;
/// sign-out removes it. Tapping a notification opens its `link`.
class PushService {
  PushService._();
  static final instance = PushService._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  bool get configured => !kIsWeb && _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty;

  bool _ready = false;
  String? _token;
  StreamSubscription<String>? _refresh;

  /// Where a tapped notification should go (the router listens).
  final links = StreamController<String>.broadcast();

  Future<bool> _init() async {
    if (_ready) return true;
    if (!configured) return false;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId),
      );
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['link']));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _open(first.data['link']);
      _ready = true;
    } catch (e) {
      debugPrint('Push unavailable: $e');
    }
    return _ready;
  }

  void _open(Object? link) {
    final to = '${link ?? ''}';
    if (to.startsWith('/')) links.add(to);
  }

  /// After sign-in: ask permission (Android 13+ asks once) and register this phone.
  Future<void> register() async {
    if (!await _init()) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // The registration token is what the server's FCM v1 `token` field takes
      // (firebase_messaging 17's register()/onRegistered gives an installation id instead).
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await _send(_token!);
      // ignore: deprecated_member_use
      _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _send(t);
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _send(String token) => Api.instance.post('/notifications/devices', body: {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
      });

  /// Before sign-out (while the session still works): stop pushes to this phone.
  Future<void> unregister() async {
    final t = _token;
    if (!_ready || t == null) return;
    try {
      await Api.instance.delete('/notifications/devices', body: {'token': t});
    } catch (_) {
      // Signing out goes ahead; the server drops the token when it stops working.
    }
    _token = null;
  }
}
