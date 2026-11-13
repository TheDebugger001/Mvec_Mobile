import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// `/admin/audit-logs` — every admin change.
class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final _q = TextEditingController();
  String _query = '';
  String _type = '';
  int _page = 1;
  late Loader<Map<String, dynamic>> _data = _load();

  Loader<Map<String, dynamic>> _load() => Loader(() => jget('/admin/audit-logs', {'page': _page, 'pageSize': 30, 'q': _query, 'targetType': _type}));

  void _reload(VoidCallback change) {
    final old = _data;
    setState(() {
      change();
      _data = _load();
    });
    old.dispose();
  }

  @override
  void dispose() {
    _data.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Platform',
      title: 'Audit log',
      subtitle: 'Every change an administrator makes is recorded here automatically: who, what and when. Entries cannot be edited or deleted.',
      onRefresh: _data.reload,
      children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: 'Search action or admin', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          onSubmitted:
              (v) => _reload(() {
                _page = 1;
                _query = v.trim();
              }),
        ),
        const SizedBox(height: 10),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading the audit log…',
          builder: (d) {
            final types = [for (final t in (d['targetTypes'] is List ? d['targetTypes'] as List : const [])) '$t'];
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total']).toInt();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilterSelect(
                  label: 'About',
                  value: _type,
                  options: [('', 'Everything'), for (final t in types) (t, t)],
                  onChanged:
                      (v) => _reload(() {
                        _type = v;
                        _page = 1;
                      }),
                ),
                const SizedBox(height: 10),
                Tiny('$total recorded'),
                if (rows.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'No admin actions recorded yet.'),
                for (final r in rows)
                  RecordCard(
                    title: strOf(r['action']),
                    subtitle: '${r['actor'] ?? ''} · ${formatDateTime(r['at'])}',
                    lines: [if (strOf(asMap(r['detail'])['reason']).isNotEmpty) '“${asMap(r['detail'])['reason']}”', 'About: ${strOf(r['targetType'], '—')}'],
                  ),
                if (total > 30) PaginationBar(page: _page, total: total, perPage: 30, onPage: (p) => _reload(() => _page = p)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Commission rules ───────────────────────────────────────────────────────
