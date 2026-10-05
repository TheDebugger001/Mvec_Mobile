import 'home_service.dart';

/// Empty-state implementation of [HomeService].
///
/// The bundled feed this used to serve is gone, so the home screen now resolves
/// to a payload with no keys at all. `HomeFeed.fromJson` treats every missing key
/// as an empty list, which is exactly the empty state the carousel, category
/// grid, vendor rail and every product row are built to render.
class EmptyHomeService implements HomeService {
  EmptyHomeService({this.delay = Duration.zero});

  final Duration delay;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return const <String, dynamic>{};
  }
}
