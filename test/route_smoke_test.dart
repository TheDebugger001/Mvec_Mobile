import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/fake_backend.dart';

/// Opens every route in the router as each role, twice: once with the backend
/// answering unknown calls with empty data, once with server errors. Collects
/// every exception, overflow and unexpected redirect, then fails with the
/// whole list so one run shows all of them.
class _AnyBackend extends FakeBackend {
  _AnyBackend(super.routes, {required this.failing});
  final bool failing;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path.replaceFirst(RegExp(r'^https?://[^/]+/api'), '');
    if (routes.containsKey('${options.method} $path')) return super.fetch(options, requestStream, cancelFuture);
    calls.add(Call(options.method, path, options.data, options.queryParameters));
    return ResponseBody.fromString(
      jsonEncode(failing ? {'message': 'Server error'} : <String, dynamic>{}),
      failing ? 500 : 200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }
}

const _portals = {'/vendor': 'vendor', '/supplier': 'supplier', '/affiliate': 'affiliate', '/delivery': 'delivery', '/admin': 'super_admin'};

String? _portalOf(String path) {
  for (final e in _portals.entries) {
    if (path == e.key || path.startsWith('${e.key}/')) return e.value;
  }
  return null;
}

/// Routes that render a page; aliases that only redirect elsewhere are skipped.
List<String> _paths(List<RouteBase> routes) => [
      for (final r in routes) ...[
        if (r is GoRoute && (r.builder != null || r.pageBuilder != null)) r.path,
        ..._paths(r.routes),
      ],
    ];

void main() {
  for (final failing in [false, true]) {
    for (final role in ['guest', 'buyer', 'vendor', 'supplier', 'affiliate', 'delivery', 'super_admin']) {
      testWidgets('every $role page opens (${failing ? 'server errors' : 'empty data'})', (tester) async {
        final backend = _AnyBackend({
          ...baseRoutes(),
          if (role != 'guest') 'GET /auth/me': (_) => (200, {'user': userJson(role)}),
        }, failing: failing);
        await pumpApp(tester, backend, token: role == 'guest' ? null : 'jwt-$role');

        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        final paths = {
          for (final p in _paths(router.configuration.routes))
            // /track/:code jumps on to the shop as soon as it loads; covered on its own.
            if (p != '/boot' && !p.contains(':section') && !p.startsWith('/track/'))
              p.replaceAll(':id', 'p1').replaceAll(':code', 'abc'),
        }.where((p) {
          final portal = _portalOf(p);
          return role == 'guest' || role == 'buyer' ? portal == null : portal == role;
        }).toList()
          ..sort();

        final problems = <String>[];
        final original = FlutterError.onError;
        var current = '';
        FlutterError.onError = (d) {
          final first = d.exceptionAsString().split('\n').first;
          final where = RegExp(r'file:///[^\s]*/lib/([^\s:]+:\d+)').firstMatch(d.toString())?.group(1) ?? '';
          problems.add('$current  →  $first ${where.isEmpty ? '' : '($where)'}');
        };
        try {
          for (final path in paths) {
            current = path;
            router.go(path);
            await settle(tester);
            final ex = tester.takeException();
            if (ex != null) problems.add('$path  →  ${'$ex'.split('\n').first}');
            final landed = router.routerDelegate.currentConfiguration.uri.path;
            final signInWall = role == 'guest' && landed == '/login';
            final alreadySignedIn = role != 'guest' && (path == '/login' || path == '/signup');
            if (landed != path && !signInWall && !alreadySignedIn) problems.add('$path  →  redirected to $landed');
            if (find.textContaining('Page not found').evaluate().isNotEmpty) problems.add('$path  →  shows "Page not found"');
          }
        } finally {
          FlutterError.onError = original;
        }
        // Every endpoint the screens called, for checking against the real backend.
        final out = Platform.environment['SMOKE_CALLS_OUT'];
        if (out != null && !failing) {
          File(out).writeAsStringSync(backend.calls.map((c) => '${c.method} ${c.path}\n').toSet().join(), mode: FileMode.append);
        }
        final unique = problems.toSet().toList();
        expect(unique, isEmpty, reason: '${unique.length} problem(s) as $role:\n${unique.join('\n')}');
      });
    }
  }
}
