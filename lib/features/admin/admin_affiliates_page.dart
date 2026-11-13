import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// `/admin/affiliates` — affiliate accounts with block / unblock.
class AdminAffiliatesPage extends StatefulWidget {
  const AdminAffiliatesPage({super.key});

  @override
  State<AdminAffiliatesPage> createState() => _AdminAffiliatesPageState();
}

class _AdminAffiliatesPageState extends State<AdminAffiliatesPage> {
  late final _data = Loader(() => jlist('/affiliates', 'data'));
  String _busy = '';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Ikiguzi operations',
      title: 'Affiliates',
      subtitle: 'Manage affiliates using live marketplace account records.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search affiliates…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading affiliates…',
          builder: (rows) {
            final shown = rows.where((a) => matches(_q, [a['name'], a['Fullname'], a['email']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${rows.length} record${rows.length == 1 ? '' : 's'}'),
                if (shown.isEmpty) const EmptyState(icon: Icons.group_outlined, title: 'No affiliates here'),
                for (final a in shown)
                  Builder(
                    builder: (_) {
                      final status = strOf(a['status'], 'ACTIVE');
                      final blocked = status == 'BLOCK';
                      return RecordCard(
                        title: strOf(a['name'] ?? a['Fullname']),
                        subtitle: strOf(a['email']),
                        lines: ['${compact(a['clicks'])} clicks · ${numOf(a['conversions']).toInt()} conversions'],
                        amount: money(a['earnings']),
                        status: StatusChip(titleCase(status), tone: blocked ? StatusTone.bad : StatusTone.good),
                        actions: [
                          ActionChipBtn(
                            blocked ? 'Unblock' : 'Block',
                            danger: !blocked,
                            busy: _busy == idOf(a),
                            onPressed: () async {
                              if (!blocked && !await confirmDialog(context, 'Block ${strOf(a['name'] ?? a['Fullname'])}? They will not be able to log in.', confirm: 'Block', danger: true)) return;
                              if (!context.mounted) return;
                              setState(() => _busy = idOf(a));
                              final ok = await runAction(context, () => jpatch('/users/${idOf(a)}', {'status': blocked ? 'ACTIVE' : 'BLOCK'}), success: blocked ? 'Unblocked.' : 'Blocked.');
                              if (mounted) setState(() => _busy = '');
                              if (ok) _data.reload();
                            },
                          ),
                        ],
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Become a seller ────────────────────────────────────────────────────────
