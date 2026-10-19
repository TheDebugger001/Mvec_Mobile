import '../models/user.dart';
import 'nav_items.dart';

/// Only follow in-app paths after login, never an external URL.
String safeRedirect(String? path) {
  if (path == null || !path.startsWith('/') || path.startsWith('//') || path.startsWith('/\\')) return '';
  if (path.startsWith('/login') || path.startsWith('/signup')) return '';
  return path;
}

String homeForRole(String? role) => roleHome[role] ?? '/';

/// Where to go right after signing in (`afterSignIn` in the web app): everyone
/// except buyers goes to their dashboard; buyers return to what they were doing.
String afterSignIn(AppUser? user, [String returnTo = '']) {
  if (user == null || user.role == 'buyer') return returnTo.isEmpty ? '/' : returnTo;
  final home = homeForRole(user.role);
  if (home == '/') return '/';
  return returnTo.isNotEmpty && (returnTo == home || returnTo.startsWith('$home/')) ? returnTo : home;
}
