/// Contract for the marketplace home feed data source.
///
/// Concrete implementations swap between the live backend
/// ([ApiHomeService], wrapped by [FallbackHomeService]) and
/// [EmptyHomeService] without touching the presentation layer or its providers.
abstract class HomeService {
  /// Fetches the home feed payload in a Map structure that mirrors the
  /// backend API response schema (`banners`, `categories`, `products`...).
  ///
  /// Returns a payload with no keys — rather than throwing — when the feed is
  /// simply empty or the endpoint is not available yet, so the screens render
  /// their empty state. Throws only for genuine failures the caller should show.
  Future<Map<String, dynamic>> getHomeFeed();

  /// True only when this service is serving a bundled/local dataset.
  bool get isDemo;
}