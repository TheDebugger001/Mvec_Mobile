import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../widgets/common.dart';

String partyName(dynamic p) => p is Map ? strOf(p['companyName'] ?? p['Fullname'] ?? p['fullName'] ?? p['email'], '—') : '—';

String locationOf(Map<String, dynamic> s) {
  final l = s['location'];
  if (l == null) return 'Rwanda';
  if (l is String) return l.isEmpty ? 'Rwanda' : l;
  final m = asMap(l);
  final parts = [m['sector'], m['district'] ?? m['city'], m['province']].where((x) => strOf(x).isNotEmpty).join(', ');
  return parts.isEmpty ? 'Rwanda' : parts;
}

/// [fromCatalog]: called from the catalog screen, which sits on top of the
/// dashboard, so it closes first and the chat opens in the dashboard.
Future<void> messageSupplier(BuildContext context, Map<String, dynamic> s, {bool fromCatalog = false}) async {
  try {
    await jpost('/conversations', {'recipientId': idOf(s['user']), 'subject': 'Wholesale enquiry: ${s['businessName']}'});
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    if (fromCatalog) Navigator.of(context).pop();
    router.go('/vendor/messages');
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
  }
}

/// Units a wholesale listing can be sold in.
const units = ['piece', 'pack', 'box', 'carton', 'dozen', 'set', 'pair', 'bag', 'sack', 'kg', 'g', 'litre', 'ml', 'metre', 'roll', 'bottle', 'crate', 'tray'];
